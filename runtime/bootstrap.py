import argparse
import ctypes.util
import importlib.metadata as metadata
import io
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys
import tempfile
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parent
CORE = Path('/workspace/ComfyUI')
ENV = os.environ.copy()
ENV['PIP_CONSTRAINT'] = str(ROOT / 'constraints.txt')
ENV['UV_CONSTRAINT'] = str(ROOT / 'constraints.txt')
BUILD = False


def run(args):
    subprocess.run(args, env=ENV, check=True)


def required_versions():
    return [tuple(line.split('==', 1)) for line in (ROOT / 'required.txt').read_text().splitlines() if line]


def torch_index():
    return 'https://download.pytorch.org/whl/' + dict(required_versions())['torch'].split('+', 1)[1]


def mismatches():
    result = []
    for name, expected in required_versions():
        try:
            current = metadata.version(name)
        except metadata.PackageNotFoundError:
            current = None
        if current != expected:
            result.append((name, current, expected))
    return result


def patch_file(path, old, new):
    before = path.read_bytes()
    if new in before:
        return
    if before.count(old) != 1:
        raise RuntimeError('Unexpected import repair target: ' + str(path))
    after = before.replace(old, new)
    assert [line for line in before.splitlines() if line.lstrip().startswith(b'#')] == [line for line in after.splitlines() if line.lstrip().startswith(b'#')]
    path.write_bytes(after)


def prepare_impact_requirements(before):
    source = next(line for line in (ROOT / 'constraints.txt').read_text().splitlines() if line.startswith('SAM-2 @ '))
    pinned = source.split(' @ ', 1)[1].encode()
    lines = before.splitlines(True)
    if any(line.strip() == pinned for line in lines):
        return before
    matches = [index for index, line in enumerate(lines) if line.strip() == b'git+https://github.com/facebookresearch/sam2']
    if len(matches) != 1:
        raise RuntimeError('Expected original Impact-Pack SAM-2 requirement')
    lines[matches[0]] = lines[matches[0]].replace(b'git+https://github.com/facebookresearch/sam2', pinned, 1)
    after = b''.join(lines)
    assert [line for line in before.splitlines() if line.lstrip().startswith(b'#')] == [line for line in after.splitlines() if line.lstrip().startswith(b'#')]
    return after


def verify_nodes():
    source = (ROOT / 'init_or_check_nodes.sh').read_bytes()
    names = re.findall(rb'^git clone https://github.com/[^/]+/([^ ]+)\.git', source, re.MULTILINE)
    if len(names) != 20:
        raise RuntimeError('Expected 20 original node repositories')
    for name in names:
        node = CORE / 'custom_nodes' / name.decode()
        if not (node / '.git').is_dir():
            raise RuntimeError('Original node repository missing: ' + name.decode())
        if (node / 'requirements.txt').is_file() and not (node / '.installed').is_file():
            raise RuntimeError('Node requirements installation did not finish: ' + name.decode())
    print('SCAIL custom node check passed: 20 original repositories and requirement markers', flush=True)


def ensure_frontend():
    target = CORE / 'web_custom_versions/Comfy-Org_ComfyUI_frontend/1.37.2'
    if (target / 'index.html').is_file():
        return
    request = urllib.request.Request('https://github.com/Comfy-Org/ComfyUI_frontend/releases/download/v1.37.2/dist.zip', headers={'User-Agent': 'SCAIL-runtime'})
    with urllib.request.urlopen(request, timeout=120) as response:
        payload = response.read()
    with zipfile.ZipFile(io.BytesIO(payload)) as archive:
        if 'index.html' not in archive.namelist():
            raise RuntimeError('Frontend archive has no index.html')
        for member in archive.infolist():
            destination = (target / member.filename).resolve()
            if not destination.is_relative_to(target.resolve()):
                raise RuntimeError('Unexpected frontend archive path')
        target.mkdir(parents=True, exist_ok=True)
        archive.extractall(target)


