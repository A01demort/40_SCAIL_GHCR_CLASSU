#!/bin/bash
set -o pipefail

# ====================================
# 🧳 Hugging Face API 키 (RunPod의 HF_TOKEN 환경 변수로 입력)
# ====================================
HUGGINGFACE_TOKEN="${HF_TOKEN:-}"
AUTH_ARGS=()
CURL_AUTH=()
if [[ -n "$HUGGINGFACE_TOKEN" ]]; then
  AUTH_ARGS=(--header="Authorization: Bearer $HUGGINGFACE_TOKEN")
  CURL_AUTH=(-H "Authorization: Bearer $HUGGINGFACE_TOKEN")
fi

# ====================================
# 🛠️ 사용자 설정값
# ====================================
MAX_PARALLEL=8

# ====================================
# 📂 파일 설정
# ====================================
INPUT_FILE="aria2_downloads.txt"
LOG_FILE="aria2_log.txt"
RESULT_FILE="aria2_result.txt"

# ====================================
# ⏱️ 타이머 시작
# ====================================
start_time=$(date +%s)

# ====================================
# 📦 Aria2 설치 확인
# ====================================
if ! command -v aria2c &> /dev/null; then
    echo "❌ 고정 이미지에 aria2c가 없습니다. 올바른 이미지를 다시 배포하세요."
    exit 1
else
    echo "✅ aria2c 설치 확인 완료."
fi

# ====================================
# 🔐 Hugging Face API 키 유효성 검사
# ====================================
TEST_URL="https://huggingface.co/api/whoami-v2"
if [[ -n "$HUGGINGFACE_TOKEN" ]]; then
    echo "🔍 Hugging Face API 키 유효성 검사 중..."
    test_response=$(curl -s -o /dev/null -w "%{http_code}" "${CURL_AUTH[@]}" "$TEST_URL")
    if [[ "$test_response" != "200" ]]; then
        echo "❌ Hugging Face 인증 실패 ($test_response). HF_TOKEN을 확인하세요."
        exit 1
    fi
    echo "✅ Hugging Face API 키 인증 성공"
else
    echo "ℹ️ HF_TOKEN 없이 공개 모델을 다운로드합니다."
fi

