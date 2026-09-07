"""Fine-Tuning Pipeline for OpenShift AI.

A 7-phase KFP pipeline supporting multiple fine-tuning techniques
(LoRA, SFT, OSFT, custom) via a `technique` parameter:

  Phase 1:   Dataset Download    -- S3/HF/HTTP -> chat-format JSONL, 90/10 train/eval split
  Phase 1.5: Data Quality Filter -- Dedup (exact + near), quality scoring, format validation
  Phase 2:   Format Validation   -- unitxt chat template enforcement + tokenization check
  Phase 3:   Training            -- dispatches to LoRA/SFT/OSFT/custom via TrainingHub
  Phase 4a:  Benchmark Eval      -- EvalHub + ephemeral vLLM KServe + MLflow logging
  Phase 4b:  Holdout Eval        -- lm-eval on held-out eval split (exact_match, BLEU, ROUGE)
  Phase 4c:  Quality Gate        -- enforce minimum eval score before registry
  Phase 5:   Model Registry      -- register trained model with provenance + all eval metrics

Submit from the RHOAI Dashboard -> Data Science Pipelines UI. No notebook needed.
"""

import os
import sys

import yaml
import kfp
import kfp.kubernetes
from kfp import dsl

# ---------------------------------------------------------------------------
# Load pipeline-config.yaml — single source of truth for all defaults.
# ---------------------------------------------------------------------------
_CONFIG_PATH = os.path.join(os.path.dirname(__file__), "pipeline-config.yaml")
with open(_CONFIG_PATH) as _f:
    _config = yaml.safe_load(_f)

_defaults = _config.get("defaults", {})
_infra = _config.get("infrastructure", {})
_services = _config.get("services", {})
_evaluation = _config.get("evaluation", {})
_pipeline = _config.get("pipeline", {})

# ---------------------------------------------------------------------------
# Import reusable components.
# ---------------------------------------------------------------------------
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "local_components"))

from local_components.train_model import train_model
from local_components.data_quality_filter import data_quality_filter
from local_components.unitxt_formatter import unitxt_format_validator

_PIPELINES_COMPONENTS = os.environ.get(
    "PIPELINES_COMPONENTS_PATH",
    os.path.join(os.path.dirname(__file__), "..", "..", "..", "..", "..", "..", "..", "..", "pipelines-components"),
)
sys.path.insert(0, _PIPELINES_COMPONENTS)

from components.data_processing.dataset_download import dataset_download
from local_components.model_registry import kubeflow_model_registry as model_registry
from local_components.evalhub_eval import evalhub_evaluator_kserve
from components.evaluation.lm_eval import universal_llm_evaluator

# =============================================================================
# PVC Configuration — from pipeline-config.yaml
# =============================================================================
PVC_SIZE = _infra.get("pvc_size", "50Gi")
PVC_STORAGE_CLASS = _infra.get("pvc_storage_class", "nfs-csi")
PVC_ACCESS_MODES = _infra.get("pvc_access_modes", ["ReadWriteMany"])
PIPELINE_NAME = _pipeline.get("name", "finetuning-pipeline")
PIPELINE_VERSION = _pipeline.get("version", "v5")


