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
MAX_PARALLEL=5

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
# 📌 다운로드 리스트 (6개 파일)
# ====================================
downloads=(

  # 1. UNet 모델 - Wan2.1_14B_VACE-Q5_K_M.gguf
  "https://huggingface.co/QuantStack/Wan2.1_14B_VACE-GGUF/resolve/18432c8dcafd3170bc92ba933510b3bad440f3fe/Wan2.1_14B_VACE-Q5_K_M.gguf|/workspace/ComfyUI/models/unet/Wan2.1_14B_VACE-Q5_K_M.gguf|40dc6bf86a8b2541607be57b2c8f50f423f104ff0955fda13ae7d52a910d28f0"

  # 2. LoRA 모델 - Wan2.1_CausVid_14B_lora_rank32_v2
  "https://huggingface.co/Kijai/WanVideo_comfy/resolve/8260d429d19fd7a72304cad059160b95d843913f/Wan21_CausVid_14B_T2V_lora_rank32_v2.safetensors|/workspace/ComfyUI/models/loras/Wan21_CausVid_14B_T2V_lora_rank32_v2.safetensors|3d6853cb7e7e9d6d35fb6c7163a85dab98e6c91d1341e8a3cf0bfb4e66dd68cc"

  # 3. VAE 모델 - Wan_2.1_vae
  "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/123acf1cc74bccbb9bfff8ac1ee72edc08c2341d/split_files/vae/wan_2.1_vae.safetensors|/workspace/ComfyUI/models/vae/wan_2.1_vae.safetensors|2fc39d31359a4b0a64f55876d8ff7fa8d780956ae2cb13463b0223e15148976b"

  # 4. 텍스트 인코더 - umt5_xxl_fp16
  "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/123acf1cc74bccbb9bfff8ac1ee72edc08c2341d/split_files/text_encoders/umt5_xxl_fp16.safetensors|/workspace/ComfyUI/models/text_encoders/umt5_xxl_fp16.safetensors|7b8850f1961e1cf8a77cca4c964a358d303f490833c6c087d0cff4b2f99db2af"
  
  # 5. 텍스트 인코더 - umt5_xxl_fp8_e4m3fn_scaled
  "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/123acf1cc74bccbb9bfff8ac1ee72edc08c2341d/split_files/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors|/workspace/ComfyUI/models/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors|c3355d30191f1f066b26d93fba017ae9809dce6c627dda5f6a66eaa651204f68"

  # 6. UNet 모델 - Wan2.1_14B_VACE-Q8_0.gguf
  "https://huggingface.co/QuantStack/Wan2.1_14B_VACE-GGUF/resolve/18432c8dcafd3170bc92ba933510b3bad440f3fe/Wan2.1_14B_VACE-Q8_0.gguf|/workspace/ComfyUI/models/unet/Wan2.1_14B_VACE-Q8_0.gguf|3c5e7ff7718e65df4940a0dbf4dcd986e0f63f6e46ee2b397a7173f3461fb0f8"

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