def verify_runtime():
    pending = mismatches()
    if pending:
        torch_names = {'torch', 'torchvision', 'torchaudio'}
        if any(name in torch_names for name, _, _ in pending):
            versions = dict(required_versions())
            run([sys.executable, '-m', 'pip', 'install', *[name + '==' + versions[name] for name in ('torch', 'torchvision', 'torchaudio')], '--index-url', torch_index()])
        run([sys.executable, '-m', 'pip', 'install', '-r', str(ROOT / 'required.txt'), '--extra-index-url', torch_index()])
    verify_nodes()
    if not ctypes.util.find_library('zbar'):
        run(['apt-get', 'update', '-qq'])
        run(['apt-get', 'install', '-y', 'libzbar0'])
    site = Path(metadata.distribution('basicsr').locate_file(''))
    patch_file(site / 'basicsr/data/degradations.py',
               b'from torchvision.transforms.functional_tensor import rgb_to_grayscale',
               b'from torchvision.transforms.functional import rgb_to_grayscale')
    patch_file(CORE / 'app/frontend_management.py',
               b'        if version.startswith("v"):',
               b'        if version.startswith("v") or re.fullmatch(r"\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?", version):')
    probe = subprocess.run([sys.executable, '-B', '-c', 'import onnxruntime as o; assert o.__version__ == "1.20.0"; assert "CUDAExecutionProvider" in o.get_available_providers()'], env=ENV, capture_output=True)
    if probe.returncode:
        run([sys.executable, '-m', 'pip', 'install', '--force-reinstall', '--no-deps', 'onnxruntime-gpu==1.20.0'])
    ensure_frontend()
    run([sys.executable, '-m', 'pip', 'check'])
    pending = mismatches()
    assert not pending, pending
    imports = '''import torch,torchvision,torchaudio,numpy,cv2,onnx,onnxruntime,insightface,basicsr,facexlib,gfpgan,realesrgan
import peft,accelerate,alembic,sqlalchemy,comfyui_workflow_templates,comfyui_embedded_docs
import skimage,scipy,numba,timm,av,torchsde,pymatting,albumentations,aiofiles,ypy_websocket,huggingface_hub,tokenizers,nio,kornia,spandrel,xformers,sageattention
from pyzbar.pyzbar import decode
from transformers import BlipProcessor,BlipForConditionalGeneration,BlipForQuestionAnswering,pipeline,AutoModelForSeq2SeqLM,AutoTokenizer,AutoModel,AutoProcessor,StoppingCriteria,StoppingCriteriaList,AutoModelForCausalLM
from diffusers import FlowMatchEulerDiscreteScheduler
from sam2.build_sam import build_sam2
assert numpy.__version__ == "1.26.4"
assert cv2.__version__ == "4.11.0"
assert "CUDAExecutionProvider" in onnxruntime.get_available_providers()
'''
    imports += 'assert torch.__version__ == ' + repr(dict(required_versions())['torch']) + '\n'
    if not BUILD:
        imports += 'assert (torch.ones(1,device="cuda")+1).item() == 2\n'
    imports += 'print("SCAIL dependency check passed: Torch " + torch.__version__ + " / NumPy 1.26.4 / ONNX GPU 1.20.0")\n'
    run([sys.executable, '-B', '-c', imports])


