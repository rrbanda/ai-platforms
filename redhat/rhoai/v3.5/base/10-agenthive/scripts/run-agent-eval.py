#!/usr/bin/env python3
"""
MLflow Agent Evaluation for the RFP Agent.

This script evaluates the RFP agent using MLflow's genai.evaluate() API
with LLM-as-judge scorers. Per the RHOAI training course:
"Evaluate agents using MLflow"

Scorers:
- Correctness: Is the answer correct vs ground truth?
- Faithfulness: Is it grounded in retrieved context?
- RelevanceToQuery: Does the answer address the question?

Requirements: mlflow>=3.0, openai (for Gemini judge)
Run on the cluster in a workbench with Python 3.11+.
"""

import json
import os
import sys
from pathlib import Path

# MLflow configuration
MLFLOW_TRACKING_URI = os.environ.get(
    "MLFLOW_TRACKING_URI",
    "https://mlflow.redhat-ods-applications.svc.cluster.local:8443"
)
MLFLOW_EXPERIMENT_NAME = os.environ.get("MLFLOW_EXPERIMENT", "rfp-agent-evaluation")

# Gemini as the LLM judge
GEMINI_API_KEY = os.environ.get("OPENAI_API_KEY", os.environ.get("GEMINI_API_KEY", ""))
GEMINI_BASE_URL = "https://generativelanguage.googleapis.com/v1beta/openai/"

DATASET_PATH = Path(os.environ.get("EVAL_DATASET_PATH", str(Path(__file__).parent / "ragas-eval-dataset.json")))


def setup_mlflow():
    """Configure MLflow tracking with kubernetes-namespaced auth (RHOAI 3.5)."""
    import mlflow

    mlflow.set_tracking_uri(MLFLOW_TRACKING_URI)

    # kubernetes-namespaced auth uses the pod's SA token automatically
    # when MLFLOW_TRACKING_AUTH=kubernetes-namespaced is set as env var.
    # The workspace is derived from the pod's namespace.
    mlflow.set_experiment(MLFLOW_EXPERIMENT_NAME)

    # Configure the LLM judge endpoint (Gemini via OpenAI-compatible API)
    os.environ["OPENAI_API_KEY"] = GEMINI_API_KEY
    os.environ["OPENAI_API_BASE"] = GEMINI_BASE_URL

    print(f"MLflow tracking URI: {MLFLOW_TRACKING_URI}")
    print(f"MLflow auth: {os.environ.get('MLFLOW_TRACKING_AUTH', 'not set')}")
    print(f"Experiment: {MLFLOW_EXPERIMENT_NAME}")
    return mlflow


def load_eval_dataset():
    """Load and format the evaluation dataset for MLflow."""
    print(f"Loading dataset from {DATASET_PATH}")
    raw = json.loads(DATASET_PATH.read_text())

    # Filter valid samples
    valid = [s for s in raw if "Error" not in s.get("answer", "")]
    print(f"  {len(valid)} valid samples (of {len(raw)} total)")

    # Format for MLflow genai.evaluate():
    # Each row needs: inputs, outputs (predictions), expectations (ground truth)
    eval_data = []
    for sample in valid:
        eval_data.append({
            "inputs": {
                "question": sample["question"],
                "context": "\n\n---\n\n".join(sample.get("contexts", [])),
            },
            "outputs": {
                "answer": sample["answer"],
            },
            "expectations": {
                "expected_answer": sample["ground_truth"],
            },
        })

    return eval_data


def run_evaluation():
    """Run the MLflow agent evaluation with scorers."""
    import mlflow
    from mlflow.genai.scorers import (
        Correctness,
        Faithfulness,
        RelevanceToQuery,
    )

    eval_data = load_eval_dataset()

    print(f"\nRunning MLflow agent evaluation...")
    print(f"  Samples: {len(eval_data)}")
    print(f"  Scorers: Correctness, Faithfulness, RelevanceToQuery")
    print(f"  Judge model: Gemini (via OpenAI-compatible API)")

    with mlflow.start_run(run_name="rfp-agent-baseline-v1") as run:
        # Log evaluation metadata
        mlflow.log_params({
            "agent_name": "rfp-agent",
            "model": "gemini-2.5-pro",
            "rag_backend": "milvus",
            "embedding_model": "sentence-transformers/all-MiniLM-L6-v2",
            "corpus_size": "30 documents",
            "eval_samples": len(eval_data),
        })

        # Run evaluation with LLM-as-judge scorers
        results = mlflow.genai.evaluate(
            data=eval_data,
            scorers=[
                Correctness(),
                Faithfulness(),
                RelevanceToQuery(),
            ],
        )

        # Log summary metrics
        print(f"\n{'='*60}")
        print(f"Evaluation Results (Run ID: {run.info.run_id})")
        print(f"{'='*60}")

        if hasattr(results, 'metrics'):
            for metric_name, metric_value in results.metrics.items():
                print(f"  {metric_name}: {metric_value:.4f}")
                mlflow.log_metric(f"eval/{metric_name}", metric_value)

        if hasattr(results, 'tables'):
            for table_name, table in results.tables.items():
                print(f"\n  Table: {table_name}")
                print(f"  Rows: {len(table)}")

        print(f"\nResults logged to MLflow experiment: {MLFLOW_EXPERIMENT_NAME}")
        print(f"Run ID: {run.info.run_id}")
        print(f"View at: {MLFLOW_TRACKING_URI}/#/experiments")

    return results


