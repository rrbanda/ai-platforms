"""Fine-Tuning Training Component.

Slim orchestrator that dispatches to technique-specific modules under
shared/techniques/. Each technique module handles its own param building,
training function, and metric logging.

Supported techniques: lora, sft, osft, custom.
Add new techniques by creating a module in shared/techniques/ that exports:
  ALGORITHM_NAME, IS_SINGLE_NODE, DEFAULT_LR, DEFAULT_EPOCHS,
  build_params(), train_func(), log_metrics()
"""

import os
from typing import Optional

from kfp import dsl

_SHARED_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "shared")


@dsl.component(
    base_image="quay.io/opendatahub/odh-th06-cpu-torch291-py312:odh-3.4",
    packages_to_install=[
        "kubernetes",
        "olot",
        "matplotlib",
    ],
    embedded_artifact_path=_SHARED_DIR,
    task_config_passthroughs=[
        dsl.TaskConfigField.RESOURCES,
        dsl.TaskConfigField.KUBERNETES_TOLERATIONS,
        dsl.TaskConfigField.KUBERNETES_NODE_SELECTOR,
        dsl.TaskConfigField.KUBERNETES_AFFINITY,
        dsl.TaskConfigPassthrough(field=dsl.TaskConfigField.ENV, apply_to_task=True),
        dsl.TaskConfigPassthrough(field=dsl.TaskConfigField.KUBERNETES_VOLUMES, apply_to_task=True),
    ],
)
def train_model(
    technique: str,
    pvc_path: str,
    output_model: dsl.Output[dsl.Model],
    output_metrics: dsl.Output[dsl.Metrics],
    output_loss_chart: dsl.Output[dsl.HTML],
    dataset: dsl.Input[dsl.Dataset] = None,
    # -- Common parameters (all techniques) --
    training_base_model: str = "Qwen/Qwen2.5-1.5B-Instruct",
    training_effective_batch_size: int = 128,
    training_max_tokens_per_gpu: int = 32000,
    training_max_seq_len: int = 8192,
    training_learning_rate: Optional[float] = None,
    training_lr_warmup_steps: Optional[int] = None,
    training_checkpoint_at_epoch: Optional[bool] = None,
    training_num_epochs: Optional[int] = None,
    training_data_output_dir: Optional[str] = None,
    training_envs: str = "",
    training_resource_cpu_per_worker: str = "4",
    training_resource_gpu_per_worker: int = 1,
    training_resource_memory_per_worker: str = "24Gi",
    training_resource_num_procs_per_worker: str = "auto",
    training_resource_num_workers: int = 1,
    training_metadata_labels: str = "",
    training_metadata_annotations: str = "",
    training_seed: Optional[int] = None,
    training_use_liger: Optional[bool] = None,
    training_lr_scheduler: Optional[str] = None,
    training_runtime: str = "training-hub",
    training_dataset_type: Optional[str] = None,
    training_field_messages: Optional[str] = None,
    training_field_instruction: Optional[str] = None,
    training_field_input: Optional[str] = None,
    training_field_output: Optional[str] = None,
    # -- LoRA-specific (ignored when technique != "lora") --
    lora_r: int = 16,
    lora_alpha: int = 32,
    lora_dropout: float = 0.0,
    lora_target_modules: str = "",
    lora_use_rslora: Optional[bool] = None,
    lora_use_dora: Optional[bool] = None,
    lora_load_in_4bit: Optional[bool] = True,
    lora_load_in_8bit: Optional[bool] = None,
    lora_sample_packing: Optional[bool] = None,
    lora_micro_batch_size: Optional[int] = None,
    lora_gradient_accumulation_steps: Optional[int] = None,
    lora_flash_attention: Optional[bool] = None,
    lora_bf16: Optional[bool] = None,
    lora_fp16: Optional[bool] = None,
    lora_tf32: Optional[bool] = None,
    lora_save_steps: Optional[int] = None,
    lora_logging_steps: Optional[int] = None,
    lora_save_total_limit: Optional[int] = None,
    lora_enable_model_splitting: Optional[bool] = None,
    # -- SFT-specific (ignored when technique != "sft") --
    sft_save_samples: Optional[int] = None,
    sft_accelerate_full_state_at_epoch: Optional[bool] = None,
    sft_fsdp_sharding_strategy: str = "",
    # -- OSFT-specific (ignored when technique != "osft") --
    osft_unfreeze_rank_ratio: Optional[float] = None,
    osft_memory_efficient_init: Optional[bool] = None,
    osft_target_patterns: str = "",
    osft_unmask_messages: Optional[bool] = None,
    osft_use_processed_dataset: Optional[bool] = None,
    osft_lr_scheduler_kwargs: str = "",
    osft_save_final_checkpoint: Optional[bool] = None,
    osft_fsdp_sharding_strategy: str = "",
    # -- KFP passthrough --
    kubernetes_config: dsl.TaskConfig = None,
) -> str:
    """Unified fine-tuning: dispatches to LoRA, SFT, OSFT, or custom technique.

    Args:
        technique: Training technique ("lora", "sft", "osft", "custom").
        pvc_path: Workspace PVC root path (use dsl.WORKSPACE_PATH_PLACEHOLDER).
        training_base_model: Base model (HuggingFace ID or local path).
        training_runtime: ClusterTrainingRuntime name.
        See technique modules for technique-specific parameter docs.
    """
    import os
    from typing import Dict

    from data import download_oci_model, prepare_jsonl, resolve_dataset
    from output import persist_model, plot_training_loss
    from setup import configure_env, create_logger, init_k8s, parse_kv, setup_hf_token
    from techniques import get_technique_module
    from training import compute_nproc, select_runtime, wait_for_training_job

    log = create_logger("unified_train_model")
    technique = technique.strip().lower()
    log.info(f"Technique: {technique} | Model: {training_base_model} | PVC: {pvc_path}")

    tech = get_technique_module(technique)

    # =====================================================================
    # Phase A: Environment and dataset setup
    # =====================================================================
    _api = init_k8s(log)

    cache = os.path.join(pvc_path, ".cache", "huggingface")
    default_env: Dict[str, str] = {
        "XDG_CACHE_HOME": "/tmp",
        "TRITON_CACHE_DIR": "/tmp/.triton",
        "HF_HOME": "/tmp/.cache/huggingface",
        "HF_DATASETS_CACHE": "/tmp/.cache/huggingface/datasets",
        "TRANSFORMERS_CACHE": "/tmp/.cache/huggingface/transformers",
        "NCCL_DEBUG": "INFO",
        "PYTHONUNBUFFERED": "1",
    }

    merged_env = configure_env(training_envs, default_env, log)
    setup_hf_token(merged_env, training_base_model, log)

    ds_dir = os.path.join(pvc_path, "dataset", "train")
    os.makedirs(ds_dir, exist_ok=True)
    resolve_dataset(dataset, ds_dir, log)

    jsonl = os.path.join(ds_dir, "train.jsonl")
    prepare_jsonl(ds_dir, jsonl, log)

    resolved = training_base_model
    if isinstance(training_base_model, str) and training_base_model.startswith("oci://"):
        resolved = download_oci_model(training_base_model, pvc_path, log)

    ckpt_dir = os.path.join(pvc_path, "checkpoints")
    os.makedirs(ckpt_dir, exist_ok=True)
    data_path = jsonl if os.path.exists(jsonl) else ds_dir

    # =====================================================================
    # Phase B: Build common + technique-specific params
    # =====================================================================
    np_val, nn_val = compute_nproc(
        training_resource_gpu_per_worker,
        training_resource_num_procs_per_worker,
        num_workers=training_resource_num_workers,
        single_node=tech.IS_SINGLE_NODE,
    )

    params: Dict = {
        "model_path": resolved,
        "data_path": data_path,
        "effective_batch_size": int(training_effective_batch_size or 128),
        "max_tokens_per_gpu": int(training_max_tokens_per_gpu),
        "max_seq_len": int(training_max_seq_len or 8192),
        "learning_rate": float(training_learning_rate or tech.DEFAULT_LR),
        "ckpt_output_dir": ckpt_dir,
        "data_output_dir": training_data_output_dir or os.path.join(ckpt_dir, "_internal_data_processing"),
        "warmup_steps": int(training_lr_warmup_steps) if training_lr_warmup_steps is not None else 10,
        "checkpoint_at_epoch": bool(training_checkpoint_at_epoch) if training_checkpoint_at_epoch is not None else False,
        "num_epochs": int(training_num_epochs) if training_num_epochs else tech.DEFAULT_EPOCHS,
        "nproc_per_node": np_val,
        "nnodes": nn_val,
    }

    if training_lr_scheduler:
        params["lr_scheduler"] = training_lr_scheduler
    if training_use_liger is not None:
        params["use_liger"] = bool(training_use_liger)
    if training_seed is not None:
        params["seed"] = int(training_seed)
    for field, key in [
        (training_dataset_type, "dataset_type"),
        (training_field_messages, "field_messages"),
        (training_field_instruction, "field_instruction"),
        (training_field_input, "field_input"),
        (training_field_output, "field_output"),
    ]:
        if field:
            params[key] = field

    tech.build_params(params, **{k: v for k, v in locals().items() if k.startswith(("lora_", "sft_", "osft_"))})
    log.info(f"Training params ({technique}): {sorted(params.keys())}")

    # =====================================================================
    # Phase C: Submit TrainJob
    # =====================================================================
    from kubeflow.common.types import KubernetesBackendConfig
    from kubeflow.trainer import TrainerClient
    from kubeflow.trainer.options.kubernetes import (
        ContainerOverride,
        PodSpecOverride,
        PodTemplateOverride,
        PodTemplateOverrides,
    )
    from kubeflow.trainer.rhai import TrainingHubAlgorithms, TrainingHubTrainer

    if _api is None:
        raise RuntimeError("K8s API not initialized")

    client = TrainerClient(KubernetesBackendConfig(client_configuration=_api.configuration))
    runtime = select_runtime(client, log, runtime_name=training_runtime)
    algorithm = getattr(TrainingHubAlgorithms, tech.ALGORITHM_NAME)

    vols, vmts = [], []
    if kubernetes_config and getattr(kubernetes_config, "volumes", None):
        vols.extend(kubernetes_config.volumes)
    if kubernetes_config and getattr(kubernetes_config, "volume_mounts", None):
        vmts.extend(kubernetes_config.volume_mounts)

    # Check if workspace PVC is already mounted via kubernetes_config passthrough.
    # If not, discover it from own pod spec and add it.
    has_workspace = any("workspace" in str(v) for v in vols)
    if not has_workspace:
        try:
            from kubernetes import client as k8s_client
            v1 = k8s_client.CoreV1Api(_api)
            my_pod_name = os.environ.get("HOSTNAME", "")
            my_namespace = open("/var/run/secrets/kubernetes.io/serviceaccount/namespace").read().strip()
            if my_pod_name and my_namespace:
                pod = v1.read_namespaced_pod(my_pod_name, my_namespace)
                for vol in pod.spec.volumes or []:
                    if vol.persistent_volume_claim and "workspace" in (vol.persistent_volume_claim.claim_name or ""):
                        workspace_pvc = vol.persistent_volume_claim.claim_name
                        workspace_mount = None
                        for container in pod.spec.containers or []:
                            for vm in container.volume_mounts or []:
                                if vm.name == vol.name:
                                    workspace_mount = vm.mount_path
                                    break
                        if workspace_pvc and workspace_mount:
                            log.info(f"Adding workspace PVC: {workspace_pvc} at {workspace_mount}")
                            vols.append({"name": "workspace", "persistentVolumeClaim": {"claimName": workspace_pvc}})
                            vmts.append({"name": "workspace", "mountPath": workspace_mount})
                        break
        except Exception as e:
            log.warning(f"Could not discover workspace PVC: {e}")
    else:
        log.info("Workspace PVC already in kubernetes_config passthrough")

    resources = {
        "nvidia.com/gpu": training_resource_gpu_per_worker,
        "memory": training_resource_memory_per_worker,
        "cpu": int(training_resource_cpu_per_worker),
    }

    job = client.train(
        trainer=TrainingHubTrainer(
            func=tech.train_func,
            func_args=params,
            algorithm=algorithm,
            packages_to_install=[],
            env=dict(merged_env),
            resources_per_node=resources,
        ),
        options=[
            PodTemplateOverrides(
                PodTemplateOverride(
                    target_jobs=["node"],
                    metadata=(
                        {"labels": parse_kv(training_metadata_labels), "annotations": parse_kv(training_metadata_annotations)}
                        if (training_metadata_labels or training_metadata_annotations)
                        else None
                    ),
                    spec=PodSpecOverride(
                        volumes=vols,
                        containers=[ContainerOverride(name="node", volume_mounts=vmts)],
                        tolerations=[{"key": "nvidia.com/gpu", "operator": "Exists", "effect": "NoSchedule"}],
                        node_selector={"nvidia.com/gpu.present": "true"},
                    ),
                )
            )
        ],
        runtime=runtime,
    )
    log.info(f"Job submitted: {job}")
    wait_for_training_job(client, job, log)

    # =====================================================================
    # Phase D: Metrics and model persistence
    # =====================================================================
    output_metrics.log_metric("technique", technique)
    output_metrics.log_metric("num_epochs", float(params.get("num_epochs", 1)))
    output_metrics.log_metric("effective_batch_size", float(params.get("effective_batch_size", 128)))
    output_metrics.log_metric("learning_rate", float(params.get("learning_rate", 2e-4)))
    output_metrics.log_metric("max_seq_len", float(params.get("max_seq_len", 8192)))
    output_metrics.log_metric("num_workers", float(nn_val))
    output_metrics.log_metric("gpu_per_worker", float(training_resource_gpu_per_worker))

    tech.log_metrics(output_metrics, params)

    plot_training_loss([], output_loss_chart.path)
    persist_model(ckpt_dir, pvc_path, training_base_model, output_model, log)

    return f"{technique} training completed"