def prepare_init(before, build=False):
    if before.count(b'onnxruntime-gpu==1.18.0') != 1:
        raise RuntimeError('Expected v1.0.23 init script')
    after = before.replace(b'onnxruntime-gpu==1.18.0', b'onnxruntime-gpu==1.20.0')
    lines = after.splitlines(True)
    invalid = [line for line in lines if line.lstrip().startswith(b'pip install facelib==0.2.2')]
    if len(invalid) != 1:
        raise RuntimeError('Expected v1.0.23 facelib command')
    after = after.replace(invalid[0], b'\n', 1)
    versions = dict(required_versions())
    after = after.replace(b'torch==2.5.1 torchvision==0.20.1 torchaudio==2.5.1',
        ' '.join(name + '==' + versions[name] for name in ('torch', 'torchvision', 'torchaudio')).encode())
    after = after.replace(b'xformers==0.0.29.post1', ('xformers==' + versions['xformers']).encode())
    after = after.replace(b'https://download.pytorch.org/whl/cu124', torch_index().encode())
    clone_lines = [line for line in after.splitlines(True) if line.startswith(b'git clone https://github.com/')]
    if len(clone_lines) != 20:
        raise RuntimeError('Expected 20 original custom node repositories')
    for line in clone_lines:
        repo = re.search(rb'git clone https://github.com/[^/]+/([^ ]+)\.git', line).group(1)
        # Fetch only the blobs used by the original pinned checkout.
        # The source script and every original checkout revision remain intact.
        efficient_clone = line.replace(b'git clone https://', b'git clone --filter=blob:none --no-checkout https://', 1)
        replacement = b'if [ ! -d "' + repo + b'/.git" ]; then\n' + efficient_clone + b'fi\n'
        after = after.replace(line, replacement, 1)
    gate = b'if [ ! -f "/tmp/.a1_sys_pkg_checked" ]; then'
    if after.count(gate) != 1:
        raise RuntimeError('Expected original package marker')
    command = (shlex.quote(sys.executable) + ' -B ' + shlex.quote(str(ROOT / 'bootstrap.py'))).encode()
    after = after.replace(gate, gate[:-6] + b' && ! ' + command + b' --packages-ready; then', 1)
    wan_gate = b'if [ -d "ComfyUI-WanVideoWrapper" ] && [ ! -f "/tmp/.wan_wrapper_checked" ]; then'
    if after.count(wan_gate) != 1:
        raise RuntimeError('Expected original WanVideoWrapper package marker')
    after = after.replace(wan_gate,
        b'if [ -d "ComfyUI-WanVideoWrapper" ] && [ ! -f "/tmp/.wan_wrapper_checked" ]'
        b' && { [ ! -f "ComfyUI-WanVideoWrapper/.installed" ] || ! ' + command + b' --packages-ready; }; then', 1)
    install = b'    if pip install -r "$req_file"; then'
    if after.count(install) != 1:
        raise RuntimeError('Expected original node requirements installation')
    after = after.replace(install,
        b'    if [ "$d" = "ComfyUI-Impact-Pack/" ]; then\n'
        b'      scail_pip_command=(' + command + b' --install-impact-requirements "$req_file")\n'
        b'    else\n'
        b'      scail_pip_command=(pip install -r "$req_file")\n'
        b'    fi\n'
        b'    if "${scail_pip_command[@]}"; then', 1)
    anchor = 'echo "\u2705 \ubaa8\ub4e0 \ucee4\uc2a4\ud140 \ub178\ub4dc \uc758\uc874\uc131 \ubcf5\uad6c \uc644\ub8cc"'.encode()
    if after.count(anchor) != 1:
        raise RuntimeError('Expected original completion message')
    verify = command + b' --verify' + (b' --build' if build else b'') + b' || exit 1\n\n'
    after = after.replace(anchor, verify + anchor, 1)
    assert [line for line in before.splitlines() if line.lstrip().startswith(b'#')] == [line for line in after.splitlines() if line.lstrip().startswith(b'#')]
    return after


def main():
    global BUILD
    parser = argparse.ArgumentParser()
    parser.add_argument('--build', action='store_true')
    parser.add_argument('--verify', action='store_true')
    parser.add_argument('--packages-ready', action='store_true')
    parser.add_argument('--validate-source', action='store_true')
    parser.add_argument('--install-impact-requirements')
    parser.add_argument('init_script', nargs='?', default='/workspace/A1/init_or_check_nodes.sh')
    args = parser.parse_args()
    BUILD = args.build
    if args.packages_ready:
        return int(bool(mismatches()))
    if args.install_impact_requirements:
        original = Path(args.install_impact_requirements).resolve()
        before = original.read_bytes()
        prepared = prepare_impact_requirements(before)
        with tempfile.TemporaryDirectory(prefix='scail-impact-') as folder:
            temporary = Path(folder) / 'requirements.txt'
            temporary.write_bytes(prepared)
            run([sys.executable, '-m', 'pip', 'install', '-r', str(temporary), '--extra-index-url', torch_index()])
        assert original.read_bytes() == before, 'Original node requirements changed'
        return 0
    if args.verify:
        verify_runtime()
        return 0
    original = Path(args.init_script)
    before = original.read_bytes()
    template = ROOT / 'init_or_check_nodes.sh'
    prepared = prepare_init(template.read_bytes() if template.is_file() else before, build=BUILD)
    with tempfile.TemporaryDirectory(prefix='scail-init-') as folder:
        temporary = Path(folder) / 'init_or_check_nodes.sh'
        temporary.write_bytes(prepared)
        run(['bash', '-n', str(temporary)])
        if args.validate_source:
            print('Original init comments and completion messages preserved')
        else:
            run(['bash', str(temporary)])
    assert original.read_bytes() == before, 'Original init script changed during initialization'
    return 0


if __name__ == '__main__':
    sys.exit(main())
