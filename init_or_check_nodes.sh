#!/bin/bash
# set -e 제거 (중간 실패로 전체 중단 방지)
# 목적: RunPod에서 ComfyUI/커스텀노드 설치를 최대한 복구형으로 진행

echo "🚀 RunPod 세션 의존성 복구 시작"

############################################
# ✅ 코어 파이썬 패키지 (ComfyUI 필수)
############################################
# 빠른 실행을 위한 세션별 설치 확인 (세션별 마커 사용)
if [ ! -f "/tmp/.a1_sys_pkg_checked" ]; then
  echo '🔧 코어 파이썬 패키지 설치'

  # [CRITICAL] 기존 버전 제거 (충돌 방지)
  pip install --no-cache-dir --upgrade pip
  pip uninstall -y torch torchvision torchaudio xformers onnxruntime onnxruntime-gpu numpy

  # [CRITICAL] RunPod CUDA 12.4 대응 고정 조합
  # - torch 2.5.1 + cu124
  # - xformers 0.0.29.post1
  pip install --no-cache-dir \
    torch==2.5.1 torchvision==0.20.1 torchaudio==2.5.1 \
    --index-url https://download.pytorch.org/whl/cu124 || echo '⚠️ Torch 재설치 실패'

  pip install --no-cache-dir \
    xformers==0.0.29.post1 \
    --index-url https://download.pytorch.org/whl/cu124 || echo '⚠️ xformers 설치 실패'

  # 필수 보조 패키지
  pip install --no-cache-dir torchsde av pydantic-settings || echo '⚠️ 초기 의존성 설치 실패'

  # [CRITICAL] ORT/Numpy 충돌 방지
  pip install --no-cache-dir --force-reinstall numpy==1.26.4 || echo '⚠️ numpy 고정 실패'

  echo '🔧 일반 파이썬 패키지 설치'
  pip install --no-cache-dir \
    GitPython onnx onnxruntime-gpu==1.16.3 opencv-python-headless tqdm requests \
    scikit-image piexif packaging transformers accelerate peft sentencepiece \
    protobuf scipy einops pandas matplotlib 'imageio[ffmpeg]' pyzbar pillow numba \
    gguf diffusers insightface dill taichi pyloudnorm || echo '⚠️ 일반 pip 설치 실패'

  pip install --no-cache-dir facelib==0.2.2 mtcnn==0.1.1 || echo '⚠️ facelib 실패'
  pip install --no-cache-dir facexlib basicsr gfpgan realesrgan || echo '⚠️ facexlib 실패'
  pip install --no-cache-dir timm || echo '⚠️ timm 실패'
  pip install --no-cache-dir ultralytics || echo '⚠️ ultralytics 실패'
  pip install --no-cache-dir ftfy || echo '⚠️ ftfy 실패'
  pip install --no-cache-dir bitsandbytes || echo '⚠️ bitsandbytes 설치 실패'
  pip install --no-cache-dir sageattention || echo '⚠️ sageattention 설치 실패'

  # 모든 시도가 끝나면 마커 생성
  touch "/tmp/.a1_sys_pkg_checked"
else
  echo "✅ 코어 패키지 설치 확인됨 (스킵)"
fi

############################################
# ✅ 커스텀 노드 설치 (실패해도 계속 진행)
############################################
echo '🧩 커스텀 노드 및 의존성 설치 시작'
mkdir -p /workspace/ComfyUI/custom_nodes

(
cd /workspace/ComfyUI/custom_nodes || exit 0

git clone https://github.com/ltdrdata/ComfyUI-Manager.git && (cd ComfyUI-Manager && git checkout fa009e7) || echo '⚠️ Manager 실패 (1)'
git clone https://github.com/pythongosssss/ComfyUI-Custom-Scripts.git && (cd ComfyUI-Custom-Scripts && git checkout f2838ed) || echo '⚠️ Scripts 실패 (2)'
git clone https://github.com/rgthree/rgthree-comfy.git && (cd rgthree-comfy && git checkout 8ff50e4) || echo '⚠️ rgthree 실패 (3)'
git clone https://github.com/WASasquatch/was-node-suite-comfyui.git && (cd was-node-suite-comfyui && git checkout ea935d1) || echo '⚠️ WAS 실패 (4)'
git clone https://github.com/kijai/ComfyUI-KJNodes.git && (cd ComfyUI-KJNodes && git checkout 7b13271) || echo '⚠️ KJNodes 실패 (5)'
git clone https://github.com/cubiq/ComfyUI_essentials.git && (cd ComfyUI_essentials && git checkout 9d9f4be) || echo '⚠️ Essentials 실패 (6)'
git clone https://github.com/Suzie1/ComfyUI_Comfyroll_CustomNodes.git && (cd ComfyUI_Comfyroll_CustomNodes && git checkout d78b780) || echo '⚠️ Comfyroll 실패 (7)'
git clone https://github.com/city96/ComfyUI-GGUF.git && (cd ComfyUI-GGUF && git checkout 795e451) || echo '⚠️ GGUF 실패 (8)'
git clone https://github.com/Gourieff/ComfyUI-ReActor.git && (cd ComfyUI-ReActor && git checkout d60458f212e8c7a496269bbd29ca7c6a3198239a) || echo '⚠️ ReActor 실패'
git clone https://github.com/yolain/ComfyUI-Easy-Use.git && (cd ComfyUI-Easy-Use && git checkout 23d9c36) || echo '⚠️ EasyUse 실패 (9)'
git clone https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git && (cd ComfyUI-VideoHelperSuite && git checkout 3234937) || echo '⚠️ VideoHelper 실패 (10)'
git clone https://github.com/kijai/ComfyUI-FramePackWrapper.git && (cd ComfyUI-FramePackWrapper && git checkout a7c4b70) || echo '⚠️ FramePackWrapper 실패 (11)'
git clone https://github.com/pollockjj/ComfyUI-MultiGPU.git && (cd ComfyUI-MultiGPU && git checkout 6e4181a7bb5e2ef147aa8e1d0845098a709306a4) || echo '⚠️ MultiGPU 실패'
git clone https://github.com/Fannovel16/comfyui_controlnet_aux.git && (cd comfyui_controlnet_aux && git checkout 59b027e088c1c8facf7258f6e392d16d204b4d27) || echo '⚠️ controlnet_aux 실패'
git clone https://github.com/chflame163/ComfyUI_LayerStyle.git && (cd ComfyUI_LayerStyle && git checkout 5840264) || echo '⚠️ LayerStyle 실패 (12)'
git clone https://github.com/Fannovel16/ComfyUI-Frame-Interpolation.git && (cd ComfyUI-Frame-Interpolation && git checkout a969c01dbccd9e5510641be04eb51fe93f6bfc3d) || echo '⚠️ Frame-Interpolation 실패'
git clone https://github.com/ltdrdata/ComfyUI-Impact-Pack.git && (cd ComfyUI-Impact-Pack && git checkout 51b7dcd) || echo '⚠️ Impact-Pack 실패 (13)'
git clone https://github.com/kijai/ComfyUI-WanVideoWrapper.git && (cd ComfyUI-WanVideoWrapper && git checkout 2ee9e2f) || echo '⚠️ WanVideoWrapper 실패 (14)'
git clone https://github.com/kijai/ComfyUI-WanAnimatePreprocess.git && (cd ComfyUI-WanAnimatePreprocess && git checkout 1a35b81) || echo '⚠️ WanAnimatePreprocess 실패 (15)'
git clone https://github.com/kijai/ComfyUI-SCAIL-Pose.git && (cd ComfyUI-SCAIL-Pose && git checkout 11402b1) || echo '⚠️ SCAIL-Pose 실패 (16)'
)

