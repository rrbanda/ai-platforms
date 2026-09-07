---
name: training-planner
description: "Plan model training — resource estimation, method selection (LoRA vs full fine-tuning), hardware matching, and job configuration."
version: 1.0.0
author: RHOAI Platform Team
license: Apache-2.0
platforms: [linux]
metadata:
  hermes:
    tags: [RHOAI, OpenShift AI, Data Scientist, Training, Fine-tuning, LoRA, GPU]
---

# Training Planner

Plans model training jobs with resource estimation, training method selection (LoRA vs full fine-tuning vs QLoRA), hardware matching, and distributed training configuration.

## Trigger Phrases

- "Plan training for 7B model"
- "How many GPUs do I need for fine-tuning?"
- "Should I use LoRA or full fine-tuning?"
- "Estimate training resources for Llama"
- "Set up distributed training"
- "Plan a training job"

## Procedure

### Phase 1: Gather Training Requirements

1. Identify model and training parameters:
   - Base model (architecture, parameter count)
   - Training type: pre-training, full fine-tuning, LoRA, QLoRA
   - Dataset size (samples, tokens)
   - Target quality metrics
   - Time constraints

### Phase 2: Method Selection

2. Apply the training method decision tree:

| Criterion | Full Fine-Tuning | LoRA | QLoRA |
|-----------|-----------------|------|-------|
| Model size ≤3B | ✓ Recommended | ✓ Good | Overkill |
| Model size 7-13B | Expensive | ✓ Recommended | ✓ Budget option |
| Model size ≥34B | Very expensive | ✓ Good | ✓ Recommended |
| Dataset <1000 samples | Overfitting risk | ✓ Recommended | ✓ Good |
| Dataset >100K samples | ✓ Recommended | Good | Good |
| Need all params tuned | ✓ Required | ✗ Partial | ✗ Partial |
| Limited GPU budget | ✗ | ✓ Good | ✓ Best |
| Quality-critical | ✓ Best | Good | Acceptable |

3. GPU memory estimation:

| Method | Formula (approx) |
|--------|-----------------|
| Full FT (FP16) | params × 2B × 4 (model + optimizer + gradients) |
| Full FT (BF16) | params × 2B × 3 |
| LoRA (FP16) | params × 2B × 1.1 (model frozen + small adapters) |
| QLoRA (4-bit) | params × 0.5B × 1.1 (quantized model + adapters) |

**Examples:**
| Model | Method | Min GPU Memory | Recommended Setup |
|-------|--------|---------------|-------------------|
| 7B | Full FT | 56 GB | 2x A100-40GB or 1x A100-80GB |
| 7B | LoRA | 16 GB | 1x A100-40GB or 1x L40S |
| 7B | QLoRA | 8 GB | 1x T4-16GB |
| 13B | LoRA | 28 GB | 1x A100-40GB |
| 70B | QLoRA | 40 GB | 1x A100-80GB |
| 70B | LoRA | 150 GB | 4x A100-40GB (distributed) |

### Phase 3: Hardware Matching

4. Call `mcp_openshift_nodes_top` to check available GPUs:
   - Identify GPU types and count
   - Check current utilization
5. Call `mcp_rhoai_get_cluster_resources` for resource overview:
   - Available GPUs by type
   - Queue capacity (if Kueue enabled)
6. If distributed training needed:
   - Determine parallelism strategy:
     - Data Parallel (DDP): same model on multiple GPUs, split data
     - Model Parallel (FSDP/DeepSpeed): split model across GPUs
   - Calculate optimal world_size (number of GPUs)

### Phase 4: Generate Training Configuration

7. Generate the training job configuration:

