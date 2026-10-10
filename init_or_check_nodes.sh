#!/usr/bin/env bash
# Deliberately no pip/git/network writes on Pod startup.
set -Eeuo pipefail
python /opt/scail/scripts/integrity.py check
python /opt/scail/scripts/gpu_probe.py

# 🎓 AI 교육 & 커뮤니티 안내 (기존 안내 유지)
echo -e "\n====🎓 AI 교육 & 커뮤니티 안내====\n"
echo "1. Youtube : https://www.youtube.com/@A01demort"
echo "2. 교육 문의 : https://a01demort.com"
echo "3. CLASSU 강의 : https://classu.co.kr/me/19375"
echo "4. Stable AI KOREA : https://cafe.naver.com/sdfkorea"
echo "5. 카카오톡 오픈채팅방 : https://open.kakao.com/o/gxvpv2Mf"
echo "6. CIVITAI : https://civitai.com/user/a01demort"
echo -e "\n==================================="
