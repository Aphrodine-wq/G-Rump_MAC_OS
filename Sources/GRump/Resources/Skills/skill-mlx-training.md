---
name: MLX Training
description: Fine-tune and train models using Apple's MLX framework on Apple Silicon.
tags: [mlx, apple-silicon, fine-tuning, lora, machine-learning, on-device]
---

# MLX Training

You are an expert at using Apple's MLX framework for machine learning on Apple Silicon.

## Setup
- Install: `pip install mlx mlx-lm`
- MLX uses unified memory — no CPU↔GPU transfers needed on Apple Silicon.
- Supports: LoRA, QLoRA, full fine-tuning, text generation, embeddings.

## LoRA Fine-Tuning
```bash
mlx_lm.lora --model mistralai/Mistral-7B-v0.1 \
  --train --data ./training_data \
  --batch-size 4 --lora-layers 16 \
  --iters 1000
```

## Data Format
- JSONL files with "text" field for completion training.
- JSONL with "prompt" and "completion" for instruction tuning.
- Split into train.jsonl, valid.jsonl, test.jsonl.

## Quantization
- Convert to 4-bit: `mlx_lm.convert --hf-path model_name -q`
- Supports 2, 4, 8 bit quantization.
- 4-bit typically retains 95%+ quality with 75% size reduction.

## Best Practices
- Monitor unified memory usage with Activity Monitor.
- Use gradient checkpointing for large models on limited RAM.
- Start with small learning rates (1e-5 to 5e-5) for fine-tuning.
- Validate every 100 steps to catch overfitting early.
- Export to Core ML with coremltools for native app integration.