def run_evaluation_manual():
    """
    Fallback: Manual evaluation without mlflow.genai.evaluate().
    Uses Gemini directly as judge and logs to MLflow manually.
    Works with MLflow 2.x or environments without genai scorers.
    """
    import mlflow
    import requests

    eval_data = load_eval_dataset()

    print(f"\nRunning manual agent evaluation (MLflow tracking)...")
    print(f"  Samples: {len(eval_data)}")
    print(f"  Judge: Gemini via API")

    judge_prompt_correctness = """You are an expert evaluator. Score the following answer for CORRECTNESS against the expected answer.

Question: {question}
Expected Answer: {expected_answer}
Actual Answer: {actual_answer}

Score from 1-5 where:
1 = Completely wrong
2 = Mostly wrong with some correct elements  
3 = Partially correct
4 = Mostly correct with minor issues
5 = Fully correct and complete

Respond with ONLY a JSON object: {{"score": <number>, "reasoning": "<brief explanation>"}}"""

    judge_prompt_faithfulness = """You are an expert evaluator. Score the following answer for FAITHFULNESS to the provided context.

Context: {context}
Question: {question}
Answer: {actual_answer}

Score from 1-5 where:
1 = Answer contains claims not supported by context (hallucination)
2 = Most claims are unsupported
3 = Some claims are grounded, some are not
4 = Most claims are grounded in context
5 = All claims are directly supported by context

Respond with ONLY a JSON object: {{"score": <number>, "reasoning": "<brief explanation>"}}"""

    def judge_with_gemini(prompt: str, retries: int = 3) -> dict:
        """Call Gemini to get a judgment score with retry + backoff."""
        import re
        import time as _time

        for attempt in range(retries):
            try:
                resp = requests.post(
                    f"{GEMINI_BASE_URL}chat/completions",
                    headers={
                        "Authorization": f"Bearer {GEMINI_API_KEY}",
                        "Content-Type": "application/json",
                    },
                    json={
                        "model": "gemini-2.5-flash",
                        "messages": [{"role": "user", "content": prompt}],
                        "temperature": 0.0,
                        "max_tokens": 4096,
                    },
                    timeout=30,
                )
                if resp.status_code == 429:
                    wait = 30 * (attempt + 1)
                    print(f"    Rate limited (429), waiting {wait}s...")
                    _time.sleep(wait)
                    continue
                if resp.status_code != 200:
                    print(f"    Judge API error: {resp.status_code}")
                    _time.sleep(5)
                    continue

                content = resp.json()["choices"][0]["message"]["content"]

                # Strategy 1: Find a JSON object containing "score"
                json_match = re.search(r'\{[^{}]*"score"\s*:\s*\d[^{}]*\}', content, re.DOTALL)
                if json_match:
                    try:
                        return json.loads(json_match.group())
                    except json.JSONDecodeError:
                        pass

                # Strategy 2: Regex extract "score": N
                score_match = re.search(r'"?score"?\s*[:=]\s*(\d)', content)
                if score_match:
                    return {"score": int(score_match.group(1)), "reasoning": "extracted via regex"}

                # Strategy 3: Look for "Score: N/5" pattern
                score_match2 = re.search(r'[Ss]core[:\s]+(\d)\s*/\s*5', content)
                if score_match2:
                    return {"score": int(score_match2.group(1)), "reasoning": "extracted from text"}

                print(f"    No score found (attempt {attempt+1}), raw: {content[:150]}")
                _time.sleep(2)
            except Exception as e:
                print(f"    Judge error (attempt {attempt+1}): {e}")
                _time.sleep(5)

        return {"score": 0, "reasoning": "All retry attempts failed"}

    with mlflow.start_run(run_name="rfp-agent-baseline-v1") as run:
        mlflow.log_params({
            "agent_name": "rfp-agent",
            "model": "gemini-2.5-pro",
            "judge_model": "gemini-2.5-flash",
            "rag_backend": "milvus",
            "embedding_model": "sentence-transformers/all-MiniLM-L6-v2",
            "eval_samples": len(eval_data),
            "eval_method": "manual_llm_judge",
        })

        correctness_scores = []
        faithfulness_scores = []

        for i, sample in enumerate(eval_data, 1):
            question = sample["inputs"]["question"]
            context = sample["inputs"]["context"]
            answer = sample["outputs"]["answer"]
            expected = sample["expectations"]["expected_answer"]

            print(f"  [{i}/{len(eval_data)}] Evaluating: {question[:60]}...")

            # Correctness
            c_result = judge_with_gemini(judge_prompt_correctness.format(
                question=question, expected_answer=expected, actual_answer=answer
            ))
            correctness_scores.append(c_result.get("score", 0))

            import time
            time.sleep(3)

            # Faithfulness
            f_result = judge_with_gemini(judge_prompt_faithfulness.format(
                context=context[:3000], question=question, actual_answer=answer
            ))
            faithfulness_scores.append(f_result.get("score", 0))

            time.sleep(3)

        # Calculate averages
        avg_correctness = sum(correctness_scores) / len(correctness_scores) if correctness_scores else 0
        avg_faithfulness = sum(faithfulness_scores) / len(faithfulness_scores) if faithfulness_scores else 0

        # Log metrics
        mlflow.log_metric("eval/correctness_avg", avg_correctness)
        mlflow.log_metric("eval/faithfulness_avg", avg_faithfulness)
        mlflow.log_metric("eval/correctness_normalized", avg_correctness / 5.0)
        mlflow.log_metric("eval/faithfulness_normalized", avg_faithfulness / 5.0)

        # Log per-sample results as artifact
        detailed_results = {
            "summary": {
                "correctness_avg": avg_correctness,
                "faithfulness_avg": avg_faithfulness,
                "total_samples": len(eval_data),
            },
            "per_sample": [
                {
                    "question": eval_data[i]["inputs"]["question"],
                    "correctness": correctness_scores[i],
                    "faithfulness": faithfulness_scores[i],
                }
                for i in range(len(eval_data))
            ]
        }

        results_path = Path("/tmp/eval-results.json")
        results_path.write_text(json.dumps(detailed_results, indent=2))
        mlflow.log_artifact(str(results_path))

        print(f"\n{'='*60}")
        print(f"EVALUATION RESULTS (Run ID: {run.info.run_id})")
        print(f"{'='*60}")
        print(f"  Correctness (avg):   {avg_correctness:.2f}/5.0 ({avg_correctness/5:.1%})")
        print(f"  Faithfulness (avg):  {avg_faithfulness:.2f}/5.0 ({avg_faithfulness/5:.1%})")
        print(f"  Total samples:       {len(eval_data)}")
        print(f"\nResults logged to MLflow experiment: {MLFLOW_EXPERIMENT_NAME}")
        print(f"Run ID: {run.info.run_id}")

        # Print per-sample scores for log traceability
        print(f"\n--- Per-Sample Scores ---")
        for i, sample in enumerate(eval_data):
            q = sample["inputs"]["question"][:55]
            c = correctness_scores[i]
            f_ = faithfulness_scores[i]
            print(f"  [{i+1:2d}] C={c} F={f_} | {q}...")

    return detailed_results


