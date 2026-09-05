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