############################################
# ✅ 기존 init 구조 유지 (requirements 자동 설치)
############################################
cd /workspace/ComfyUI/custom_nodes || {
  echo "⚠️ custom_nodes 폴더 없음. ComfyUI 설치 확인 필요"
  exit 0
}

for d in */; do
  req_file="${d}requirements.txt"
  marker_file="${d}.installed"

  if [ -f "$req_file" ]; then
    if [ -f "$marker_file" ]; then
      echo "✅ $d 이미 설치됨, 건너뜀"
      continue
    fi

    echo "🔧 $d 의존성 설치 중..."
    if pip install -r "$req_file"; then
      touch "$marker_file"
    else
      echo "⚠️ $d 의존성 설치 실패 (무시하고 진행)"
    fi
  fi
done

############################################
# 🔒 핵심 CUDA 스택 재고정
# custom node requirements가 torch/numpy/onnxruntime를
# 다시 바꾸는 케이스 방지
############################################
echo "🔒 핵심 CUDA 스택 재고정"
pip install --no-cache-dir \
  torch==2.5.1 torchvision==0.20.1 torchaudio==2.5.1 \
  --index-url https://download.pytorch.org/whl/cu124 || echo '⚠️ Torch 재고정 실패'
pip install --no-cache-dir \
  xformers==0.0.29.post1 \
  --index-url https://download.pytorch.org/whl/cu124 || echo '⚠️ xformers 재고정 실패'
pip install --no-cache-dir --force-reinstall numpy==1.26.4 onnxruntime-gpu==1.16.3 || echo '⚠️ numpy/onnxruntime 재고정 실패'

############################################
# 🚩 WanVideoWrapper 마지막 의존성 복구 (세션별 마커)
############################################
if [ -d "ComfyUI-WanVideoWrapper" ] && [ ! -f "/tmp/.wan_wrapper_checked" ]; then
  echo "🚩 WanVideoWrapper 의존성 확인 및 복구..."
  cd ComfyUI-WanVideoWrapper
  if pip install -r requirements.txt 2>/dev/null; then
    echo "✅ WanVideoWrapper 의존성 설치 완료"
    touch "/tmp/.wan_wrapper_checked"
  else
    echo "⚠️ WanVideoWrapper 의존성 설치 실패 (재시도 필요)"
  fi
  cd ..
else
  echo "✅ WanVideoWrapper 의존성 확인됨 (스킵)"
fi

############################################
# ✅ 런타임 상태 확인 로그
############################################
python - <<'PY'
import torch
print('[A1] torch:', torch.__version__)
print('[A1] cuda available:', torch.cuda.is_available())
print('[A1] cudnn available:', torch.backends.cudnn.is_available())
print('[A1] cudnn version:', torch.backends.cudnn.version())
if torch.cuda.is_available():
    print('[A1] gpu:', torch.cuda.get_device_name(0))
PY

echo "✅ 모든 커스텀 노드 의존성 복구 완료"
echo "✅ 다음 단계로 넘어갑니다"

echo -e "\n====📢 AI 교육 & 커뮤니티 안내====\n"
echo -e "1. Youtube : https://www.youtube.com/@A01demort"
echo "2. 교육 문의 : https://a01demort.com"
echo "3. CLASSU 강의 : https://classu.co.kr/me/19375"
echo "4. Stable AI KOREA : https://cafe.naver.com/sdfkorea"
echo "5. 카카오톡 오픈채팅방: https://open.kakao.com/o/gxvpv2Mf"
echo "6. CIVITAI : https://civitai.com/user/a01demort"
echo -e "\n==================================="

# /workspace/A1/startup_banner.sh -> Dockerfile에서 병렬 실행