# ====================================
# 📌 다운로드 리스트 (9개 파일)
# ====================================
downloads=(

  # 1. Detection 모델 (YOLO) - yolov10m.onnx
  "https://huggingface.co/Wan-AI/Wan2.2-Animate-14B/resolve/cb93a225fbaf1ca100f54e79da8f994995b689b3/process_checkpoint/det/yolov10m.onnx|/workspace/ComfyUI/models/detection/yolov10m.onnx|89b526498a6d55f869a6ab52e3a2eb20ad45b3711c1f7de3dd9ca0b399dfd6d7"

  # 2. Pose 모델 (ViTPose WholeBody) - vitpose-l-wholebody.onnx
  "https://huggingface.co/JunkyByte/easy_ViTPose/resolve/e83805274e89428969355ec4afffcbc413e79188/onnx/wholebody/vitpose-l-wholebody.onnx|/workspace/ComfyUI/models/detection/vitpose-l-wholebody.onnx|89bdf6692d9224dbd5004dcef23a9ba2d54c5776212b359d5a5b5068ac14fd08"

  # 3. CLIP Vision 모델 - clip_vision_h.safetensors
  "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/123acf1cc74bccbb9bfff8ac1ee72edc08c2341d/split_files/clip_vision/clip_vision_h.safetensors|/workspace/ComfyUI/models/clip_vision/clip_vision_h.safetensors|64a7ef761bfccbadbaa3da77366aac4185a6c58fa5de5f589b42a65bcc21f161"

  # 4. LoRA 모델 1 - Wan2.1_CausVid_14B_lora_rank32_v2
  "https://huggingface.co/Kijai/WanVideo_comfy/resolve/8260d429d19fd7a72304cad059160b95d843913f/Wan21_CausVid_14B_T2V_lora_rank32_v2.safetensors|/workspace/ComfyUI/models/loras/Wan21_CausVid_14B_T2V_lora_rank32_v2.safetensors|3d6853cb7e7e9d6d35fb6c7163a85dab98e6c91d1341e8a3cf0bfb4e66dd68cc"

  # 5. LoRA 모델 2 (Lightx2v I2V) - lightx2v_I2V_14B_480p_cfg_step_distill_rank32_bf16.safetensors
  "https://huggingface.co/Kijai/WanVideo_comfy/resolve/8260d429d19fd7a72304cad059160b95d843913f/Lightx2v/lightx2v_I2V_14B_480p_cfg_step_distill_rank32_bf16.safetensors|/workspace/ComfyUI/models/loras/lightx2v_I2V_14B_480p_cfg_step_distill_rank32_bf16.safetensors|f501375c1a4e34533fa1c08360059f8f849ebddd829ff5853e551c3fea991368"

  # 6. Diffusion 모델 (SCAIL Preview GGUF) - Wan21-14B-SCAIL-preview_comfy-Q5_K_M.gguf
  "https://huggingface.co/vantagewithai/SCAIL-Preview-GGUF/resolve/f94f521f007df8701f7f2d5e53f3fa424050b764/Wan21-14B-SCAIL-preview_comfy-Q5_K_M.gguf|/workspace/ComfyUI/models/diffusion_models/Wan21-14B-SCAIL-preview_comfy-Q5_K_M.gguf|8da8179e4ce3564ff5ffa2861cec45135a0758bb9aed88f7582fe318d5e04424"

  # 7. VAE 모델 - Wan_2.1_vae
  "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/123acf1cc74bccbb9bfff8ac1ee72edc08c2341d/split_files/vae/wan_2.1_vae.safetensors|/workspace/ComfyUI/models/vae/wan_2.1_vae.safetensors|2fc39d31359a4b0a64f55876d8ff7fa8d780956ae2cb13463b0223e15148976b"

  # 8. Text Encoder 모델 (UMT5 XXL) - umt5-xxl-enc-fp8_e4m3fn.safetensors
  "https://huggingface.co/Kijai/WanVideo_comfy/resolve/8260d429d19fd7a72304cad059160b95d843913f/umt5-xxl-enc-fp8_e4m3fn.safetensors|/workspace/ComfyUI/models/text_encoders/umt5-xxl-enc-fp8_e4m3fn.safetensors|3fe5173588270c22505d4f9158bb1644b78331b8614206a97e92760b960c9ffa"

  # 9. NLF 모델 (Multi) - nlf_l_multi_0.3.2.torchscript
  "https://huggingface.co/spaces/yanboding/MTVCrafter/resolve/9d9257a85413a16e99ce252c5794ca09908dc0ba/nlf_l_multi_0.3.2.torchscript|/workspace/ComfyUI/models/nlf/nlf_l_multi_0.3.2.torchscript|52bee28edb6ea9148691331df87cfc238d7e3d9134dc60104a5aaed282a9ddad"




# Q8모델 필요할경우 주석 해제 후 사용
# 6. Diffusion 모델 (SCAIL Preview GGUF) - Wan21-14B-SCAIL-preview_comfy-Q8_0.gguf
# "https://huggingface.co/vantagewithai/SCAIL-Preview-GGUF/resolve/f94f521f007df8701f7f2d5e53f3fa424050b764/Wan21-14B-SCAIL-preview_comfy-Q8_0.gguf|/workspace/ComfyUI/models/diffusion_models/Wan21-14B-SCAIL-preview_comfy-Q8_0.gguf|2e4eeb9c0ba1c1c2192d94b04e80f88f0e938a2c453e8a0728597f73438b2162"


)

# ====================================
# 🧹 초기화
# ====================================
rm -f "$INPUT_FILE" "$LOG_FILE" "$RESULT_FILE"

# ====================================
# 📋 리스트 생성
# ====================================
for item in "${downloads[@]}"; do
  IFS="|" read -r url path checksum <<< "$item"
  if [[ -f "$path" && ! -f "$path.aria2" ]] && printf '%s  %s\n' "$checksum" "$path" | sha256sum -c - >/dev/null 2>&1; then
    echo "[완료] 이미 존재: $path" | tee -a "$RESULT_FILE"
  else
    if [[ -e "$path" ]]; then
      echo "[확인 필요] 기존 파일의 해시 또는 다운로드 상태가 다릅니다: $path" | tee -a "$RESULT_FILE"
      continue
    fi
    mkdir -p "$(dirname "$path")"
    echo "$url" >> "$INPUT_FILE"
    echo "  dir=$(dirname "$path")" >> "$INPUT_FILE"
    echo "  out=$(basename "$path")" >> "$INPUT_FILE"
    echo "  checksum=sha-256=$checksum" >> "$INPUT_FILE"
  fi