# =============================================================================
# Quality gate + consolidated MLflow logger
# =============================================================================
@dsl.component(
    base_image=_config.get("images", {}).get("pipeline_base", "quay.io/opendatahub/odh-th06-cpu-torch291-py312:odh-3.4"),
    packages_to_install=["mlflow>=2.12.0"],
)
def eval_quality_gate(
    eval_metrics: dsl.Input[dsl.Metrics],
    holdout_metrics: dsl.Input[dsl.Metrics],
    training_metrics: dsl.Input[dsl.Metrics],
    min_eval_score: float,
    run_name: str = "",
    mlflow_tracking_uri: str = "",
    mlflow_experiment_name: str = "",
) -> str:
    """Quality gate + consolidated MLflow logger.

    Logs training hyperparameters, EvalHub benchmarks, and holdout eval
    scores to a single MLflow run. Then checks eval scores against a
    minimum threshold before allowing model registration.

    Returns 'pass' or raises an exception to block downstream registry.
    """
    import os

    print("=" * 60)
    print(f"QUALITY GATE — {run_name or 'unnamed run'}")
    print("=" * 60)

    # -- Collect all metrics --
    _SKIP_KEYS = {"display_name", "store_session_info"}
    eval_meta = getattr(eval_metrics, "metadata", {}) or {}
    holdout_meta = getattr(holdout_metrics, "metadata", {}) or {}
    training_meta = getattr(training_metrics, "metadata", {}) or {}

    training_params = {}
    for k, v in training_meta.items():
        if k not in _SKIP_KEYS:
            training_params[k] = v
    if training_params:
        print(f"\n  Training: {len(training_params)} params")
        for k in ["technique", "num_epochs", "learning_rate", "effective_batch_size"]:
            if k in training_params:
                print(f"    {k}: {training_params[k]}")

    evalhub_score = None
    evalhub_state = eval_meta.get("evalhub_state", "unknown")
    if evalhub_state != "skipped":
        raw = eval_meta.get("eval_overall_score")
        if raw is not None:
            evalhub_score = float(raw)
            print(f"  EvalHub overall score: {evalhub_score:.4f}")

    holdout_scores = {}
    for k, v in holdout_meta.items():
        if k not in _SKIP_KEYS and isinstance(v, (int, float)):
            holdout_scores[k] = float(v)
    if holdout_scores:
        print(f"  Holdout: {len(holdout_scores)} metrics")
        for k, v in sorted(holdout_scores.items()):
            print(f"    {k}: {v:.4f}" if isinstance(v, float) else f"    {k}: {v}")

    # -- Log everything to MLflow in one run --
    if mlflow_tracking_uri and mlflow_experiment_name:
        try:
            os.environ["MLFLOW_TRACKING_URI"] = mlflow_tracking_uri
            os.environ["MLFLOW_TRACKING_INSECURE_TLS"] = "true"
            import mlflow

            mlflow.set_experiment(mlflow_experiment_name)
            mlflow_run_name = run_name or "finetuning-run"
            with mlflow.start_run(run_name=mlflow_run_name):
                for k, v in training_params.items():
                    if isinstance(v, (int, float)):
                        mlflow.log_metric(f"training/{k}", float(v))
                    else:
                        mlflow.log_param(f"training/{k}", str(v))
                for k, v in holdout_scores.items():
                    mlflow.log_metric(f"holdout/{k}", v)
                if evalhub_score is not None:
                    mlflow.log_metric("evalhub/overall_score", evalhub_score)
                for k, v in eval_meta.items():
                    if k not in _SKIP_KEYS and isinstance(v, (int, float)):
                        mlflow.log_metric(f"evalhub/{k}", float(v))
            total = len(training_params) + len(holdout_scores) + (1 if evalhub_score else 0)
            print(f"  MLflow: logged {total} metrics/params as '{mlflow_run_name}' in '{mlflow_experiment_name}'")
        except Exception as e:
            print(f"  MLflow logging failed (non-fatal): {e}")

    # -- Quality gate check --
    best_score = evalhub_score
    if best_score is None and holdout_scores:
        best_score = max(holdout_scores.values())
    if best_score is None:
        best_score = 0.0

    print(f"\n  Best score:     {best_score:.4f}")
    print(f"  Min threshold:  {min_eval_score:.4f}")

    if min_eval_score > 0.0 and best_score < min_eval_score:
        msg = (
            f"QUALITY GATE FAILED: best score {best_score:.4f} < "
            f"threshold {min_eval_score:.4f}. Model will NOT be registered."
        )
        print(f"\n  {msg}")
        raise ValueError(msg)

    print("\n  QUALITY GATE PASSED")
    print("=" * 60)
    return "pass"


