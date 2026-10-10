# SCAIL RunPod v1.0.24

이미지: `ghcr.io/a01demort/40_scail_comfyui_classu:v1.0.24`

- RunPod 볼륨: `/workspace` · ComfyUI: `8188` · Jupyter: `8888`
- 첫 실행 시 고정된 패키지와 커스텀 노드 20개를 볼륨에 설치합니다. 설치 중에는 Pod 로그를 확인하세요.
- 재시작 시 설치된 환경을 검사하고 재사용합니다. GPU 검사는 RunPod에서 실행합니다.
- ComfyUI `0.7.0` · 프런트엔드 `1.37.2` · Torch `2.5.1+cu124`
- 모델 로더의 precision은 `fp16`을 사용합니다.

모델 다운로드:

```bash
bash /workspace/A1/SCAIL_down_a1.sh
# VACE 사용 시
bash /workspace/A1/Wan2.1_Vace_a1.sh
```

필요한 Hugging Face 인증은 `HF_TOKEN` 환경 변수로 설정합니다.
`startup_banner.sh`와 `init_or_check_nodes.sh`도 `/workspace/A1/`에 있습니다.

버전 변경은 `locks/`와 `requirements/`를 갱신한 뒤 새 이미지를 빌드합니다.
`main` 푸시 또는 Actions 수동 실행으로 GHCR에 게시하며, 운영 시에는 게시된 이미지의 digest를 사용하세요.
