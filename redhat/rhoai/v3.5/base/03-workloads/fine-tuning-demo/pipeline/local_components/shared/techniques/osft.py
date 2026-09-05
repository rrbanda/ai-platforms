"""OSFT (Orthogonal Subspace Fine-Tuning) technique.

Uses the mini-trainer backend via TrainingHubAlgorithms.OSFT.
Preserves base model capabilities while adapting to new tasks.
Supports multi-node training with FSDP.
"""

ALGORITHM_NAME = "OSFT"
IS_SINGLE_NODE = False
DEFAULT_LR = 5e-6
DEFAULT_EPOCHS = 1


def build_params(common, **kw):
    """Add OSFT-specific parameters to the common params dict."""
    from setup import parse_kv

    for param, key, cast in [
        ("osft_unfreeze_rank_ratio", "unfreeze_rank_ratio", float),
    ]:
        v = kw.get(param)
        if v is not None:
            common[key] = cast(v)

    if kw.get("osft_memory_efficient_init") is not None:
        common["memory_efficient_init"] = bool(kw["osft_memory_efficient_init"])
    if kw.get("osft_unmask_messages") is not None:
        common["unmask_messages"] = bool(kw["osft_unmask_messages"])
    if kw.get("osft_use_processed_dataset") is not None:
        common["use_processed_dataset"] = bool(kw["osft_use_processed_dataset"])
    if kw.get("osft_save_final_checkpoint") is not None:
        common["save_final_checkpoint"] = bool(kw["osft_save_final_checkpoint"])

    target_patterns = kw.get("osft_target_patterns", "")
    if target_patterns:
        common["target_patterns"] = [p.strip() for p in target_patterns.split(",") if p.strip()]

    lr_kw = kw.get("osft_lr_scheduler_kwargs", "")
    if lr_kw:
        common["lr_scheduler_kwargs"] = parse_kv(lr_kw)

    fsdp = kw.get("osft_fsdp_sharding_strategy", "")
    if fsdp:
        common["fsdp_sharding_strategy"] = fsdp.upper().strip()

    return common


def train_func(**p):
    """OSFT training function — serialized to run inside the TrainJob pod.

    Calls training_hub.osft() with optional FSDP sharding configuration.
    """
    a = dict(p)
    fsdp = a.pop("fsdp_sharding_strategy", None)
    from training_hub import osft as tr

    print("[PY] Launching OSFT training...", flush=True)
    if fsdp:
        try:
            from instructlab.training.config import FSDPOptions, ShardingStrategies

            sm = {
                "FULL_SHARD": ShardingStrategies.FULL_SHARD,
                "HYBRID_SHARD": ShardingStrategies.HYBRID_SHARD,
                "NO_SHARD": ShardingStrategies.NO_SHARD,
            }
            if fsdp.upper() in sm:
                a["fsdp_options"] = FSDPOptions(sharding_strategy=sm[fsdp.upper()])
        except ImportError as exc:
            raise RuntimeError(f"FSDP support unavailable: {exc}") from exc
    return tr(**a)


def log_metrics(output_metrics, params, **kw):
    """Log OSFT-specific metrics to the KFP Metrics artifact."""
    if params.get("unfreeze_rank_ratio") is not None:
        output_metrics.log_metric("unfreeze_rank_ratio", float(params["unfreeze_rank_ratio"]))
