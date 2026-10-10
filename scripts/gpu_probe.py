"""Exercise CUDA kernels and an ONNX CUDA session; provider listing alone is insufficient."""
import numpy as np
import torch
import torch.nn.functional as F
from onnx import TensorProto, helper
import onnxruntime as ort

if not torch.cuda.is_available():
    raise SystemExit('CUDA unavailable. Select a CUDA-capable RunPod GPU/driver.')
q = torch.randn(1, 2, 8, 32, device='cuda', dtype=torch.float16)
result = F.scaled_dot_product_attention(q, q, q)
assert torch.isfinite(result).all().item(), 'CUDA SDPA produced non-finite values'
graph = helper.make_graph([helper.make_node('Add', ['x', 'x'], ['y'])], 'cuda_probe',
                          [helper.make_tensor_value_info('x', TensorProto.FLOAT, [2])],
                          [helper.make_tensor_value_info('y', TensorProto.FLOAT, [2])])
model = helper.make_model(graph, opset_imports=[helper.make_opsetid('', 13)])
model.ir_version = 9
session = ort.InferenceSession(model.SerializeToString(), providers=['CUDAExecutionProvider'])
if session.get_providers()[0] != 'CUDAExecutionProvider':
    raise SystemExit('ONNX fell back to CPU. CUDA/cuDNN libraries are incompatible.')
np.testing.assert_array_equal(session.run(None, {'x': np.array([1, 2], dtype=np.float32)})[0], [2, 4])
torch.cuda.synchronize()
print(f'CUDA/SDPA/ONNX probe passed: {torch.cuda.get_device_name(0)} / torch {torch.__version__}')