def main():
    if not GEMINI_API_KEY:
        print("ERROR: Set OPENAI_API_KEY or GEMINI_API_KEY environment variable")
        sys.exit(1)

    if not DATASET_PATH.exists():
        print(f"ERROR: Dataset not found at {DATASET_PATH}")
        print("  Run build-ragas-dataset.py first.")
        sys.exit(1)

    try:
        mlflow = setup_mlflow()
        # Try the full genai.evaluate() first
        try:
            from mlflow.genai.scorers import Correctness
            print("MLflow genai scorers available — using mlflow.genai.evaluate()")
            results = run_evaluation()
        except (ImportError, AttributeError) as e:
            print(f"MLflow genai scorers not available ({e})")
            print("Falling back to manual LLM-as-judge evaluation...")
            results = run_evaluation_manual()
    except Exception as e:
        print(f"MLflow connection failed ({e})")
        print("Running manual evaluation with local output only...")
        # Can still run locally without MLflow tracking
        os.environ.setdefault("MLFLOW_TRACKING_URI", "sqlite:///mlflow.db")
        import mlflow
        mlflow.set_tracking_uri("sqlite:///mlflow.db")
        mlflow.set_experiment(MLFLOW_EXPERIMENT_NAME)
        results = run_evaluation_manual()

    print("\nDone.")


if __name__ == "__main__":
    main()
