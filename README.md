# SCAIL 1.0.25

기존 버전: `ghcr.io/a01demort/40_scail_comfyui_classu:v1.0.23`

사용할 버전:
```text
ghcr.io/a01demort/40_scail_comfyui_classu:v1.0.25
```

- Torch 2.5.1과 최신 라이브러리 충돌 → 검증한 호환 버전 고정.
- NumPy/OpenCV 충돌, ONNX의 CPU 덮어쓰기 → 버전 정렬과 GPU 복구.
- BasicSR import 오류와 누락 의존성 → import 수정 및 필수 패키지 설치.
- 프런트엔드 다운로드 오류 → 기존 1.37.2 캐시 우선 사용.
- SAM-2 설치의 Torch·Git 주소 충돌 → 공식 CUDA 인덱스와 고정 Git 주소 사용.
- 재시작 때 의존성을 검사·복구하며 기존 설정을 유지.

1.0.23의 기본 sh 파일, 주석, 설치 완료 멘트와 재시작 배너는 그대로 유지합니다.