@dsl.pipeline(
    name=PIPELINE_NAME,
    description=_pipeline.get("description", "Fine-tuning pipeline"),
    pipeline_config=dsl.PipelineConfig(
        workspace=dsl.WorkspaceConfig(
            size=PVC_SIZE,
            kubernetes=dsl.KubernetesWorkspaceConfig(
                pvcSpecPatch={
                    "accessModes": PVC_ACCESS_MODES,
                    "storageClassName": PVC_STORAGE_CLASS,
                }
            ),
        ),
    ),
)
def finetuning_pipeline(
    # =========================================================================
    # RUN IDENTITY
    # =========================================================================
    run_name: str = _defaults.get("run_name", "lora-qwen25-finetuning"),

    # =========================================================================
    # TECHNIQUE SELECTION
    # =========================================================================
    technique: str = _defaults.get("technique", "lora"),

    # =========================================================================
    # PHASE 1: DATASET
    # =========================================================================
    dataset_uri: str = _defaults.get("dataset_uri", "hf://b-mc2/sql-create-context"),
    dataset_subset: int = _defaults.get("dataset_subset", 5000),
    train_split_ratio: float = _defaults.get("train_split_ratio", 0.9),

    # PHASE 1.5: DATA QUALITY
    similarity_threshold: float = 0.85,
    enable_llm_judge: bool = False,
    llm_judge_endpoint: str = "",
    llm_judge_model: str = "judge",

    # PHASE 2: FORMAT VALIDATION (unitxt)
    system_prompt: str = "You are a helpful assistant.",

    # =========================================================================
    # PHASE 2: MODEL SELECTION
    # =========================================================================
    base_model: str = _defaults.get("base_model", "Qwen/Qwen2.5-1.5B-Instruct"),

    # =========================================================================
    # PHASE 3: TRAINING -- Common
    # =========================================================================
    epochs: int = _defaults.get("epochs", 2),
    learning_rate: float = _defaults.get("learning_rate", 2e-4),
    effective_batch_size: int = _defaults.get("effective_batch_size", 128),
    max_seq_len: int = _defaults.get("max_seq_len", 8192),
    max_tokens_per_gpu: int = _defaults.get("max_tokens_per_gpu", 32000),
    gpu_per_worker: int = _defaults.get("gpu_per_worker", 1),
    num_workers: int = _defaults.get("num_workers", 1),
    cpu_per_worker: str = str(_defaults.get("cpu_per_worker", "4")),
    memory_per_worker: str = _defaults.get("memory_per_worker", "32Gi"),
    training_runtime: str = _defaults.get("training_runtime", "training-hub"),
    seed: int = _defaults.get("seed", 42),
    use_liger: bool = True,
    lr_scheduler: str = "cosine",
    env_vars: str = "",
    labels: str = "",
    annotations: str = "",

    # PHASE 3: TRAINING -- LoRA-specific
    lora_r: int = 16,
    lora_alpha: int = 32,
    lora_dropout: float = 0.0,
    lora_target_modules: str = "",
    lora_load_in_4bit: bool = True,
    lora_load_in_8bit: bool = False,
    lora_sample_packing: bool = True,
    lora_micro_batch_size: int = 2,
    lora_grad_accum_steps: int = 1,
    lora_flash_attention: bool = True,
    lora_bf16: bool = True,

    # PHASE 3: TRAINING -- SFT-specific
    sft_fsdp_sharding: str = "",
    sft_save_samples: int = 0,
    sft_accelerate_full_state_at_epoch: bool = False,

    # PHASE 3: TRAINING -- OSFT-specific
    osft_unfreeze_ratio: float = 0.25,
    osft_target_patterns: str = "",
    osft_memory_efficient_init: bool = True,
    osft_unmask_messages: bool = False,
    osft_use_processed_dataset: bool = False,
    osft_lr_scheduler_kwargs: str = "",
    osft_save_final_checkpoint: bool = True,
    osft_fsdp_sharding: str = "",

    # =========================================================================
    # PHASE 4a: BENCHMARK EVALUATION (EvalHub + MLflow)
    # =========================================================================
    evalhub_url: str = _services.get("evalhub_url", ""),
    evalhub_collection: str = "",
    evalhub_benchmarks: list = _evaluation.get("benchmarks", []),
    mlflow_experiment: str = _services.get("mlflow_experiment", "finetuning-experiments"),
    eval_timeout: int = _evaluation.get("timeout", 7200),
    eval_gpu_count: int = _evaluation.get("gpu_count", 1),
    eval_cpu: str = str(_evaluation.get("cpu", "2")),
    eval_memory: str = _evaluation.get("memory", "32Gi"),

    # =========================================================================
    # PHASE 4b: HOLDOUT EVALUATION (lm-eval on task-specific eval split)
    # =========================================================================
    holdout_eval_tasks: list = _evaluation.get("holdout_tasks", ["arc_easy"]),
    holdout_eval_limit: int = _evaluation.get("holdout_limit", 100),
    holdout_eval_batch_size: str = "auto",
    holdout_enforce_eager: bool = True,

    # =========================================================================
    # PHASE 4c: QUALITY GATE (0.0 = disabled, any positive value = threshold)
    # =========================================================================
    min_eval_score: float = _evaluation.get("min_eval_score", 0.0),

    # =========================================================================
    # PHASE 5: MODEL REGISTRY
    # =========================================================================
    registry_address: str = _services.get("registry_address", ""),
    registry_port: int = _services.get("registry_port", 8443),
    registry_model_name: str = "finetuned-model",
    registry_model_version: str = "1.0.0",
    registry_author: str = "pipeline",
    registry_description: str = "",
    registry_stage: str = _defaults.get("registry_stage", "dev"),
):
    """Fine-Tuning Pipeline.

    A 7-phase pipeline supporting multiple fine-tuning techniques in a single
    DAG. Select the technique at run time via the ``technique`` parameter.

    Techniques:
      - lora:   Parameter-efficient LoRA/QLoRA via unsloth (single-node, fast)
      - sft:    Full supervised fine-tuning via instructlab-training (multi-node, FSDP)
      - osft:   Orthogonal Subspace FT via mini-trainer (preserves base capabilities)
      - custom: Bring-your-own training code (plain PyTorch demo)
    """
    # =========================================================================
    # Phase 1: Dataset Download (90/10 train/eval split)
    # =========================================================================
    dataset_task = dataset_download(
        dataset_uri=dataset_uri,
        pvc_mount_path=dsl.WORKSPACE_PATH_PLACEHOLDER,
        train_split_ratio=train_split_ratio,
        subset_count=dataset_subset,
        shared_log_file="pipeline_log.txt",
    )
    dataset_task.set_caching_options(False)
    kfp.kubernetes.set_image_pull_policy(dataset_task, "IfNotPresent")

    kfp.kubernetes.use_secret_as_env(
        dataset_task,
        secret_name="s3-secret",
        secret_key_to_env={
            "AWS_ACCESS_KEY_ID": "AWS_ACCESS_KEY_ID",
            "AWS_SECRET_ACCESS_KEY": "AWS_SECRET_ACCESS_KEY",
        },
        optional=True,
    )

    # =========================================================================
    # Phase 1.5: Data Quality Filter (dedup + quality scoring)
    # =========================================================================
    quality_task = data_quality_filter(
        input_dataset=dataset_task.outputs["train_dataset"],
        pvc_mount_path=dsl.WORKSPACE_PATH_PLACEHOLDER,
        similarity_threshold=similarity_threshold,
        min_assistant_tokens=5,
        min_user_tokens=3,
        export_to_pvc=True,
        shared_log_file="pipeline_log.txt",
        enable_llm_judge=enable_llm_judge,
        llm_judge_endpoint=llm_judge_endpoint,
        llm_judge_model=llm_judge_model,
        mlflow_tracking_uri="https://mlflow.redhat-ods-applications.svc.cluster.local:8443" if mlflow_experiment else "",
        mlflow_experiment_name="finetuning-datasets",
    )
    quality_task.set_caching_options(False)
    kfp.kubernetes.set_image_pull_policy(quality_task, "IfNotPresent")

    kfp.kubernetes.use_secret_as_env(
        quality_task,
        secret_name="gemini-api-key",
        secret_key_to_env={"GEMINI_API_KEY": "api-key"},
        optional=True,
    )

    # =========================================================================
    # Phase 2: Format Validation (unitxt)
    #   Enforces standard system prompt, validates chat template structure,
    #   checks tokenization fits within max_seq_len.
    # =========================================================================
    format_task = unitxt_format_validator(
        input_dataset=quality_task.outputs["output_dataset"],
        base_model=base_model,
        system_prompt=system_prompt,
        max_seq_len=max_seq_len,
        pvc_mount_path=dsl.WORKSPACE_PATH_PLACEHOLDER,
    )
    format_task.set_caching_options(False)
    kfp.kubernetes.set_image_pull_policy(format_task, "IfNotPresent")

    # =========================================================================
    # Phase 3: Training (dispatches to LoRA/SFT/OSFT/custom)
    # =========================================================================
    training_task = train_model(
        technique=technique,
        pvc_path=dsl.WORKSPACE_PATH_PLACEHOLDER,
        dataset=format_task.outputs["output_dataset"],
        training_base_model=base_model,
        training_effective_batch_size=effective_batch_size,
        training_max_tokens_per_gpu=max_tokens_per_gpu,
        training_max_seq_len=max_seq_len,
        training_learning_rate=learning_rate,
        training_num_epochs=epochs,
        training_seed=seed,
        training_use_liger=use_liger,
        training_lr_scheduler=lr_scheduler,
        training_envs=env_vars,
        training_resource_cpu_per_worker=cpu_per_worker,
        training_resource_gpu_per_worker=gpu_per_worker,
        training_resource_memory_per_worker=memory_per_worker,
        training_resource_num_workers=num_workers,
        training_metadata_labels=labels,
        training_metadata_annotations=annotations,
        training_runtime=training_runtime,
        # LoRA
        lora_r=lora_r,
        lora_alpha=lora_alpha,
        lora_dropout=lora_dropout,
        lora_target_modules=lora_target_modules,
        lora_load_in_4bit=lora_load_in_4bit,
        lora_load_in_8bit=lora_load_in_8bit,
        lora_sample_packing=lora_sample_packing,
        lora_micro_batch_size=lora_micro_batch_size,
        lora_gradient_accumulation_steps=lora_grad_accum_steps,
        lora_flash_attention=lora_flash_attention,
        lora_bf16=lora_bf16,
        # SFT
        sft_fsdp_sharding_strategy=sft_fsdp_sharding,
        sft_save_samples=sft_save_samples,
        sft_accelerate_full_state_at_epoch=sft_accelerate_full_state_at_epoch,
        # OSFT
        osft_unfreeze_rank_ratio=osft_unfreeze_ratio,
        osft_target_patterns=osft_target_patterns,
        osft_memory_efficient_init=osft_memory_efficient_init,
        osft_unmask_messages=osft_unmask_messages,
        osft_use_processed_dataset=osft_use_processed_dataset,
        osft_lr_scheduler_kwargs=osft_lr_scheduler_kwargs,
        osft_save_final_checkpoint=osft_save_final_checkpoint,
        osft_fsdp_sharding_strategy=osft_fsdp_sharding,
    )
    training_task.set_caching_options(False)
    kfp.kubernetes.set_image_pull_policy(training_task, "IfNotPresent")
    kfp.kubernetes.add_toleration(training_task, key="nvidia.com/gpu", operator="Exists", effect="NoSchedule")
    kfp.kubernetes.add_node_selector(training_task, "nvidia.com/gpu.present", "true")

    kfp.kubernetes.use_secret_as_env(
        task=training_task,
        secret_name="kubernetes-credentials",
        secret_key_to_env={
            "KUBERNETES_SERVER_URL": "KUBERNETES_SERVER_URL",
            "KUBERNETES_AUTH_TOKEN": "KUBERNETES_AUTH_TOKEN",
        },
        optional=False,
    )
    kfp.kubernetes.use_secret_as_env(
        task=training_task,
        secret_name="oci-pull-secret-model-download",
        secret_key_to_env={"OCI_PULL_SECRET_MODEL_DOWNLOAD": "OCI_PULL_SECRET_MODEL_DOWNLOAD"},
        optional=True,
    )

    # =========================================================================
    # Phase 4a: Benchmark Evaluation via EvalHub (KServe vLLM + MLflow)
    # =========================================================================
    eval_task = evalhub_evaluator_kserve(
        pvc_mount_path=dsl.WORKSPACE_PATH_PLACEHOLDER,
        model_artifact=training_task.outputs["output_model"],
        evalhub_url=evalhub_url,
        collection_id=evalhub_collection,
        benchmarks=evalhub_benchmarks,
        evalhub_model_name="finetuned-model",
        base_model_name=base_model,
        evalhub_job_name=f"{PIPELINE_NAME}-eval",
        evalhub_timeout=eval_timeout,
        evalhub_poll_interval=30,
        mlflow_experiment_name=mlflow_experiment,
        gpu_count=eval_gpu_count,
        memory=eval_memory,
        cpu=eval_cpu,
    )
    eval_task.set_caching_options(False)
    kfp.kubernetes.set_image_pull_policy(eval_task, "IfNotPresent")

    # =========================================================================
    # Phase 4b: Holdout Evaluation (upstream component + CUDA image via post-compile patch)
    # =========================================================================
    holdout_eval_task = universal_llm_evaluator(
        model_artifact=training_task.outputs["output_model"],
        eval_dataset=dataset_task.outputs["eval_dataset"],
        task_names=holdout_eval_tasks,
        batch_size=holdout_eval_batch_size,
        limit=holdout_eval_limit,
        log_samples=True,
        model_args={"enforce_eager": holdout_enforce_eager},
    )
    holdout_eval_task.after(eval_task)
    holdout_eval_task.set_caching_options(False)
    kfp.kubernetes.set_image_pull_policy(holdout_eval_task, "IfNotPresent")
    holdout_eval_task.set_accelerator_type("nvidia.com/gpu")
    holdout_eval_task.set_accelerator_limit(1)
    kfp.kubernetes.add_node_selector(holdout_eval_task, "nvidia.com/gpu.present", "true")
    kfp.kubernetes.add_toleration(holdout_eval_task, key="nvidia.com/gpu", operator="Exists", effect="NoSchedule")

    # vLLM JIT workarounds — eval image (ubi9) lacks CUDA toolkit;
    # post-compile patch in build_pipeline.py swaps to CUDA image.
    holdout_eval_task.set_env_variable("VLLM_ATTENTION_BACKEND", "FLASH_ATTN")
    holdout_eval_task.set_env_variable("VLLM_USE_FLASHINFER_SAMPLER", "0")
    holdout_eval_task.set_env_variable("FLASHINFER_ENABLE_AOT", "1")

    # HF token for all steps that may download gated models or datasets
    for _task in [dataset_task, training_task, eval_task, holdout_eval_task]:
        kfp.kubernetes.use_secret_as_env(
            task=_task,
            secret_name="hf-token",
            secret_key_to_env={"HF_TOKEN": "HF_TOKEN"},
            optional=True,
        )

    # =========================================================================
    # Phase 4c: Quality Gate + Consolidated MLflow Logger
    #   Logs training params, eval benchmarks, holdout scores to one MLflow run.
    #   Blocks registry if score < min_eval_score.
    # =========================================================================
    mlflow_uri = "https://mlflow.redhat-ods-applications.svc.cluster.local:8443" if mlflow_experiment else ""
    gate_task = eval_quality_gate(
        eval_metrics=eval_task.outputs["output_metrics"],
        holdout_metrics=holdout_eval_task.outputs["output_metrics"],
        training_metrics=training_task.outputs["output_metrics"],
        min_eval_score=min_eval_score,
        run_name=run_name,
        mlflow_tracking_uri=mlflow_uri,
        mlflow_experiment_name=mlflow_experiment if mlflow_experiment else "",
    )
    gate_task.set_caching_options(False)
    kfp.kubernetes.set_image_pull_policy(gate_task, "IfNotPresent")

    # =========================================================================
    # Phase 5: Model Registry (only runs if quality gate passes)
    #   Includes stage label (dev/staging/prod) for promotion workflow.
    # =========================================================================
    registry_task = model_registry(
        pvc_mount_path=dsl.WORKSPACE_PATH_PLACEHOLDER,
        input_model=training_task.outputs["output_model"],
        input_metrics=training_task.outputs["output_metrics"],
        eval_metrics=eval_task.outputs["output_metrics"],
        eval_results=eval_task.outputs["output_results"],
        registry_address=registry_address,
        registry_port=registry_port,
        model_name=registry_model_name,
        model_version=registry_model_version,
        model_format_name="pytorch",
        model_format_version="1.0",
        model_description=registry_description,
        author=registry_author,
        registry_stage=registry_stage,
        shared_log_file="pipeline_log.txt",
        source_pipeline_name=PIPELINE_NAME,
        source_pipeline_run_id=dsl.PIPELINE_JOB_ID_PLACEHOLDER,
        source_pipeline_run_name=run_name,
        source_namespace="",
    )
    registry_task.after(gate_task)
    registry_task.set_caching_options(False)
    kfp.kubernetes.set_image_pull_policy(registry_task, "IfNotPresent")


if __name__ == "__main__":
    from kfp.compiler.compiler_utils import KubernetesManifestOptions

    kfp.compiler.Compiler().compile(
        pipeline_func=finetuning_pipeline,
        package_path=__file__.replace(".py", ".yaml"),
        kubernetes_manifest_format=True,
        kubernetes_manifest_options=KubernetesManifestOptions(
            pipeline_name=PIPELINE_NAME,
            pipeline_version_name=PIPELINE_VERSION,
            namespace=_infra.get("namespace", "fine-tuning-demo"),
            include_pipeline_manifest=True,
        ),
    )
