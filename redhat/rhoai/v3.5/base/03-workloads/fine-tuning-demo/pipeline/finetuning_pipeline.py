"""Fine-Tuning Pipeline for OpenShift AI.

A single 4-phase KFP pipeline supporting multiple fine-tuning techniques
(LoRA, SFT, OSFT, custom) via a `technique` parameter:

  Phase 1: Dataset Download   -- S3/HF/HTTP -> chat-format JSONL + train/eval split
  Phase 2: Unified Training   -- dispatches to LoRA/SFT/OSFT/custom via TrainingHub
  Phase 3: Evaluation          -- EvalHub + ephemeral vLLM KServe + MLflow logging
  Phase 4: Model Registry      -- register trained model with provenance metadata

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
# At compile time, `pipelines-components` must be on PYTHONPATH:
#   export PYTHONPATH=/path/to/pipelines-components:$PYTHONPATH
#   python unified_finetuning_pipeline.py
#
# At runtime the compiled YAML is self-contained.
# ---------------------------------------------------------------------------
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "local_components"))

from local_components.train_model import train_model

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


# =============================================================================
# PVC Configuration (compile-time)
# =============================================================================
PVC_SIZE = "50Gi"
PVC_STORAGE_CLASS = "nfs-csi"
PVC_ACCESS_MODES = ["ReadWriteMany"]
PIPELINE_NAME = "finetuning-pipeline"


@dsl.pipeline(
    name=PIPELINE_NAME,
    description=(
        "Fine-tuning pipeline supporting LoRA, SFT, OSFT, and custom "
        "techniques. Select technique at run time. "
        "Evaluates via EvalHub with MLflow tracking, registers to Model Registry."
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

    # =========================================================================
    # PHASE 2: TRAINING -- Common
    # =========================================================================
    base_model: str = "Qwen/Qwen2.5-1.5B-Instruct",
    epochs: int = 2,
    learning_rate: float = 2e-4,
    effective_batch_size: int = 128,
    max_seq_len: int = 8192,
    max_tokens_per_gpu: int = 32000,
    gpu_per_worker: int = 1,
    num_workers: int = 1,
    cpu_per_worker: str = "4",
    memory_per_worker: str = "32Gi",
    training_runtime: str = "training-hub",
    seed: int = 42,
    use_liger: bool = True,
    lr_scheduler: str = "cosine",
    env_vars: str = "",
    labels: str = "",
    annotations: str = "",

    # =========================================================================
    # PHASE 2: TRAINING -- LoRA-specific
    # =========================================================================
    lora_r: int = 16,
    lora_alpha: int = 32,
    lora_dropout: float = 0.0,
    lora_target_modules: str = "",
    lora_load_in_4bit: bool = True,
    lora_load_in_8bit: bool = False,
    lora_sample_packing: bool = False,
    lora_micro_batch_size: int = 2,
    lora_grad_accum_steps: int = 1,
    lora_flash_attention: bool = True,
    lora_bf16: bool = True,

    # =========================================================================
    # PHASE 2: TRAINING -- SFT-specific
    # =========================================================================
    sft_fsdp_sharding: str = "",

    # =========================================================================
    # PHASE 2: TRAINING -- OSFT-specific
    # =========================================================================
    osft_unfreeze_ratio: float = 0.1,
    osft_target_patterns: str = "",

    # =========================================================================
    # PHASE 3: EVALUATION
    # =========================================================================
    evalhub_url: str = "",
    evalhub_collection: str = "",
    evalhub_benchmarks: list = [
        {"id": "leaderboard_ifeval", "provider_id": "lm_evaluation_harness"},
        {"id": "leaderboard_bbh", "provider_id": "lm_evaluation_harness"},
        {"id": "leaderboard_mmlu_pro", "provider_id": "lm_evaluation_harness"},
        {"id": "leaderboard_musr", "provider_id": "lm_evaluation_harness"},
        {"id": "leaderboard_math_hard", "provider_id": "lm_evaluation_harness"},
    ],
    mlflow_experiment: str = "",
    eval_timeout: int = 7200,
    eval_gpu_count: int = 1,
    eval_cpu: str = "2",
    eval_memory: str = "32Gi",

    # =========================================================================
    # PHASE 4: MODEL REGISTRY
    # =========================================================================
    registry_address: str = "",
    registry_port: int = 8080,
    registry_model_name: str = "finetuned-model",
    registry_model_version: str = "1.0.0",
    registry_author: str = "pipeline",
    registry_description: str = "",
):
    """Fine-Tuning Pipeline.

    A 4-phase pipeline that supports multiple fine-tuning techniques in a single
    DAG. Select the technique at run time via the `technique` parameter.

    Techniques:
      - lora:   Parameter-efficient LoRA/QLoRA via unsloth (single-node, fast)
      - sft:    Full supervised fine-tuning via instructlab-training (multi-node, FSDP)
      - osft:   Orthogonal Subspace FT via mini-trainer (preserves base capabilities)
      - custom: Bring-your-own training code (plain PyTorch demo)

    Prerequisites:
      - RHOAI 3.4+ with Data Science Pipelines, Kubeflow Trainer v2, KServe, TrustyAI
      - EvalHub and MLflow deployed (for Phase 3)
      - Secrets: kubernetes-credentials, hf-token (optional), s3-secret (optional)
      - 50Gi ReadWriteMany NFS PVC (auto-provisioned by pipeline workspace)

    Args:
        technique: Training technique ("lora", "sft", "osft", "custom").
        dataset_uri: Dataset location (hf://, s3://, https://).
        dataset_subset: Limit to first N examples (0 = all).
        base_model: Base model (HuggingFace ID or path).
        epochs: Number of training epochs.
        learning_rate: Learning rate.
        lora_r: LoRA rank (4, 8, 16, 32, 64).
        lora_alpha: LoRA scaling factor (typically 2x lora_r).
        sft_fsdp_sharding: FSDP sharding strategy for SFT.
        osft_unfreeze_ratio: OSFT unfreeze ratio (0.1=minimal, 0.5=strong).
        evalhub_url: EvalHub API endpoint (empty = skip evaluation).
        mlflow_experiment: MLflow experiment name (empty = disabled).
        registry_address: Model Registry address (empty = skip registration).
    """
    # =========================================================================
    # Phase 1: Dataset Download
    # =========================================================================
    dataset_task = dataset_download(
        dataset_uri=dataset_uri,
        pvc_mount_path=dsl.WORKSPACE_PATH_PLACEHOLDER,
        train_split_ratio=1.0,
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
    # Phase 2: Unified Training
    # =========================================================================
    training_task = train_model(
        technique=technique,
        pvc_path=dsl.WORKSPACE_PATH_PLACEHOLDER,
        dataset=dataset_task.outputs["train_dataset"],
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
    # Phase 3: Evaluation via EvalHub (KServe vLLM + MLflow)
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

    for _task in [dataset_task, training_task, eval_task]:
        kfp.kubernetes.use_secret_as_env(
            task=_task,
            secret_name="hf-token",
            secret_key_to_env={"HF_TOKEN": "HF_TOKEN"},
            optional=True,
        )

    # =========================================================================
    # Phase 4: Model Registry
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
    registry_task.set_caching_options(False)
    kfp.kubernetes.set_image_pull_policy(registry_task, "IfNotPresent")


if __name__ == "__main__":
    kfp.compiler.Compiler().compile(
        pipeline_func=finetuning_pipeline,
        package_path=__file__.replace(".py", ".yaml"),
    )
