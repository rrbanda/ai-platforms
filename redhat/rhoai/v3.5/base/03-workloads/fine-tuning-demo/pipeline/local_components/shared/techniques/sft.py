"""SFT (Supervised Fine-Tuning) technique.

Uses the instructlab-training backend via TrainingHubAlgorithms.SFT.
Supports multi-node distributed training with FSDP sharding.
"""

ALGORITHM_NAME = "SFT"
IS_SINGLE_NODE = False
DEFAULT_LR = 5e-6
DEFAULT_EPOCHS = 1


def build_params(common, **kw):
    """Add SFT-specific parameters to the common params dict."""
    for param, key, cast in [
        ("sft_save_samples", "save_samples", int),
    ]:
        v = kw.get(param)
        if v is not None:
            common[key] = cast(v)

    if kw.get("sft_accelerate_full_state_at_epoch") is not None:
        common["accelerate_full_state_at_epoch"] = bool(kw["sft_accelerate_full_state_at_epoch"])

    fsdp = kw.get("sft_fsdp_sharding_strategy", "")
    if fsdp:
        common["fsdp_sharding_strategy"] = fsdp.upper().strip()

    return common


def train_func(**p):
    """SFT training function — serialized to run inside the TrainJob pod.

    Calls training_hub.sft() with optional FSDP sharding configuration.
    """
    a = dict(p)
    fsdp = a.pop("fsdp_sharding_strategy", None)
    from training_hub import sft as tr

    print("[PY] Launching SFT training...", flush=True)
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
    """Log SFT-specific metrics to the KFP Metrics artifact."""
    if params.get("fsdp_sharding_strategy"):
        output_metrics.log_metric("fsdp_strategy", params["fsdp_sharding_strategy"])
