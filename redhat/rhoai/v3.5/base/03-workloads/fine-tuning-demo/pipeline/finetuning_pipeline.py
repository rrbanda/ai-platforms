"""Fine-Tuning Pipeline for OpenShift AI.

A 7-phase KFP pipeline supporting multiple fine-tuning techniques
(LoRA, SFT, OSFT, custom) via a `technique` parameter:

  Phase 1:   Dataset Download    -- S3/HF/HTTP -> chat-format JSONL, 90/10 train/eval split
  Phase 1.5: Data Quality Filter -- Dedup (exact + near), quality scoring, format validation
  Phase 2:   Model Download      -- Pre-cache base model to PVC (idempotent)
  Phase 3:   Training            -- dispatches to LoRA/SFT/OSFT/custom via TrainingHub
  Phase 4a:  Benchmark Eval      -- EvalHub + ephemeral vLLM KServe + MLflow logging
  Phase 4b:  Holdout Eval        -- lm-eval on held-out eval split (exact_match, BLEU, ROUGE)
  Phase 5:   Model Registry      -- register trained model with provenance + all eval metrics

All RHOAI components used are GA as of 3.4:
  - Data Science Pipelines (KFP 2.16.0) + Argo Workflows (v3.7.3)
  - Kubeflow Trainer v2 (2.1.0) with training-hub ClusterTrainingRuntime
  - KServe (0.17.0) with vLLM serving runtime
  - TrustyAI (1.37.0) + LMEval (0.4.8) + EvalHub/AI Hub (0.3.9)
  - MLflow (3.10.1) -- pipeline-level experiment tracking via EvalHub
  - Model Registry

Submit from the RHOAI Dashboard -> Data Science Pipelines UI. No notebook needed.
"""

import sys
import os

import kfp
import kfp.kubernetes
from kfp import dsl

# ---------------------------------------------------------------------------
# Import reusable components.
#
# At compile time, `pipelines-components` must be on PYTHONPATH or set
# PIPELINES_COMPONENTS_PATH. At runtime the compiled YAML is self-contained.
# ---------------------------------------------------------------------------
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "local_components"))

from local_components.train_model import train_model
from local_components.data_quality_filter import data_quality_filter

_PIPELINES_COMPONENTS = os.environ.get(
    "PIPELINES_COMPONENTS_PATH",
    os.path.join(os.path.dirname(__file__), "..", "..", "..", "..", "..", "..", "..", "..", "pipelines-components"),
)
sys.path.insert(0, _PIPELINES_COMPONENTS)

from components.data_processing.dataset_download import dataset_download
from components.deployment.kubeflow_model_registry import (
    kubeflow_model_registry as model_registry,
)
from components.evaluation.evalhub.kserve import evalhub_evaluator_kserve
from components.evaluation.lm_eval import universal_llm_evaluator


# =============================================================================
# PVC Configuration — KFP workspace auto-provisioning with gp3-csi (EBS).
# KFP creates and mounts a workspace PVC automatically per pipeline run.
# All tasks use dsl.WORKSPACE_PATH_PLACEHOLDER for the mount path.
# =============================================================================
PVC_SIZE = "50Gi"
PVC_STORAGE_CLASS = "nfs-csi"
PVC_ACCESS_MODES = ["ReadWriteMany"]
PIPELINE_NAME = "finetuning-pipeline"


# =============================================================================
# Inline model download component (avoids kfp_components.utils.consts import)
# =============================================================================
@dsl.component(
    base_image="quay.io/opendatahub/odh-th06-cpu-torch291-py312:odh-3.4",
    packages_to_install=["huggingface_hub>=0.20.0"],
)
def download_base_model(
    model_name: str,
    pvc_mount_path: str,
) -> str:
    """Pre-cache a HuggingFace model to the workspace PVC.

    Idempotent: skips download if model already cached (sentinel file check).
    This ensures the model is available on shared PVC for training and eval
    without re-downloading on every pipeline run.

    Args:
        model_name: HuggingFace model ID (e.g. 'Qwen/Qwen2.5-1.5B-Instruct').
        pvc_mount_path: Workspace PVC mount path.

    Returns:
        The sub-path on PVC where the model is cached.
    """
    import os

    from huggingface_hub import snapshot_download

    model_dir_name = model_name.replace("/", "--")
    model_path = os.path.join(pvc_mount_path, "models", model_dir_name)
    sentinel = os.path.join(model_path, ".download_complete")

    if os.path.exists(sentinel):
        file_count = sum(1 for _ in os.scandir(model_path) if _.is_file())
        print(f"Model '{model_name}' already cached at {model_path} ({file_count} files). Skipping.")
        return model_dir_name

    print(f"Downloading model '{model_name}' to {model_path}...")
    os.makedirs(model_path, exist_ok=True)
    snapshot_download(
        repo_id=model_name,
        local_dir=model_path,
        local_dir_use_symlinks=False,
    )

    with open(sentinel, "w") as f:
        f.write(model_name)

    file_count = sum(1 for _ in os.scandir(model_path) if _.is_file())
    print(f"Model '{model_name}' downloaded ({file_count} files).")
    return model_dir_name


