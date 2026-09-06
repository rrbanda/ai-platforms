"""Data Quality Component — Deduplication and Quality Filtering.

Uses SDG Hub's framework (Red Hat supported) for dataset processing,
with additional dedup and quality heuristics for instruction-tuning data.

Operations (applied in order):
  1. Format validation — verify chat format (messages with role/content)
  2. Empty removal — drop rows with empty messages or missing assistant response
  3. Exact deduplication — hash-based on user prompt content
  4. Near-duplicate removal — fuzzy similarity matching (configurable threshold)
  5. Quality scoring — flag low-quality examples (too short, repetitive, trivial)
  6. Statistics — log dataset metrics before/after cleaning

Input:  JSONL in chat format (messages: [{role, content}, ...])
Output: Cleaned JSONL + quality metrics artifact
"""

from kfp import dsl


@dsl.component(
    base_image="quay.io/opendatahub/odh-th06-cpu-torch291-py312:odh-3.4",
    packages_to_install=["sdg-hub>=0.7.0,<1.0", "requests", "mlflow>=2.0"],
)
def data_quality_filter(
    output_dataset: dsl.Output[dsl.Dataset],
    output_metrics: dsl.Output[dsl.Metrics],
    input_dataset: dsl.Input[dsl.Dataset] = None,
    input_pvc_path: str = "",
    pvc_mount_path: str = "",
    similarity_threshold: float = 0.85,
    min_assistant_tokens: int = 5,
    min_user_tokens: int = 3,
    max_repetition_ratio: float = 0.5,
    export_to_pvc: bool = True,
    shared_log_file: str = "pipeline_log.txt",
    # -- Optional LLM Judge for hallucination detection --
    enable_llm_judge: bool = False,
    llm_judge_endpoint: str = "",
    llm_judge_model: str = "judge",
    llm_judge_api_key: str = "",
    # -- Optional MLflow dataset tracking --
    mlflow_tracking_uri: str = "",
    mlflow_experiment_name: str = "finetuning-datasets",
):
    """Clean and deduplicate an instruction-tuning dataset.

    Performs exact and near-duplicate removal, quality scoring, and
    format validation on chat-format JSONL data. Built on the SDG Hub
    framework (Red Hat supported).

    Optional LLM Judge:
      When enable_llm_judge=True, each example is scored by an LLM
      for answer quality and factual grounding. Requires an OpenAI-compatible
      endpoint (e.g., vLLM on KServe). Examples scoring below threshold
      are flagged or removed. Useful for synthetic/generated training data.
      For expert-curated data, leave disabled (default).

    Args:
        output_dataset: Cleaned dataset artifact (JSONL).
        output_metrics: Quality metrics (rows before/after, duplicates found, etc.).
        input_dataset: Input dataset artifact from upstream component.
        input_pvc_path: Path to input JSONL on PVC (alternative to artifact).
        pvc_mount_path: PVC mount path for exports.
        similarity_threshold: Fuzzy dedup threshold (0.0-1.0). Higher = stricter.
        min_assistant_tokens: Minimum word count for assistant response.
        min_user_tokens: Minimum word count for user prompt.
        max_repetition_ratio: Max ratio of repeated words in assistant response.
        export_to_pvc: Whether to save cleaned dataset to PVC.
        shared_log_file: Pipeline log file name.
        enable_llm_judge: Enable LLM-based quality scoring (requires endpoint).
        llm_judge_endpoint: OpenAI-compatible API endpoint for the judge model
            (e.g., http://vllm-judge.namespace.svc.cluster.local:8000/v1).
    """
    import hashlib
    import json
    import logging
    import os
    import time
    from difflib import SequenceMatcher

    import pandas as pd

    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s - %(levelname)s - %(message)s",
    )
    log = logging.getLogger("data_quality")

    start_time = time.time()

    def log_message(msg: str):
        log.info(msg)
        if pvc_mount_path and shared_log_file:
            log_path = os.path.join(pvc_mount_path, shared_log_file)
            try:
                with open(log_path, "a") as f:
                    f.write(msg + "\n")
            except OSError:
                pass

    log_message("=" * 60)
    log_message("Data Quality Filter — SDG Hub Framework")
    log_message("=" * 60)

    # =====================================================================
    # Load input data
    # =====================================================================
    if input_dataset and os.path.exists(input_dataset.path):
        log_message(f"Loading from artifact: {input_dataset.path}")
        data = []
        with open(input_dataset.path, "r") as f:
            for line in f:
                line = line.strip()
                if line:
                    data.append(json.loads(line))
    elif input_pvc_path and os.path.exists(input_pvc_path):
        log_message(f"Loading from PVC: {input_pvc_path}")
        data = []
        with open(input_pvc_path, "r") as f:
            for line in f:
                line = line.strip()
                if line:
                    data.append(json.loads(line))
    else:
        raise ValueError("No input provided. Supply input_dataset or input_pvc_path.")

    total_input = len(data)
    log_message(f"Loaded {total_input} examples")

    # =====================================================================
    # Step 1: Format validation — keep only valid chat-format rows
    # =====================================================================
    valid_data = []
    format_rejected = 0
    for row in data:
        messages = row.get("messages") or row.get("conversations")
        if not messages or not isinstance(messages, list):
            format_rejected += 1
            continue
        has_user = any(m.get("role") == "user" and m.get("content", "").strip() for m in messages)
        has_assistant = any(m.get("role") == "assistant" and m.get("content", "").strip() for m in messages)
        if not has_user or not has_assistant:
            format_rejected += 1
            continue
        valid_data.append(row)

    log_message(f"Format validation: {format_rejected} rejected, {len(valid_data)} valid")

    # =====================================================================
    # Step 2: Extract user prompt and assistant response for analysis
    # =====================================================================
    def extract_user_prompt(row):
        messages = row.get("messages") or row.get("conversations") or []
        for m in messages:
            if m.get("role") == "user":
                return m.get("content", "").strip()
        return ""

    def extract_assistant_response(row):
        messages = row.get("messages") or row.get("conversations") or []
        for m in messages:
            if m.get("role") == "assistant":
                return m.get("content", "").strip()
        return ""

    # =====================================================================
    # Step 3: Exact deduplication (hash-based on user prompt)
    # =====================================================================
    seen_hashes = set()
    exact_dedup_data = []
    exact_dupes = 0
    for row in valid_data:
        prompt = extract_user_prompt(row)
        prompt_hash = hashlib.sha256(prompt.lower().encode()).hexdigest()
        if prompt_hash in seen_hashes:
            exact_dupes += 1
            continue
        seen_hashes.add(prompt_hash)
        exact_dedup_data.append(row)

    log_message(f"Exact dedup: {exact_dupes} duplicates removed, {len(exact_dedup_data)} remaining")

    # =====================================================================
    # Step 4: Near-duplicate removal (fuzzy similarity on user prompt)
    # Uses difflib.SequenceMatcher — same algorithm as SDG Hub's
    # SimilarityFilterBlock (PR #665, Red-Hat-AI-Innovation-Team/sdg_hub)
    # =====================================================================
    if similarity_threshold < 1.0:
        kept_prompts = []
        near_dedup_data = []
        near_dupes = 0
        for row in exact_dedup_data:
            prompt = extract_user_prompt(row).lower()
            is_near_dupe = False
            for kept in kept_prompts:
                ratio = SequenceMatcher(None, prompt, kept).ratio()
                if ratio >= similarity_threshold:
                    is_near_dupe = True
                    break
            if is_near_dupe:
                near_dupes += 1
            else:
                kept_prompts.append(prompt)
                near_dedup_data.append(row)

        log_message(f"Near-dedup (threshold={similarity_threshold}): {near_dupes} removed, {len(near_dedup_data)} remaining")
    else:
        near_dedup_data = exact_dedup_data
        near_dupes = 0
        log_message("Near-dedup: skipped (threshold=1.0)")

    # =====================================================================
    # Step 5: Quality scoring
    # =====================================================================
    quality_rejected = 0
    clean_data = []
    for row in near_dedup_data:
        prompt = extract_user_prompt(row)
        response = extract_assistant_response(row)
        prompt_words = prompt.split()
        response_words = response.split()

        if len(prompt_words) < min_user_tokens:
            quality_rejected += 1
            continue
        if len(response_words) < min_assistant_tokens:
            quality_rejected += 1
            continue

        if response_words:
            unique_words = set(w.lower() for w in response_words)
            repetition_ratio = 1.0 - (len(unique_words) / len(response_words))
            if repetition_ratio > max_repetition_ratio:
                quality_rejected += 1
                continue

        clean_data.append(row)

    log_message(f"Quality filter: {quality_rejected} low-quality removed, {len(clean_data)} remaining")

    # =====================================================================
    # Step 6 (optional): LLM Judge — hallucination and quality grading
    # When enabled, scores each example using an LLM endpoint. Useful for
    # synthetic/generated data where factual grounding matters.
    # Uses SDG Hub's LLM integration pattern.
    # =====================================================================
    llm_judge_rejected = 0
    if enable_llm_judge and llm_judge_endpoint:
        if not llm_judge_api_key:
            llm_judge_api_key = os.environ.get("GEMINI_API_KEY", "")
        log_message(f"LLM Judge enabled — endpoint: {llm_judge_endpoint}, model: {llm_judge_model}")
        try:
            import requests

            judge_system_prompt = (
                "You are a training data quality judge. Score the following "
                "instruction-response pair from 1-10 based on:\n"
                "- Relevance: Does the response answer the question?\n"
                "- Accuracy: Is the response factually correct?\n"
                "- Completeness: Is the response complete?\n"
                "- Clarity: Is the response clear and well-structured?\n\n"
                "Respond with ONLY a single integer score (1-10). "
                "Score 1-4 = reject, 5-6 = marginal, 7-10 = good."
            )

            judged_data = []
            for i, row in enumerate(clean_data):
                prompt = extract_user_prompt(row)
                response = extract_assistant_response(row)

                judge_messages = [
                    {"role": "system", "content": judge_system_prompt},
                    {"role": "user", "content": f"Instruction: {prompt}\n\nResponse: {response}"},
                ]

                try:
                    judge_headers = {"Content-Type": "application/json"}
                    if llm_judge_api_key:
                        judge_headers["Authorization"] = f"Bearer {llm_judge_api_key}"

                    resp = requests.post(
                        f"{llm_judge_endpoint.rstrip('/')}/chat/completions",
                        headers=judge_headers,
                        json={
                            "model": llm_judge_model,
                            "messages": judge_messages,
                            "max_tokens": 5,
                            "temperature": 0.0,
                        },
                        timeout=30,
                    )
                    score_text = resp.json()["choices"][0]["message"]["content"].strip()
                    score = int("".join(c for c in score_text if c.isdigit())[:2] or "5")
                except Exception:
                    score = 5

                if score >= 5:
                    judged_data.append(row)
                else:
                    llm_judge_rejected += 1

                if (i + 1) % 100 == 0:
                    log_message(f"  LLM Judge progress: {i + 1}/{len(clean_data)}")

            clean_data = judged_data
            log_message(f"LLM Judge: {llm_judge_rejected} rejected (score < 5), {len(clean_data)} remaining")

        except ImportError:
            log_message("LLM Judge: 'requests' not available, skipping")
        except Exception as e:
            log_message(f"LLM Judge: error ({e}), continuing without judge")
    elif enable_llm_judge and not llm_judge_endpoint:
        log_message("LLM Judge: enabled but no endpoint provided — skipping")
    else:
        log_message("LLM Judge: disabled (default for expert-curated data)")

    # =====================================================================
    # Output
    # =====================================================================
    total_output = len(clean_data)
    total_removed = total_input - total_output

    with open(output_dataset.path, "w") as f:
        for row in clean_data:
            f.write(json.dumps(row) + "\n")

    if export_to_pvc and pvc_mount_path:
        pvc_output_dir = os.path.join(pvc_mount_path, "datasets", "cleaned")
        os.makedirs(pvc_output_dir, exist_ok=True)
        pvc_output_path = os.path.join(pvc_output_dir, "cleaned.jsonl")
        with open(pvc_output_path, "w") as f:
            for row in clean_data:
                f.write(json.dumps(row) + "\n")
        log_message(f"Cleaned dataset saved to PVC: {pvc_output_path}")

    try:
        output_dataset.metadata["num_examples"] = str(total_output)
        output_dataset.metadata["pvc_path"] = os.path.join(pvc_mount_path, "datasets", "cleaned", "cleaned.jsonl") if pvc_mount_path else ""
    except Exception:
        pass

    elapsed = time.time() - start_time
    output_metrics.log_metric("input_rows", total_input)
    output_metrics.log_metric("output_rows", total_output)
    output_metrics.log_metric("total_removed", total_removed)
    output_metrics.log_metric("removal_rate", round(total_removed / max(total_input, 1) * 100, 1))
    output_metrics.log_metric("format_rejected", format_rejected)
    output_metrics.log_metric("exact_duplicates", exact_dupes)
    output_metrics.log_metric("near_duplicates", near_dupes)
    output_metrics.log_metric("quality_rejected", quality_rejected)
    output_metrics.log_metric("llm_judge_rejected", llm_judge_rejected)
    output_metrics.log_metric("llm_judge_enabled", 1 if (enable_llm_judge and llm_judge_endpoint) else 0)
    output_metrics.log_metric("execution_seconds", round(elapsed, 2))

    log_message("")
    log_message("=" * 60)
    log_message(f"Data Quality Summary:")
    log_message(f"  Input:            {total_input:,} examples")
    log_message(f"  Format rejected:  {format_rejected:,}")
    log_message(f"  Exact duplicates: {exact_dupes:,}")
    log_message(f"  Near-duplicates:  {near_dupes:,}")
    log_message(f"  Quality rejected: {quality_rejected:,}")
    log_message(f"  LLM judge:        {llm_judge_rejected:,}" if enable_llm_judge else "  LLM judge:        disabled")
    log_message(f"  Output:           {total_output:,} examples ({total_removed:,} removed, {round(total_removed / max(total_input, 1) * 100, 1)}%)")
    log_message(f"  Time:             {elapsed:.1f}s")
    log_message("=" * 60)

    # =====================================================================
    # MLflow Dataset Tracking (optional)
    #   Registers the cleaned dataset as an MLflow artifact with quality
    #   metadata so it can be browsed and reused from the MLflow UI.
    # =====================================================================
    if mlflow_tracking_uri:
        try:
            import mlflow

            mlflow.set_tracking_uri(mlflow_tracking_uri)
            mlflow.set_experiment(mlflow_experiment_name)

            dataset_name = input_pvc_path or "cleaned_dataset"
            if hasattr(input_dataset, "metadata"):
                src = (getattr(input_dataset, "metadata", {}) or {}).get("dataset_uri", "")
                if src:
                    dataset_name = src.replace("hf://", "").replace("/", "_")

            with mlflow.start_run(run_name=f"dataset_{dataset_name}_{total_output}ex"):
                mlflow.log_param("source_uri", (getattr(input_dataset, "metadata", {}) or {}).get("dataset_uri", "unknown"))
                mlflow.log_param("input_examples", total_input)
                mlflow.log_param("output_examples", total_output)
                mlflow.log_param("format_rejected", format_rejected)
                mlflow.log_param("exact_duplicates", exact_dupes)
                mlflow.log_param("near_duplicates", near_dupes)
                mlflow.log_param("quality_rejected", quality_rejected)
                mlflow.log_param("llm_judge_rejected", llm_judge_rejected)
                mlflow.log_param("llm_judge_enabled", enable_llm_judge)
                mlflow.log_param("similarity_threshold", similarity_threshold)
                mlflow.log_metric("removal_rate", round(total_removed / max(total_input, 1) * 100, 1))
                mlflow.log_metric("execution_seconds", round(elapsed, 2))

                if export_to_pvc and pvc_mount_path:
                    pvc_cleaned = os.path.join(pvc_mount_path, "datasets", "cleaned", "cleaned.jsonl")
                    if os.path.exists(pvc_cleaned):
                        mlflow.log_artifact(pvc_cleaned, artifact_path="datasets")

            log_message(f"MLflow: dataset registered in experiment '{mlflow_experiment_name}'")
        except Exception as e:
            log_message(f"MLflow: tracking failed ({e}), continuing")
