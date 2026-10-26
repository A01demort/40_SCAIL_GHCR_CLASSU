#!/bin/bash
set -Eeuo pipefail
echo 'A1(AI) : https://www.youtube.com/@A01demort'
runtime=/opt/scail-runtime-fix
comfy_extra_args=()
capabilities=$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null || true)
while read -r capability; do
    if [[ "$capability" =~ ^[[:space:]]*([0-9]+)\. ]] && [ "${BASH_REMATCH[1]}" -ge 12 ]; then
        runtime=/opt/scail-cu128/runtime
        export PATH="/opt/scail-cu128/venv/bin:$PATH"
        export TRITON_CACHE_DIR=/workspace/.cache/triton-cu128
        export TORCHINDUCTOR_CACHE_DIR=/workspace/.cache/torchinductor-cu128
        gpu_libs=$(python -c 'import site,glob,os; print(":".join(p for s in site.getsitepackages() if s.startswith("/opt/scail-cu128/") for p in [s+"/torch/lib"]+glob.glob(s+"/nvidia/*/lib") if os.path.isdir(p)))')
        export LD_LIBRARY_PATH="$gpu_libs:${LD_LIBRARY_PATH:-}"
        comfy_extra_args+=(--use-pytorch-cross-attention)
        break
    fi
done <<< "$capabilities"
export PIP_CONSTRAINT="$runtime/constraints.txt"
export UV_CONSTRAINT="$PIP_CONSTRAINT"
echo "[SCAIL] 고정 GPU 환경: $runtime"
cd /workspace/ComfyUI

pids=()
cleanup() {
    trap - EXIT TERM INT
    kill "${pids[@]}" 2>/dev/null || true
    wait "${pids[@]}" 2>/dev/null || true
}
trap cleanup EXIT
trap 'exit 143' TERM
trap 'exit 130' INT

jupyter_args=(--ip=0.0.0.0 --port=8888 --allow-root --ServerApp.root_dir=/workspace --app-dir=/usr/local/share/jupyter/lab)
if [ -n "${JUPYTER_PASSWORD:-${JUPYTER_TOKEN:-}}" ]; then
    jupyter_args+=("--ServerApp.token=${JUPYTER_PASSWORD:-$JUPYTER_TOKEN}")
fi
python -m jupyterlab "${jupyter_args[@]}" &
pids+=("$!")
echo '[SCAIL] JupyterLab 시작 요청 완료'

while ! driver_status=$(python -c 'import ctypes,sys; r=ctypes.CDLL("libcuda.so.1").cuInit(0); print(r); sys.exit(0 if r == 0 else 1)' 2>&1); do
    recovery=$(nvidia-smi -q 2>/dev/null | grep 'GPU Recovery Action' | head -n 1 || true)
    echo "[SCAIL] CUDA 초기화 대기: $driver_status / $recovery"
    echo '[SCAIL] Recovery Action=Reboot이면 호스트 재부팅 또는 정상 호스트의 Pod가 필요합니다. 30초 후 재확인합니다.'
    kill -0 "${pids[0]}" 2>/dev/null || exit 1
    sleep 30
done
echo '[SCAIL] GPU 초기화 완료 - 원래 설치 단계 확인 시작'
if ! python -B "$runtime/bootstrap.py" /workspace/A1/init_or_check_nodes.sh; then
    echo '[SCAIL] 의존성 확인 실패. JupyterLab 터미널에서 확인할 수 있습니다.'
    wait "${pids[0]}"
    exit 1
fi
echo '의존성 확인 완료 - 서비스 시작'
python -u /workspace/ComfyUI/main.py --listen 0.0.0.0 --port=8188 --front-end-version Comfy-Org/ComfyUI_frontend@1.37.2 "${comfy_extra_args[@]}" &
pids+=("$!")
bash /workspace/A1/startup_banner.sh &
banner_pid=$!

# Ubuntu 20.04's Bash 5.0 does not restrict wait -n to the supplied PIDs.
# Check the two required services explicitly so the banner may finish normally.
while kill -0 "${pids[0]}" 2>/dev/null && kill -0 "${pids[1]}" 2>/dev/null; do
    sleep 2
done
kill "$banner_pid" 2>/dev/null || true
echo 'A required SCAIL service exited.'
exit 1
