"""Technique modules for the unified fine-tuning component.

Each technique module exports:
  - ALGORITHM_NAME: str          (TrainingHubAlgorithms enum name)
  - IS_SINGLE_NODE: bool         (force single-node training)
  - DEFAULT_LR: float            (default learning rate)
  - DEFAULT_EPOCHS: int          (default epoch count)
  - build_params(common, **kw)   (add technique-specific params to common dict)
  - train_func(**p)              (serialized to run inside TrainJob pod)
  - log_metrics(output, params)  (log technique-specific metrics to KFP)
"""

SUPPORTED_TECHNIQUES = ("lora", "sft", "osft", "custom")


def get_technique_module(technique: str):
    """Import and return the technique module by name.

    Args:
        technique: One of "lora", "sft", "osft", "custom".

    Returns:
        The technique module.

    Raises:
        ValueError: If technique is not recognized.
    """
    technique = technique.strip().lower()
    if technique not in SUPPORTED_TECHNIQUES:
        raise ValueError(
            f"Unknown technique '{technique}'. Must be one of: {', '.join(SUPPORTED_TECHNIQUES)}"
        )

    if technique == "lora":
        from techniques import lora as mod
    elif technique == "sft":
        from techniques import sft as mod
    elif technique == "osft":
        from techniques import osft as mod
    else:
        from techniques import custom as mod

    return mod


def nfs_safe_output(train_fn, params, ckpt_dir):
    """Run training with output to local /tmp, then copy results to PVC.

    Avoids NFS mmap hangs from large safetensors writes by writing to
    ephemeral local storage first, then doing sequential file copies.

    Args:
        train_fn: The technique's training function (called with **params).
        params: Training parameters dict. 'ckpt_output_dir' will be redirected.
        ckpt_dir: The final PVC checkpoint directory.

    Returns:
        The result from train_fn.
    """
    import os
    import shutil

    local_dir = "/tmp/_training_output"
    os.makedirs(local_dir, exist_ok=True)

    original_ckpt = params.get("ckpt_output_dir", ckpt_dir)
    params["ckpt_output_dir"] = local_dir

    result = train_fn(**params)

    params["ckpt_output_dir"] = original_ckpt

    print("[PY] Copying model output to PVC...", flush=True)
    for entry in os.listdir(ckpt_dir):
        p = os.path.join(ckpt_dir, entry)
        if os.path.isdir(p):
            shutil.rmtree(p, ignore_errors=True)
        elif entry.endswith((".safetensors", ".bin")) or entry in (
            "adapter_config.json", "model.safetensors.index.json",
        ):
            os.remove(p)

    for fn in os.listdir(local_dir):
        src = os.path.join(local_dir, fn)
        dst = os.path.join(ckpt_dir, fn)
        if os.path.isfile(src):
            shutil.copy2(src, dst)
        elif os.path.isdir(src):
            shutil.copytree(src, dst, dirs_exist_ok=True)
    shutil.rmtree(local_dir, ignore_errors=True)
    print("[PY] Model output copied to PVC.", flush=True)

    return result
