"""Prepare the pinned RTX 50 runtime beside the original CUDA 12.4 runtime."""
from pathlib import Path
import re
import shutil


GPU_VERSIONS = {
    'torch': '2.7.1+cu128',
    'torchvision': '0.22.1+cu128',
    'torchaudio': '2.7.1+cu128',
    'xformers': '0.0.31.post1',
    'triton': '3.3.1',
    'sympy': '1.14.0',
    'nvidia-cublas-cu12': '12.8.3.14',
    'nvidia-cuda-cupti-cu12': '12.8.57',
    'nvidia-cuda-nvrtc-cu12': '12.8.61',
    'nvidia-cuda-runtime-cu12': '12.8.57',
    'nvidia-cudnn-cu12': '9.7.1.26',
    'nvidia-cufft-cu12': '11.3.3.41',
    'nvidia-cufile-cu12': '1.13.0.11',
    'nvidia-curand-cu12': '10.3.9.55',
    'nvidia-cusolver-cu12': '11.7.2.55',
    'nvidia-cusparse-cu12': '12.5.7.53',
    'nvidia-cusparselt-cu12': '0.6.3',
    'nvidia-nccl-cu12': '2.26.2',
    'nvidia-nvjitlink-cu12': '12.8.61',
    'nvidia-nvtx-cu12': '12.8.55',
}


def pinned_text(text):
    result, seen = [], set()
    for line in text.splitlines():
        name = re.split(r'\s*(?:==|@)', line, maxsplit=1)[0].lower().replace('_', '-')
        if name in GPU_VERSIONS:
            line = name + '==' + GPU_VERSIONS[name]
        seen.add(name)
        result.append(line)
    for name, version in GPU_VERSIONS.items():
        if name not in seen:
            result.append(name + '==' + version)
    return '\n'.join(result) + '\n'


def prepare(source, target):
    target.mkdir(parents=True, exist_ok=True)
    for name in ('bootstrap.py', 'init_or_check_nodes.sh'):
        shutil.copy2(source / name, target / name)
    for name in ('constraints.txt', 'required.txt'):
        (target / name).write_text(pinned_text((source / name).read_text()), encoding='utf-8')
    (target / 'gpu-packages.txt').write_text(
        '\n'.join(name + '==' + version for name, version in GPU_VERSIONS.items()) + '\n', encoding='utf-8')


if __name__ == '__main__':
    prepare(Path(__file__).resolve().parent, Path('/opt/scail-cu128/runtime'))
