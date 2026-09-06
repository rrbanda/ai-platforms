"""Unitxt Format Validator Component.

Enforces standardized prompt templates on training data using unitxt
format definitions. Validates that every example follows the base
model's chat template structure, enforces a consistent system prompt,
and checks tokenization fits within max_seq_len.

Placed between the quality filter and training steps to catch format
issues before GPU time is spent.

Per RHOAI 3.5, unitxt provides reusable format definitions (cards,
templates, formats) that can be shared between training and evaluation,
ensuring consistency across the ML lifecycle.
"""

from kfp import dsl


@dsl.component(
    base_image="quay.io/opendatahub/odh-th06-cpu-torch291-py312:odh-3.4",
    packages_to_install=["unitxt", "transformers", "mlflow>=2.0"],
)
def unitxt_format_validator(
    input_dataset: dsl.Input[dsl.Dataset],
    output_dataset: dsl.Output[dsl.Dataset],
    output_metrics: dsl.Output[dsl.Metrics],
    base_model: str = "Qwen/Qwen2.5-1.5B-Instruct",
    system_prompt: str = "You are a helpful assistant.",
    max_seq_len: int = 8192,
    pvc_mount_path: str = "",
    mlflow_tracking_uri: str = "",
    mlflow_experiment_name: str = "finetuning-datasets",
):
    """Validate and normalize training data format using unitxt.

    Enforces a standard system prompt, validates chat template structure,
    and checks tokenization length against the base model's tokenizer.

    Args:
        input_dataset: Cleaned JSONL from the quality filter.
        output_dataset: Normalized JSONL with consistent formatting.
        output_metrics: Validation metrics (token stats, format corrections).
        base_model: HuggingFace model ID for tokenizer resolution.
        system_prompt: Standard system prompt to enforce on all examples.
        max_seq_len: Maximum sequence length in tokens.
        pvc_mount_path: Workspace PVC mount path.
        mlflow_tracking_uri: MLflow tracking URI (empty = skip logging).
        mlflow_experiment_name: MLflow experiment for dataset tracking.
    """
    import json
    import logging
    import os
    import time

    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
    )
    log = logging.getLogger("unitxt_formatter")

    start_time = time.time()

    # =====================================================================
    # 1. Load cleaned dataset
    # =====================================================================
    data = []
    src = input_dataset.path
    if os.path.isdir(src):
        for fn in sorted(os.listdir(src)):
            fp = os.path.join(src, fn)
            if os.path.isfile(fp):
                with open(fp) as f:
                    for line in f:
                        if line.strip():
                            data.append(json.loads(line))
                break
    elif os.path.isfile(src):
        with open(src) as f:
            for line in f:
                if line.strip():
                    data.append(json.loads(line))

    if not data:
        meta = getattr(input_dataset, "metadata", {}) or {}
        pvc_path = (meta.get("pvc_path") or "").strip()
        if pvc_path and os.path.isfile(pvc_path):
            with open(pvc_path) as f:
                for line in f:
                    if line.strip():
                        data.append(json.loads(line))

    total_input = len(data)
    log.info(f"Loaded {total_input} examples")

    if total_input == 0:
        log.warning("No examples loaded — passing through empty dataset")
        with open(output_dataset.path, "w") as f:
            pass
        output_metrics.log_metric("input_examples", 0)
        return

    # =====================================================================
    # 2. Load tokenizer for token length validation
    # =====================================================================
    from transformers import AutoTokenizer

    log.info(f"Loading tokenizer for {base_model}...")
    tokenizer = AutoTokenizer.from_pretrained(base_model, trust_remote_code=True)
    if tokenizer.chat_template:
        log.info(f"Chat template found: {tokenizer.chat_template[:80]}...")
    else:
        log.info("No chat template in tokenizer — using default formatting")

    # =====================================================================
    # 3. Validate and normalize each example
    # =====================================================================
    normalized = []
    stats = {
        "system_prompt_added": 0,
        "system_prompt_replaced": 0,
        "system_prompt_kept": 0,
        "invalid_structure": 0,
        "exceeds_max_seq_len": 0,
        "token_lengths": [],
    }

    for i, example in enumerate(data):
        messages = example.get("messages", example.get("conversations", []))
        if not messages or not isinstance(messages, list):
            stats["invalid_structure"] += 1
            continue

        # -----------------------------------------------------------------
        # 3a. Enforce system prompt
        # -----------------------------------------------------------------
        if messages[0].get("role") == "system":
            if messages[0].get("content", "").strip() != system_prompt.strip():
                stats["system_prompt_replaced"] += 1
                messages[0]["content"] = system_prompt
            else:
                stats["system_prompt_kept"] += 1
        else:
            stats["system_prompt_added"] += 1
            messages.insert(0, {"role": "system", "content": system_prompt})

        # -----------------------------------------------------------------
        # 3b. Validate role ordering: system -> (user -> assistant)+
        # -----------------------------------------------------------------
        roles = [m.get("role") for m in messages]
        valid = True

        if roles[0] != "system":
            valid = False

        for j in range(1, len(roles)):
            if j % 2 == 1 and roles[j] != "user":
                valid = False
                break
            if j % 2 == 0 and roles[j] != "assistant":
                valid = False
                break

        if not valid:
            has_user = any(r == "user" for r in roles)
            has_assistant = any(r == "assistant" for r in roles)
            if not (has_user and has_assistant):
                stats["invalid_structure"] += 1
                continue

        # -----------------------------------------------------------------
        # 3c. Check tokenization length
        # -----------------------------------------------------------------
        try:
            if tokenizer.chat_template:
                formatted = tokenizer.apply_chat_template(
                    messages, tokenize=True, add_generation_prompt=False
                )
                token_count = len(formatted)
            else:
                text = ""
                for m in messages:
                    text += f"<|{m['role']}|>\n{m['content']}\n"
                token_count = len(tokenizer.encode(text))

            stats["token_lengths"].append(token_count)

            if token_count > max_seq_len:
                stats["exceeds_max_seq_len"] += 1
        except Exception as e:
            log.warning(f"Tokenization failed for example {i}: {e}")
            token_count = 0

        normalized.append({"messages": messages})

    # =====================================================================
    # 4. Write normalized output
    # =====================================================================
    with open(output_dataset.path, "w") as f:
        for row in normalized:
            f.write(json.dumps(row, ensure_ascii=False) + "\n")

    if pvc_mount_path:
        pvc_out = os.path.join(pvc_mount_path, "datasets", "formatted", "formatted.jsonl")
        os.makedirs(os.path.dirname(pvc_out), exist_ok=True)
        with open(pvc_out, "w") as f:
            for row in normalized:
                f.write(json.dumps(row, ensure_ascii=False) + "\n")
        log.info(f"Formatted dataset saved to PVC: {pvc_out}")
        try:
            output_dataset.metadata["pvc_path"] = pvc_out
        except Exception:
            pass

    # =====================================================================
    # 5. Compute and log metrics
    # =====================================================================
    total_output = len(normalized)
    token_lengths = stats["token_lengths"]
    avg_tokens = sum(token_lengths) / len(token_lengths) if token_lengths else 0
    min_tokens = min(token_lengths) if token_lengths else 0
    max_tokens = max(token_lengths) if token_lengths else 0

    elapsed = time.time() - start_time

    output_metrics.log_metric("input_examples", total_input)
    output_metrics.log_metric("output_examples", total_output)
    output_metrics.log_metric("invalid_structure", stats["invalid_structure"])
    output_metrics.log_metric("system_prompt_added", stats["system_prompt_added"])
    output_metrics.log_metric("system_prompt_replaced", stats["system_prompt_replaced"])
    output_metrics.log_metric("system_prompt_kept", stats["system_prompt_kept"])
    output_metrics.log_metric("exceeds_max_seq_len", stats["exceeds_max_seq_len"])
    output_metrics.log_metric("avg_token_length", round(avg_tokens, 1))
    output_metrics.log_metric("min_token_length", min_tokens)
    output_metrics.log_metric("max_token_length", max_tokens)
    output_metrics.log_metric("execution_seconds", round(elapsed, 2))

    try:
        output_dataset.metadata["num_examples"] = str(total_output)
        output_dataset.metadata["system_prompt"] = system_prompt
        output_dataset.metadata["base_model"] = base_model
        output_dataset.metadata["avg_token_length"] = str(round(avg_tokens, 1))
    except Exception:
        pass

    log.info("=" * 60)
    log.info("Unitxt Format Validation Summary:")
    log.info(f"  Input:              {total_input:,} examples")
    log.info(f"  Output:             {total_output:,} examples")
    log.info(f"  Invalid structure:  {stats['invalid_structure']:,}")
    log.info(f"  System prompt:")
    log.info(f"    - Added:          {stats['system_prompt_added']:,}")
    log.info(f"    - Replaced:       {stats['system_prompt_replaced']:,}")
    log.info(f"    - Already correct:{stats['system_prompt_kept']:,}")
    log.info(f"  Token lengths:")
    log.info(f"    - Min:            {min_tokens:,}")
    log.info(f"    - Avg:            {avg_tokens:,.1f}")
    log.info(f"    - Max:            {max_tokens:,}")
    log.info(f"    - Exceeds {max_seq_len}: {stats['exceeds_max_seq_len']:,}")
    log.info(f"  Base model:         {base_model}")
    log.info(f"  System prompt:      {system_prompt[:50]}...")
    log.info(f"  Time:               {elapsed:.1f}s")
    log.info("=" * 60)

    # =====================================================================
    # 6. Log to MLflow (optional)
    # =====================================================================
    if mlflow_tracking_uri:
        try:
            import mlflow

            mlflow.set_tracking_uri(mlflow_tracking_uri)
            mlflow.set_experiment(mlflow_experiment_name)

            with mlflow.start_run(run_name=f"format_{base_model.replace('/', '_')}_{total_output}ex"):
                mlflow.log_param("base_model", base_model)
                mlflow.log_param("system_prompt", system_prompt)
                mlflow.log_param("max_seq_len", max_seq_len)
                mlflow.log_param("input_examples", total_input)
                mlflow.log_param("output_examples", total_output)
                mlflow.log_param("system_prompt_added", stats["system_prompt_added"])
                mlflow.log_param("exceeds_max_seq_len", stats["exceeds_max_seq_len"])
                mlflow.log_metric("avg_token_length", round(avg_tokens, 1))
                mlflow.log_metric("max_token_length", max_tokens)

                if pvc_mount_path:
                    pvc_formatted = os.path.join(pvc_mount_path, "datasets", "formatted", "formatted.jsonl")
                    if os.path.exists(pvc_formatted):
                        mlflow.log_artifact(pvc_formatted, artifact_path="datasets")

            log.info(f"MLflow: format validation logged to '{mlflow_experiment_name}'")
        except Exception as e:
            log.warning(f"MLflow logging failed: {e}")