@dsl.pipeline(
    name=PIPELINE_NAME,
    description=(
        "Fine-tuning pipeline supporting LoRA, SFT, OSFT, and custom "
        "techniques. Includes dataset preparation with train/eval split, "
        "model pre-caching, distributed training, benchmark evaluation "
        "via EvalHub with MLflow, holdout evaluation on task-specific data, "
        "and model registry with full provenance."
    ),
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
    # TECHNIQUE SELECTION
    # =========================================================================
    technique: str = "lora",

    # =========================================================================
    # PHASE 1: DATASET
    # =========================================================================
    dataset_uri: str = "hf://b-mc2/sql-create-context",
    dataset_subset: int = 5000,
    train_split_ratio: float = 0.9,

    # PHASE 1.5: DATA QUALITY (dedup, quality scoring, optional LLM judge)
    similarity_threshold: float = 0.85,
    enable_llm_judge: bool = False,
    llm_judge_endpoint: str = "",

    # =========================================================================
    # PHASE 2: MODEL SELECTION
    # =========================================================================
    base_model: str = "Qwen/Qwen2.5-1.5B-Instruct",

    # =========================================================================
    # PHASE 3: TRAINING -- Common
    # =========================================================================
    epochs: int = 2,
    learning_rate: float = 2e-4,
    effective_batch_size: int = 128,
    max_seq_len: int = 8192,
    max_tokens_per_gpu: int = 32000,
    gpu_per_worker: int = 1,
    num_workers: int = 1,
    cpu_per_worker: str = "4",
    memory_per_worker: str = "24Gi",
    training_runtime: str = "training-hub",
    seed: int = 42,
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

    # PHASE 3: TRAINING -- OSFT-specific
    osft_unfreeze_ratio: float = 0.1,
    osft_target_patterns: str = "",

    # =========================================================================
    # PHASE 4a: BENCHMARK EVALUATION (EvalHub + MLflow)
    #   Accuracy benchmarks (leaderboard-v2) + Safety benchmarks
    # =========================================================================
    evalhub_url: str = "https://evalhub.redhat-ods-applications.svc.cluster.local:8443",
    evalhub_collection: str = "",
    evalhub_benchmarks: list = [
        # Accuracy (leaderboard-v2)
        {"id": "leaderboard_ifeval", "provider_id": "lm_evaluation_harness"},
        {"id": "leaderboard_bbh", "provider_id": "lm_evaluation_harness"},
        {"id": "leaderboard_mmlu_pro", "provider_id": "lm_evaluation_harness"},
        {"id": "leaderboard_musr", "provider_id": "lm_evaluation_harness"},
        {"id": "leaderboard_math_hard", "provider_id": "lm_evaluation_harness"},
        # Safety & fairness — verifies fine-tuning didn't degrade guardrails
        {"id": "truthfulqa_mc1", "provider_id": "lm_evaluation_harness"},
        {"id": "toxigen", "provider_id": "lm_evaluation_harness"},
        {"id": "ethics_cm", "provider_id": "lm_evaluation_harness"},
    ],
    mlflow_experiment: str = "finetuning-experiments",
    eval_timeout: int = 7200,
    eval_gpu_count: int = 1,
    eval_cpu: str = "2",
    eval_memory: str = "32Gi",

    # =========================================================================
    # PHASE 4b: HOLDOUT EVALUATION (lm-eval on task-specific eval split)
    # =========================================================================
    holdout_eval_tasks: list = ["arc_easy"],
    holdout_eval_limit: int = 100,
    holdout_eval_batch_size: str = "auto",

    # =========================================================================
    # PHASE 5: MODEL REGISTRY
    # =========================================================================
    registry_address: str = "fine-tuning-demo.rhoai-model-registries.svc.cluster.local",
    registry_port: int = 8443,
    registry_model_name: str = "finetuned-model",
    registry_model_version: str = "1.0.0",
    registry_author: str = "pipeline",
    registry_description: str = "",
):
    """Fine-Tuning Pipeline.

    A 6-phase pipeline supporting multiple fine-tuning techniques in a single
    DAG. Select the technique at run time via the `technique` parameter.

    Techniques:
      - lora:   Parameter-efficient LoRA/QLoRA via unsloth (single-node, fast)
      - sft:    Full supervised fine-tuning via instructlab-training (multi-node, FSDP)
      - osft:   Orthogonal Subspace FT via mini-trainer (preserves base capabilities)
      - custom: Bring-your-own training code (plain PyTorch demo)

    Evaluation:
      - Phase 4a: EvalHub benchmarks — accuracy (MMLU, ifeval, bbh) AND safety
        (truthfulqa, toxigen, ethics) + MLflow experiment tracking.
        Answers: "Is the model capable AND safe after fine-tuning?"
      - Phase 4b: Holdout eval on the 10% eval split — measures task-specific
        performance with exact_match, BLEU, ROUGE, perplexity, F1 overlap.
        Answers: "Did the model learn the specific task?"

    Prerequisites:
      - RHOAI 3.4+ with Data Science Pipelines, Kubeflow Trainer v2, KServe, TrustyAI
      - EvalHub and MLflow deployed (for Phase 4a)
      - Secrets: kubernetes-credentials, hf-token (optional), s3-secret (optional)
      - ReadWriteMany PVC in the pipeline namespace (default: fine-tuning-shared)
      - GPU nodes for training (Phase 3) and evaluation (Phases 4a, 4b)

    Multi-tenancy:
      Each team gets their own namespace with: DSPA, secrets, RWX PVC, Role/RoleBinding.
      Override shared_pvc_name, evalhub_url, registry_address per namespace.
      Pipeline RBAC uses namespace-scoped Role (not ClusterRole) so teams
      cannot access each other's TrainJobs or InferenceServices.
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
    #   Removes exact duplicates, near-duplicates, empty/trivial examples.
    #   Uses SDG Hub framework (Red Hat supported).
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
    )
    quality_task.set_caching_options(False)
    kfp.kubernetes.set_image_pull_policy(quality_task, "IfNotPresent")

    # =========================================================================
    # Phase 3: Training (dispatches to LoRA/SFT/OSFT/custom)
    # Model download handled internally by TrainJob (training-hub runtime)
    # =========================================================================
    training_task = train_model(
        technique=technique,
        pvc_path=dsl.WORKSPACE_PATH_PLACEHOLDER,
        dataset=quality_task.outputs["output_dataset"],
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
        # OSFT
        osft_unfreeze_rank_ratio=osft_unfreeze_ratio,
        osft_target_patterns=osft_target_patterns,
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
    #   Answers: "Is the model generally capable?" (MMLU, ifeval, bbh, etc.)
    #   Results logged to MLflow experiment for cross-run comparison.
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
    # Phase 4b: Holdout Evaluation via lm-eval (on the actual eval split)
    #   Answers: "Did the model learn the specific task?" (exact_match, BLEU,
    #   ROUGE, perplexity, F1 on the held-out 10% of training data)
    #   Also runs standard benchmarks for baseline comparison.
    #   Includes unitxt for standard prompt formatting.
    # =========================================================================
    holdout_eval_task = universal_llm_evaluator(
        model_artifact=training_task.outputs["output_model"],
        eval_dataset=dataset_task.outputs["eval_dataset"],
        task_names=holdout_eval_tasks,
        batch_size=holdout_eval_batch_size,
        limit=holdout_eval_limit,
        log_samples=True,
        model_args={"enforce_eager": True},
    )
    holdout_eval_task.after(eval_task)
    holdout_eval_task.set_caching_options(False)
    kfp.kubernetes.set_image_pull_policy(holdout_eval_task, "IfNotPresent")
    holdout_eval_task.set_accelerator_type("nvidia.com/gpu")
    holdout_eval_task.set_accelerator_limit(1)
    kfp.kubernetes.add_node_selector(
        holdout_eval_task, "nvidia.com/gpu.present", "true"
    )
    kfp.kubernetes.add_toleration(holdout_eval_task, key="nvidia.com/gpu", operator="Exists", effect="NoSchedule")

    # The eval image (ubi9/python-311) has no CUDA toolkit (no nvcc, no
    # /usr/local/cuda). vLLM's FlashInfer JIT and deep_gemm both need nvcc.
    # Disable all JIT-compiled kernel paths to use pre-compiled alternatives.
    holdout_eval_task.set_env_variable("VLLM_ATTENTION_BACKEND", "FLASH_ATTN")
    holdout_eval_task.set_env_variable("VLLM_USE_FLASHINFER_SAMPLER", "false")
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
    # Phase 5: Model Registry
    #   Registers the trained model with full provenance:
    #   - Training hyperparameters + technique (from Phase 3)
    #   - Benchmark eval scores (from Phase 4a — passed directly)
    #   - Holdout eval scores (from Phase 4b — available as KFP artifacts
    #     in the pipeline run; registry component supports one eval input)
    #   - Pipeline run ID and namespace
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
        shared_log_file="pipeline_log.txt",
        source_pipeline_name=PIPELINE_NAME,
        source_pipeline_run_id=dsl.PIPELINE_JOB_ID_PLACEHOLDER,
        source_pipeline_run_name=dsl.PIPELINE_JOB_NAME_PLACEHOLDER,
        source_namespace="",
    )
    registry_task.after(holdout_eval_task)
    registry_task.set_caching_options(False)
    kfp.kubernetes.set_image_pull_policy(registry_task, "IfNotPresent")


if __name__ == "__main__":
    from kfp.compiler.compiler_utils import KubernetesManifestOptions

    # Compile to Pipeline + PipelineVersion CRD manifests (GitOps-ready)
    kfp.compiler.Compiler().compile(
        pipeline_func=finetuning_pipeline,
        package_path=__file__.replace(".py", ".yaml"),
        kubernetes_manifest_format=True,
        kubernetes_manifest_options=KubernetesManifestOptions(
            pipeline_name="finetuning-pipeline",
            pipeline_version_name="v1",
            namespace="fine-tuning-demo",
            include_pipeline_manifest=True,
        ),
    )