**For Ray-based distributed training:**
```yaml
apiVersion: ray.io/v1
kind: RayJob
metadata:
  name: {training-job-name}
spec:
  entrypoint: "python train.py --model {model} --method {lora|full} ..."
  runtimeEnvYAML: |
    pip:
      - transformers
      - peft
      - datasets
      - accelerate
  rayClusterSpec:
    headGroupSpec:
      rayStartParams:
        dashboard-host: '0.0.0.0'
      template:
        spec:
          containers:
            - name: ray-head
              resources:
                limits:
                  cpu: "4"
                  memory: "16Gi"
    workerGroupSpecs:
      - replicas: {gpu_count}
        groupName: gpu-workers
        rayStartParams: {}
        template:
          spec:
            containers:
              - name: ray-worker
                resources:
                  limits:
                    nvidia.com/gpu: 1
                    memory: "{mem_per_gpu}Gi"
                    cpu: "{cpu_per_gpu}"
```

**For single-GPU LoRA (via workbench or job):**
```python
# Training script outline
from peft import LoraConfig, get_peft_model
from transformers import AutoModelForCausalLM, TrainingArguments

lora_config = LoraConfig(
    r=16,  # rank
    lora_alpha=32,
    target_modules=["q_proj", "v_proj", "k_proj", "o_proj"],
    lora_dropout=0.05,
    task_type="CAUSAL_LM"
)
training_args = TrainingArguments(
    per_device_train_batch_size={batch_size},
    gradient_accumulation_steps={grad_accum},
    num_train_epochs={epochs},
    learning_rate={lr},
    fp16=True,
    output_dir="./output"
)
```

### Phase 5: Timeline and Cost Estimation

8. Estimate training time:
   - Tokens per second per GPU (rough): 3000-5000 for 7B LoRA on A100
   - Total tokens = dataset_samples × avg_tokens_per_sample × epochs
   - Estimated hours = total_tokens / (tokens_per_sec × num_gpus)

9. Estimate cost:
   - GPU-hours = num_gpus × estimated_hours
   - If cloud: GPU-hour rate × GPU-hours

## Output Format

```
# Training Plan: {model_name}

## Method Selection
- **Recommended**: {method} ({reasoning})
- Base model: {model} ({params}B parameters)
- Dataset: {samples} samples ({tokens} tokens)

## Resource Requirements
| Resource | Minimum | Recommended | Optimal |
|----------|---------|-------------|---------|
| GPUs | {min} | {rec} | {opt} |
| GPU Type | {type} | {type} | {type} |
| GPU Memory | {min_mem} | {rec_mem} | {opt_mem} |
| System RAM | {ram} | {ram} | {ram} |
| Storage | {disk} | {disk} | {disk} |

## Cluster Fit
- Available GPUs: {available} ({types})
- Queue wait estimate: {time}
- Can run now: {yes/no}

## Training Configuration
### Hyperparameters
| Parameter | Value | Reasoning |
|-----------|-------|-----------|
| Learning rate | {lr} | {reason} |
| Batch size | {bs} | {reason} |
| Grad accum steps | {gas} | Effective batch = {effective} |
| Epochs | {epochs} | {reason} |
| LoRA rank | {r} | {reason} |

### Infrastructure
- Parallelism: {strategy}
- World size: {gpus}
- Framework: {ray/pytorch/deepspeed}

## Timeline
- Estimated duration: {hours}h ({tokens} tokens at ~{tps} tok/s/gpu)
- Checkpointing: Every {interval}
- Expected completion: {estimate}

## Generated Config
```yaml
{job YAML or config}
```

## Next Steps
1. Prepare dataset in S3 (data connection required)
2. Create/verify workbench with GPU accelerator profile
3. Submit training job
4. Monitor with: `hermes ask "Training job progress for {job_name}"`
```

## Domain Knowledge

- RHOAI supports Ray for distributed training via the Ray component in DSC
- Kueue queues training jobs — they may wait if GPU quota is full
- LoRA adapters are small (10-100MB) and can be hot-swapped in vLLM serving
- QLoRA with bitsandbytes requires CUDA GPU — won't work on CPU
- Gradient checkpointing trades compute for memory — enables larger models on smaller GPUs
- DeepSpeed ZeRO-3 allows training models that don't fit in single GPU memory
- Always use BF16 on A100/H100 — it has hardware support for brain-float
- Monitor GPU memory: if OOMKilled, reduce batch size or enable gradient checkpointing
