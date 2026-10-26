#!/bin/bash
set -Eeuo pipefail
echo 'A1(AI) : https://www.youtube.com/@A01demort'
cd /workspace/ComfyUI
python -B /opt/scail-runtime-fix/bootstrap.py /workspace/A1/init_or_check_nodes.sh
echo '의존성 확인 완료 - 서비스 시작'

pids=()
cleanup() {
    trap - EXIT TERM INT
    kill "${pids[@]}" 2>/dev/null || true
    wait "${pids[@]}" 2>/dev/null || true
}
trap cleanup EXIT
trap 'exit 143' TERM
trap 'exit 130' INT

jupyter_args=(--ip=0.0.0.0 --port=8888 --allow-root --ServerApp.root_dir=/workspace)
if [ -n "${JUPYTER_PASSWORD:-${JUPYTER_TOKEN:-}}" ]; then
    jupyter_args+=("--ServerApp.token=${JUPYTER_PASSWORD:-$JUPYTER_TOKEN}")
fi
jupyter lab "${jupyter_args[@]}" &
pids+=("$!")
python -u /workspace/ComfyUI/main.py --listen 0.0.0.0 --port=8188 --front-end-version Comfy-Org/ComfyUI_frontend@1.37.2 &
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
