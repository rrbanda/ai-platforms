"""Custom (bring-your-own) training technique.

Demonstrates that any PyTorch training code can run in the same pipeline
framework. Replace train_func() with your own training logic.

Contract for custom training code:
  - Read data from params["data_path"]
  - Load base model from params["model_path"]
  - Save trained model + config.json to params["ckpt_output_dir"]
"""

ALGORITHM_NAME = "LORA_SFT"  # TrainingHub requires an algorithm; custom func ignores it
IS_SINGLE_NODE = True
DEFAULT_LR = 2e-4
DEFAULT_EPOCHS = 1


def build_params(common, **kw):
    """Custom technique uses only common params — no technique-specific additions."""
    return common


def train_func(**p):
    """Bring-your-own training: a plain PyTorch LoRA loop as an example.

    This function is serialized and runs inside the TrainJob pod. It has
    access to all packages in the training-hub image (PyTorch, Transformers,
    PEFT, etc.) but does NOT use the training_hub algorithm layer — proving
    that arbitrary customer code works.

    Replace this entire function body with your training code. The only
    contract is:
      - Read data from p["data_path"]
      - Load model from p["model_path"]
      - Write model + config.json to p["ckpt_output_dir"]
    """
    import os

    print("[PY] Launching custom training (bring-your-own demo)...", flush=True)
    print(f"[PY] Model: {p['model_path']}", flush=True)
    print(f"[PY] Data: {p['data_path']}", flush=True)
    print(f"[PY] Output: {p['ckpt_output_dir']}", flush=True)

    import torch
    from datasets import load_dataset
    from peft import LoraConfig, get_peft_model
    from transformers import (
        AutoModelForCausalLM,
        AutoTokenizer,
        Trainer,
        TrainingArguments,
    )

    model_path = p["model_path"]
    data_path = p["data_path"]
    output_dir = p["ckpt_output_dir"]
    lr = p.get("learning_rate", 2e-4)
    epochs = p.get("num_epochs", 1)
    max_seq = int(p.get("max_seq_len", 512))

    tokenizer = AutoTokenizer.from_pretrained(model_path, trust_remote_code=True)
    if tokenizer.pad_token is None:
        tokenizer.pad_token = tokenizer.eos_token

    model = AutoModelForCausalLM.from_pretrained(
        model_path,
        torch_dtype=torch.float16,
        device_map="auto",
        trust_remote_code=True,
    )

    peft_config = LoraConfig(r=16, lora_alpha=32, lora_dropout=0.0, task_type="CAUSAL_LM")
    model = get_peft_model(model, peft_config)
    model.print_trainable_parameters()

    ds = load_dataset("json", data_files=data_path, split="train")

    def tokenize(example):
        text = ""
        for msg in example.get("messages", []):
            text += f"<|{msg['role']}|>\n{msg['content']}\n"
        enc = tokenizer(text, truncation=True, max_length=max_seq, padding="max_length")
        enc["labels"] = enc["input_ids"].copy()
        return enc

    ds = ds.map(tokenize, remove_columns=ds.column_names)

    training_args = TrainingArguments(
        output_dir=output_dir,
        num_train_epochs=epochs,
        learning_rate=lr,
        per_device_train_batch_size=4,
        gradient_accumulation_steps=4,
        logging_steps=10,
        save_steps=200,
        save_total_limit=2,
        fp16=True,
        report_to="none",
    )

    trainer = Trainer(model=model, args=training_args, train_dataset=ds, tokenizer=tokenizer)
    trainer.train()

    merged = model.merge_and_unload()
    merged.save_pretrained(output_dir)
    tokenizer.save_pretrained(output_dir)

    print("[PY] Custom training complete.", flush=True)
    return None


def log_metrics(output_metrics, params, **kw):
    """Log custom-technique metrics."""
    output_metrics.log_metric("custom_technique", "bring-your-own-demo")
