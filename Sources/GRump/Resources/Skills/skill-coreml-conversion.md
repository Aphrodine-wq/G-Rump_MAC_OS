---
name: Core ML Conversion
description: Convert ML models from PyTorch, TensorFlow, and ONNX to Core ML format for on-device inference.
---

# Core ML Conversion

You are an expert at converting machine learning models to Apple's Core ML format.

## Conversion Tools
- Use coremltools (Python): `pip install coremltools`
- Supports: PyTorch, TensorFlow, TF-Lite, ONNX, scikit-learn, XGBoost, LibSVM

## PyTorch Conversion
```python
import coremltools as ct
import torch

model = MyModel()
model.eval()
traced = torch.jit.trace(model, example_input)
mlmodel = ct.convert(traced, inputs=[ct.TensorType(shape=example_input.shape)])
mlmodel.save("Model.mlpackage")
```

## Optimization
- Use ct.optimize.coreml.palettize for weight compression (2/4/6/8 bit).
- Use ct.optimize.coreml.prune for structured pruning.
- Use ct.precision.Float16 for FP16 quantization (halves model size).
- Use ct.optimize.torch for training-time quantization-aware optimization.

## Compute Units
- .all = Neural Engine + GPU + CPU (best performance, default)
- .cpuAndGPU = Skip Neural Engine (more predictable)
- .cpuOnly = Maximum compatibility

## Best Practices
- Always test converted model output against original for accuracy.
- Use MLComputeUnits.all for best Apple Silicon performance.
- Include metadata: author, description, license, version.
- Create manifest.json alongside .mlmodelc for G-Rump integration.
