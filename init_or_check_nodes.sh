#!/usr/bin/env bash
# Install once on the volume, then verify and reuse the locked environment.
set -Eeuo pipefail
mkdir -p /workspace/.scail /workspace/scail-logs
(
  flock -x 9
  /usr/local/bin/python /opt/scail/scripts/bootstrap.py
) 9>/workspace/.scail/install.lock
export PATH="/workspace/.scail/current/venv/bin:$PATH"
export VIRTUAL_ENV=/workspace/.scail/current/venv
if [[ -e /opt/ComfyUI && ! -L /opt/ComfyUI ]]; then
  echo 'Unexpected /opt/ComfyUI directory; use the current image.' >&2
  exit 1
fi
ln -sfn /workspace/.scail/current/ComfyUI /opt/ComfyUI
python /opt/scail/scripts/integrity.py check
python /opt/scail/scripts/gpu_probe.py
python /opt/scail/scripts/models.py download --lock /opt/scail/locks/models-reactor.json

# 🎓 AI 교육 & 커뮤니티 안내 (기존 안내 유지)
echo -e "\n====🎓 AI 교육 & 커뮤니티 안내====\n"
echo "1. Youtube : https://www.youtube.com/@A01demort"
echo "2. 교육 문의 : https://a01demort.com"
echo "3. CLASSU 강의 : https://classu.co.kr/me/19375"
echo "4. Stable AI KOREA : https://cafe.naver.com/sdfkorea"
echo "5. 카카오톡 오픈채팅방 : https://open.kakao.com/o/gxvpv2Mf"
echo "6. CIVITAI : https://civitai.com/user/a01demort"
echo -e "\n==================================="
