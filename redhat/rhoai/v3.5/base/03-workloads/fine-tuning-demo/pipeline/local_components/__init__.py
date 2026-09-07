"""Local pipeline components — downstream forks and enhancements.

These components live here temporarily while being validated in production.
They should be contributed to the midstream repo once stabilized:

  Target: opendatahub-io/pipelines-components

  Component                  Status         Midstream target
  -------------------------  -------------- ------------------------------------------
  evalhub_eval.py            Fork           components/evaluation/evalhub/
                                            Adds GPU tolerations to ephemeral KServe
                                            InferenceService (upstream lacks them).

  model_registry.py          Enhancement    components/model_registry/kubeflow/
                                            Adds provenance tracking (pipeline name,
                                            run ID, namespace) via SDK 0.3.4+ params.

  data_quality_filter.py     New component  components/data_processing/quality_filter/
                                            Dedup + quality scoring + LLM judge.

  train_model.py             New component  components/training/training_hub/
                                            Multi-technique dispatcher (LoRA/SFT/OSFT).

  unitxt_formatter.py        New component  components/data_processing/format_validator/
                                            Chat template + tokenization validation.

  holdout_eval.py            Wrapper        N/A (uses upstream universal_llm_evaluator)
"""
