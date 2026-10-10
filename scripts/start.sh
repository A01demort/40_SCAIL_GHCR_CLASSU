#!/usr/bin/env bash
set -Eeuo pipefail
export PYTHONPATH='' PYTHONNOUSERSITE=1
echo "Starting SCAIL v${SCAIL_RELEASE_VERSION:?Release version missing from image}"
mkdir -p /workspace/ComfyUI/{models,input,output,temp} /workspace/scail-user/default/workflows /workspace/scail-logs /workspace/A1
# 기존 A1 스크립트 네 개를 유지합니다. 변경된 기존 파일은 번호가 붙은 백업으로 보존합니다.
for helper in init_or_check_nodes.sh startup_banner.sh SCAIL_down_a1.sh Wan2.1_Vace_a1.sh; do
  if ! cmp -s "/opt/scail/$helper" "/workspace/A1/$helper"; then
    install -m 0755 --backup=numbered "/opt/scail/$helper" "/workspace/A1/$helper"
  fi
  chmod +x "/workspace/A1/$helper"
done
echo 'A1(AI) : https://www.youtube.com/@A01demort'
/workspace/A1/init_or_check_nodes.sh
export PATH="/workspace/.scail/current/venv/bin:$PATH"
export VIRTUAL_ENV=/workspace/.scail/current/venv
export PIP_NO_INDEX=1 PIP_REQUIRE_HASHES=1 UV_OFFLINE=true
export HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1
python /opt/scail/scripts/runtime_policy.py
echo '의존성 확인 완료 - 서비스 시작'
cd /opt/ComfyUI
comfy_pid='' jupyter_pid=''
cleanup() {
  [[ -z "$comfy_pid" ]] || kill "$comfy_pid" 2>/dev/null || true
  [[ -z "$jupyter_pid" ]] || kill "$jupyter_pid" 2>/dev/null || true
  wait 2>/dev/null || true
}
trap cleanup EXIT
trap 'exit 143' TERM
trap 'exit 130' INT
python -u main.py --listen 0.0.0.0 --port 8188 --disable-auto-launch \
  --input-directory /workspace/ComfyUI/input --output-directory /workspace/ComfyUI/output \
  --temp-directory /workspace/ComfyUI/temp --user-directory /workspace/scail-user \
  --database-url sqlite:////workspace/scail-user/comfyui.db \
  > /workspace/scail-logs/comfyui.log 2>&1 &
comfy_pid=$!
if ! /workspace/A1/startup_banner.sh; then
  cat /workspace/scail-logs/comfyui.log
  exit 1
fi
# Preserve the existing template's Jupyter authentication behavior.
jupyter lab --ip=0.0.0.0 --port=8888 --allow-root --no-browser \
  --ServerApp.root_dir=/workspace --ServerApp.token='' --ServerApp.password='' \
  > /workspace/scail-logs/jupyter.log 2>&1 &
jupyter_pid=$!
echo 'ComfyUI: :8188; Jupyter: :8888; logs: /workspace/scail-logs/'
set +e
wait -n "$comfy_pid" "$jupyter_pid"
status=$?
set -e
(( status != 0 )) || status=1
exit "$status"