done

# ====================================
# 🚀 다운로드 시작
# ====================================
if [ -s "$INPUT_FILE" ]; then
  echo -e "\n🚀 다운로드 시작...\n"
  aria2c -x 8 -j "$MAX_PARALLEL" -i "$INPUT_FILE" --auto-file-renaming=false --allow-overwrite=false \
         --console-log-level=notice --summary-interval=1 \
         "${AUTH_ARGS[@]}" \
         | tee -a "$LOG_FILE"
else
  echo "📂 다운로드할 항목이 없습니다."
fi

# ====================================
# ✅ 결과 반영
# ====================================
total=${#downloads[@]}
success=0
failures=()

for item in "${downloads[@]}"; do
  IFS="|" read -r url path checksum <<< "$item"
  if [[ -f "$path" && ! -f "$path.aria2" ]] && printf '%s  %s\n' "$checksum" "$path" | sha256sum -c - >/dev/null 2>&1; then
    echo "[완료] $path" | tee -a "$RESULT_FILE"
    ((success++))
  else
    echo "[실패] $path" | tee -a "$RESULT_FILE"
    failures+=("$path")
  fi
done

# ====================================
# ⏱️ 소요 시간
# ====================================
end_time=$(date +%s)
duration=$((end_time - start_time))
minutes=$((duration / 60))
seconds=$((duration % 60))

echo -e "\n🕒 총 소요 시간: ${minutes}분 ${seconds}초\n" | tee -a "$RESULT_FILE"

# ====================================
# 📊 요약
# ====================================
if [ "$success" -eq "$total" ]; then
  echo "✅ $success/$total 모든 파일 정상!" | tee -a "$RESULT_FILE"
else
  echo "❌ $success/$total 완료, ${#failures[@]} 실패" | tee -a "$RESULT_FILE"
  echo "🔹 실패 파일 목록:" | tee -a "$RESULT_FILE"
  for fail in "${failures[@]}"; do
    echo " - $fail" | tee -a "$RESULT_FILE"
  done
fi

# ====================================
# ❌ 손상/중단 파일 검사 및 재시도
# ====================================
echo -e "\n🔍 다중 실패(또는 중단) 파일 검사..."
broken_files=()

for item in "${downloads[@]}"; do
  IFS="|" read -r url path checksum <<< "$item"
  if ! ( [[ -f "$path" && ! -f "$path.aria2" ]] && printf '%s  %s\n' "$checksum" "$path" | sha256sum -c - >/dev/null 2>&1 ); then
    broken_files+=("$path")
  fi
done

if [ "${#broken_files[@]}" -gt 0 ]; then
  echo -e "\n🚨 ${#broken_files[@]}개의 중단/잘못된 파일 발견됨:"
  for bf in "${broken_files[@]}"; do
    echo " - $bf"
  done

  echo -e "\n❓ 자동 삭제 후 재다운로드 하시겠습니까? (Y/N): \c"
  read -r confirm_retry

  if [[ "$confirm_retry" == "Y" || "$confirm_retry" == "y" ]]; then
    echo "🗑️ 삭제 중..."
    for bf in "${broken_files[@]}"; do
      rm -f "$bf" "$bf.aria2"
      echo "삭제됨: $bf"
    done
    echo "♻️ 다시 실행합니다..."
    bash "$0"
    exit $?
  else
    echo "⛔ 수동 처리 위해 종료합니다."
    exit 1
  fi
else
  echo "✅ 모든 파일이 정상적으로 다운되었습니다. (All good)"
   # ====================================
  # 🎓 AI 교육 & 커뮤니티 안내 (Community & EDU)
  # ====================================
  echo -e "\n====🎓 AI 교육 & 커뮤니티 안내====\n"
  echo -e "1. Youtube : https://www.youtube.com/@A01demort"
  echo "2. 교육 문의 : https://a01demort.com"
  echo "3. CLASSU 강의 : https://classu.co.kr/me/19375"
  echo "4. Stable AI KOREA : https://cafe.naver.com/sdfkorea"
  echo "5. 카카오톡 오픈채팅방 : https://open.kakao.com/o/gxvpv2Mf"
  echo "6. CIVITAI : https://civitai.com/user/a01demort"
  echo -e "\n==================================="
fi
