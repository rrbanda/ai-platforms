"""LoRA / QLoRA fine-tuning technique.

Uses the unsloth backend via TrainingHubAlgorithms.LORA_SFT.
Single-node only. Merges LoRA adapter into base model post-training
for vLLM/lm-eval compatibility.
"""

ALGORITHM_NAME = "LORA_SFT"
IS_SINGLE_NODE = True
DEFAULT_LR = 2e-4
DEFAULT_EPOCHS = 3


def build_params(common, **kw):
    """Add LoRA-specific parameters to the common params dict.

    Args:
        common: Dict of common training parameters.
        **kw: LoRA-specific keyword arguments from the component signature.

    Returns:
        Updated params dict.
    """
    common["backend"] = "unsloth"
    common["lora_r"] = int(kw.get("lora_r", 16))
    common["lora_alpha"] = int(kw.get("lora_alpha", 32))
    common["lora_dropout"] = float(kw.get("lora_dropout", 0.0))

    target_modules = kw.get("lora_target_modules", "")
    if target_modules:
        common["target_modules"] = [m.strip() for m in target_modules.split(",") if m.strip()]

    for flag, key in [
        ("lora_use_rslora", "use_rslora"),
        ("lora_use_dora", "use_dora"),
        ("lora_sample_packing", "sample_packing"),
        ("lora_flash_attention", "flash_attention"),
        ("lora_bf16", "bf16"),
        ("lora_fp16", "fp16"),
        ("lora_tf32", "tf32"),
        ("lora_enable_model_splitting", "enable_model_splitting"),
    ]:
        v = kw.get(flag)
        if v is not None:
            common[key] = bool(v)

    # Unsloth >=2026.6 sets padding_free=True when flash_attention is enabled.
    # padding_free without packing raises:
    #   "When padding_free=True without packing, max_length is not enforced."
    # Auto-enable sample_packing to prevent this incompatibility.
    if common.get("flash_attention") and not common.get("sample_packing"):
        common["sample_packing"] = True

    load_4bit = kw.get("lora_load_in_4bit")
    load_8bit = kw.get("lora_load_in_8bit")
    if load_4bit and load_8bit:
        raise ValueError("Cannot enable both 4-bit and 8-bit quantization.")
    if load_4bit is not None:
        common["load_in_4bit"] = bool(load_4bit)
    if load_8bit is not None:
        common["load_in_8bit"] = bool(load_8bit)

    for param, key in [
        ("lora_micro_batch_size", "micro_batch_size"),
        ("lora_gradient_accumulation_steps", "gradient_accumulation_steps"),
        ("lora_save_steps", "save_steps"),
        ("lora_logging_steps", "logging_steps"),
        ("lora_save_total_limit", "save_total_limit"),
    ]:
        v = kw.get(param)
        if v is not None:
            common[key] = int(v)

    return common


def train_func(**p):
    """LoRA training function — serialized to run inside the TrainJob pod.

    Calls training_hub.lora_sft(), then merges the LoRA adapter into the
    base model using Unsloth's save_pretrained_merged(). Post-processes
    safetensors keys and config.json for vLLM compatibility.

    The merge writes to local /tmp first (avoids NFS mmap hangs on large
    safetensors writes), then copies the final model to the PVC checkpoint dir.
    """
    import os
    import shutil

    from training_hub import lora_sft as tr

    print("[PY] Launching LoRA training...", flush=True)
    result = tr(**p)

    ckpt_dir = p.get("ckpt_output_dir")
    if ckpt_dir and result and "model" in result:
        import glob as _glob
        import json

        from safetensors.torch import load_file, save_file

        local_merge = "/tmp/_merge_output"
        os.makedirs(local_merge, exist_ok=True)

        print("[PY] Merging and saving model (Unsloth merged_16bit) to local storage...", flush=True)
        result["model"].save_pretrained_merged(
            local_merge, result["tokenizer"], save_method="merged_16bit"
        )

        for sf_path in sorted(_glob.glob(local_merge + "/*.safetensors")):
            tensors = load_file(sf_path)
            clean, needs_fix = {}, False
            for k, v in tensors.items():
                if k.startswith("base_model.model."):
                    clean[k[len("base_model.model."):]] = v
                    needs_fix = True
                elif k.startswith("base_model."):
                    clean[k[len("base_model."):]] = v
                    needs_fix = True
                else:
                    clean[k] = v
            if needs_fix:
                save_file(clean, sf_path)

        idx_path = local_merge + "/model.safetensors.index.json"
        if os.path.exists(idx_path):
            with open(idx_path) as f:
                idx = json.load(f)
            if "weight_map" in idx:
                new_map = {}
                for k, v in idx["weight_map"].items():
                    if k.startswith("base_model.model."):
                        new_map[k[len("base_model.model."):]] = v
                    elif k.startswith("base_model."):
                        new_map[k[len("base_model."):]] = v
                    else:
                        new_map[k] = v
                idx["weight_map"] = new_map
                with open(idx_path, "w") as f:
                    json.dump(idx, f, indent=2)

        cfg_path = local_merge + "/config.json"
        if os.path.exists(cfg_path):
            with open(cfg_path) as f:
                cfg = json.load(f)
            if "quantization_config" in cfg:
                del cfg["quantization_config"]
                with open(cfg_path, "w") as f:
                    json.dump(cfg, f, indent=2)

        print("[PY] Copying merged model to PVC...", flush=True)
        # Clean ckpt_dir first — remove old checkpoint subdirs and adapter files
        # so persist_model only finds the clean merged model.
        for entry in os.listdir(ckpt_dir):
            p = os.path.join(ckpt_dir, entry)
            if os.path.isdir(p):
                shutil.rmtree(p, ignore_errors=True)
            elif entry.endswith((".safetensors", ".bin")) or entry in (
                "adapter_config.json", "model.safetensors.index.json",
            ):
                os.remove(p)
        for fn in os.listdir(local_merge):
            src = os.path.join(local_merge, fn)
            dst = os.path.join(ckpt_dir, fn)
            if os.path.isfile(src):
                shutil.copy2(src, dst)
        shutil.rmtree(local_merge, ignore_errors=True)

        print("[PY] Merged model saved.", flush=True)
    return result


def log_metrics(output_metrics, params, **kw):
    """Log LoRA-specific metrics to the KFP Metrics artifact."""
    output_metrics.log_metric("lora_r", float(params.get("lora_r", 16)))
    output_metrics.log_metric("lora_alpha", float(params.get("lora_alpha", 32)))
    output_metrics.log_metric("lora_dropout", float(params.get("lora_dropout", 0.0)))
    if params.get("load_in_4bit"):
        output_metrics.log_metric("quantization", "4bit")
    elif params.get("load_in_8bit"):
        output_metrics.log_metric("quantization", "8bit")
