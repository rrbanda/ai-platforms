"""Holdout Evaluation Component.

Local wrapper around the pipelines-components universal_llm_evaluator that
uses a CUDA-capable base image. The upstream component uses ubi9/python-311
which has no CUDA toolkit — vLLM's FlashInfer and deep_gemm JIT compilation
fail with 'Could not find nvcc'.

This component uses the training-hub CUDA image (has nvcc, Python 3.12,
PyTorch, CUDA 13.0) and sets the necessary env vars to disable JIT paths
that would still fail on some configurations.
"""

import os

from kfp import dsl

_EVAL_IMAGE = (
    "registry.redhat.io/rhoai/odh-th-torch-cuda-py312-rhel9"
    "@sha256:884aeeb039f9592252fe0c518acf31803a208757d4fa6500fe79884a022ea52d"
)


@dsl.component(
    base_image=_EVAL_IMAGE,
    packages_to_install=[
        "lm-eval[vllm]",
        "unitxt",
        "sacrebleu",
        "rouge-score",
        "datasets",
        "accelerate",
    ],
)
def holdout_llm_evaluator(
    output_metrics: dsl.Output[dsl.Metrics],
    output_results: dsl.Output[dsl.Artifact],
    output_samples: dsl.Output[dsl.Artifact],
    task_names: list,
    model_path: str = None,
    model_artifact: dsl.Input[dsl.Model] = None,
    eval_dataset: dsl.Input[dsl.Dataset] = None,
    model_args: dict = {},
    gen_kwargs: dict = {},
    batch_size: str = "auto",
    limit: int = -1,
    log_samples: bool = True,
    verbosity: str = "INFO",
    custom_eval_max_tokens: int = 256,
    enforce_eager: bool = True,
):
    """Holdout evaluation with CUDA-capable image.

    Same interface as universal_llm_evaluator but runs on a CUDA image
    with nvcc available for vLLM JIT compilation.

    Args:
        output_metrics: Output metrics artifact with evaluation scores.
        output_results: Full evaluation results JSON.
        output_samples: Logged evaluation samples.
        task_names: Benchmark task names (e.g. ["arc_easy"]).
        model_path: HF model ID or path. Used if model_artifact is None.
        model_artifact: KFP Model artifact from training step.
        eval_dataset: JSONL dataset for custom holdout evaluation.
        model_args: Model init args (e.g. {"dtype": "float16"}).
        gen_kwargs: Generation kwargs for the model.
        batch_size: Batch size ("auto" or integer).
        limit: Max examples per task (-1 = all).
        log_samples: Log individual evaluation samples.
        verbosity: Logging level.
        custom_eval_max_tokens: Max tokens for custom eval generation.
        enforce_eager: Disable CUDA graphs (avoids JIT compilation issues).
    """
    import json
    import logging
    import multiprocessing
    import os
    import random
    import time

    multiprocessing.set_start_method("spawn", force=True)
    os.environ["VLLM_WORKER_MULTIPROC_METHOD"] = "spawn"
    os.environ["VLLM_ATTENTION_BACKEND"] = "FLASH_ATTN"
    os.environ["VLLM_USE_FLASHINFER_SAMPLER"] = "0"
    os.environ["FLASHINFER_ENABLE_AOT"] = "1"

    import torch

    from lm_eval.api.instance import Instance
    from lm_eval.api.metrics import mean
    from lm_eval.api.registry import get_model
    from lm_eval.api.task import Task, TaskConfig
    from lm_eval.evaluator import evaluate
    from lm_eval.tasks import get_task_dict

    logging.basicConfig(
        level=getattr(logging, verbosity.upper()),
        format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
    )
    logger = logging.getLogger("HoldoutEval")

    if not torch.cuda.is_available():
        logger.warning("CUDA is not available! Evaluation will be extremely slow.")

    def extract_chat_parts(messages: list) -> tuple:
        system_content, user_content, assistant_content = None, None, None
        for msg in messages:
            role = msg.get("role", "")
            content = msg.get("content", "")
            if role == "system":
                system_content = content
            elif role == "user":
                user_content = content
            elif role == "assistant":
                assistant_content = content
        return system_content, user_content, assistant_content

    def validate_dataset(path: str, sample_size: int = 10) -> bool:
        with open(path) as f:
            lines = [json.loads(line) for line in f if line.strip()]
        sample = random.sample(lines, min(sample_size, len(lines)))
        for item in sample:
            msgs = item.get("messages", item.get("conversations", []))
            if not msgs:
                return False
            _, user, assistant = extract_chat_parts(msgs)
            if not user or not assistant:
                return False
        logger.info(f"Dataset format validated: {len(sample)}/{len(sample)} samples checked OK")
        return True

    final_model_path = model_path
    if model_artifact:
        art_path = model_artifact.path
        if os.path.isdir(art_path):
            final_model_path = art_path
        elif os.path.isfile(art_path):
            final_model_path = os.path.dirname(art_path)
        logger.info(f"Using model from artifact path: {final_model_path}")

        meta = getattr(model_artifact, "metadata", {}) or {}
        pvc_dir = (meta.get("pvc_model_dir") or "").strip()
        if pvc_dir and os.path.isdir(pvc_dir) and os.path.exists(os.path.join(pvc_dir, "config.json")):
            final_model_path = pvc_dir
            logger.info(f"Using PVC model path: {final_model_path}")

    if not final_model_path:
        raise ValueError("No model provided. Set model_path or model_artifact.")

    if not os.path.exists(os.path.join(final_model_path, "config.json")):
        for root, _, files in os.walk(final_model_path):
            if "config.json" in files:
                final_model_path = root
                logger.info(f"Found model config at: {final_model_path}")
                break

    eval_jsonl = None
    if eval_dataset:
        ds_path = eval_dataset.path
        meta = getattr(eval_dataset, "metadata", {}) or {}
        logger.info(f"Eval dataset: {meta.get('num_examples', '?')} examples from {meta.get('split', '?')} split")

        pvc_path = (meta.get("pvc_path") or "").strip()
        if pvc_path and os.path.isfile(pvc_path):
            eval_jsonl = pvc_path
        elif os.path.isfile(ds_path):
            eval_jsonl = ds_path
        elif os.path.isdir(ds_path):
            for fn in ["eval.jsonl", "test.jsonl", "data.jsonl"]:
                candidate = os.path.join(ds_path, fn)
                if os.path.isfile(candidate):
                    eval_jsonl = candidate
                    break

        if eval_jsonl:
            logger.info(f"Found eval JSONL for custom evaluation: {eval_jsonl}")

    class CustomHoldoutTask(Task):
        VERSION = 0
        OUTPUT_TYPE = "generate_until"

        def __init__(self, data_path, max_tokens=256, **kwargs):
            self._data_path = data_path
            self._max_tokens = max_tokens
            self._dataset = None
            config = TaskConfig(
                task="custom_holdout_eval",
                num_fewshot=0,
                output_type="generate_until",
                generation_kwargs={
                    "temperature": 0.0,
                    "do_sample": False,
                    "max_gen_toks": max_tokens,
                    "until": ["\n\n"],
                },
                metric_list=[
                    {"metric": "exact_match", "aggregation": "mean", "higher_is_better": True},
                ],
            )
            super().__init__(config=config, **kwargs)

        def download(self, *args, **kwargs):
            pass

        def has_training_docs(self):
            return False

        def has_validation_docs(self):
            return False

        def has_test_docs(self):
            return True

        def _load_data(self):
            if self._dataset is None:
                with open(self._data_path) as f:
                    self._dataset = [json.loads(line) for line in f if line.strip()]
                logger.info(f"Loaded {len(self._dataset)} examples from {self._data_path}")
            return self._dataset

        def test_docs(self):
            return self._load_data()

        def doc_to_text(self, doc):
            messages = doc.get("messages", doc.get("conversations", []))
            prompt = ""
            for msg in messages:
                if msg["role"] == "assistant":
                    break
                prompt += f"<|{msg['role']}|>\n{msg['content']}\n"
            prompt += "<|assistant|>\n"
            return prompt

        def doc_to_target(self, doc):
            messages = doc.get("messages", doc.get("conversations", []))
            for msg in messages:
                if msg["role"] == "assistant":
                    return msg.get("content", "")
            return ""

        def construct_requests(self, doc, ctx, **kwargs):
            return [Instance(
                request_type="generate_until",
                doc=doc,
                arguments=(ctx, {"until": ["\n\n"], "max_gen_toks": self._max_tokens}),
                idx=0,
                **kwargs,
            )]

        def process_results(self, doc, results):
            pred = results[0].strip() if results else ""
            ref = self.doc_to_target(doc).strip()
            em = 1.0 if pred == ref else 0.0
            return {"exact_match": em}

        def aggregation(self):
            return {"exact_match": mean}

        def higher_is_better(self):
            return {"exact_match": True}

    tasks_to_eval = {}

    if eval_jsonl and validate_dataset(eval_jsonl):
        holdout_task = CustomHoldoutTask(eval_jsonl, max_tokens=custom_eval_max_tokens)
        tasks_to_eval["custom_holdout_eval"] = holdout_task
        logger.info("Added custom holdout task to evaluation")

    if task_names:
        logger.info(f"Adding benchmark tasks: {task_names}")
        benchmark_tasks = get_task_dict(task_names)
        tasks_to_eval.update(benchmark_tasks)

    for name, task in tasks_to_eval.items():
        cfg = getattr(task, "_config", None) or getattr(task, "config", None)
        if cfg:
            logger.info(f"Task: {name} ({getattr(cfg, 'task', 'unknown')})")

    if not tasks_to_eval:
        logger.warning("No tasks to evaluate. Skipping.")
        output_metrics.log_metric("status", "skipped")
        with open(output_results.path, "w") as f:
            json.dump({"status": "skipped"}, f)
        with open(output_samples.path, "w") as f:
            json.dump({"status": "skipped"}, f)
        return

    logger.info(f"Total tasks to evaluate: {len(tasks_to_eval)}")
    logger.info("Loading model with vLLM backend...")
    start_time = time.time()

    m_args = dict(model_args) if model_args else {}
    if enforce_eager:
        m_args["enforce_eager"] = True

    try:
        vllm_model_args = {
            "pretrained": final_model_path,
            "trust_remote_code": True,
            "gpu_memory_utilization": 0.8,
            "dtype": "auto",
        }
        vllm_model_args.update(m_args)

        model_class = get_model("vllm")

        if batch_size == "auto":
            bs = "auto"
        else:
            try:
                bs = int(batch_size)
            except ValueError:
                bs = "auto"

        additional_config = {"batch_size": bs, "device": None}
        loaded_model = model_class.create_from_arg_obj(vllm_model_args, additional_config)
        logger.info(f"Model loaded successfully in {time.time() - start_time:.2f}s")
    except Exception as e:
        logger.error(f"Failed to load model: {e}")
        raise RuntimeError(f"Model loading failed: {e}")

    logger.info("Starting evaluation...")
    start_time = time.time()

    try:
        eval_limit = None if limit == -1 else limit
        results = evaluate(
            lm=loaded_model,
            task_dict=tasks_to_eval,
            limit=eval_limit,
            log_samples=log_samples,
        )
        logger.info(f"Evaluation completed in {time.time() - start_time:.2f}s")
    except Exception as e:
        logger.error(f"Evaluation failed: {e}")
        raise RuntimeError(f"Evaluation failed: {e}")

    clean_results = {}
    for task_name, task_results in results.get("results", {}).items():
        clean_results[task_name] = {}
        for metric_name, value in task_results.items():
            if metric_name.endswith(",none"):
                metric_name = metric_name[:-5]
            if metric_name.endswith("_stderr"):
                continue
            if isinstance(value, (int, float)):
                clean_results[task_name][metric_name] = round(value, 4)
                output_metrics.log_metric(f"{task_name}_{metric_name}", round(value, 4))

    output_results.name = "eval_results.json"
    with open(output_results.path, "w") as f:
        json.dump(clean_results, f, indent=2)

    if log_samples and "samples" in clean_results:
        output_samples.name = "eval_samples.json"
        with open(output_samples.path, "w") as f:
            json.dump(clean_results["samples"], f, indent=2)
