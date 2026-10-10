# SCAIL RunPod 고정 환경 v1.0.24

SCAIL 실행 환경의 **배포 후보**입니다. 유료 워크플로우와 개인 입력 자료는 이 저장소·배포 ZIP·컨테이너 이미지에 포함하지 않습니다. 로컬 검증은 통과했지만 이 작업 환경에는 Docker 엔진과 RunPod 접속 정보가 없어 컨테이너 빌드, 실제 Linux 노드 import, GPU 영상 생성은 아직 실행하지 못했습니다. 아래의 배포 검증까지 통과한 이미지 digest만 운영에 사용하세요.

소스 저장소는 [A01demort/40_SCAIL_GHCR_CLASSU](https://github.com/A01demort/40_SCAIL_GHCR_CLASSU)입니다. 이번 릴리스의 이미지 태그는 `ghcr.io/a01demort/40_scail_comfyui_classu:v1.0.24`이며, GitHub Actions의 `RELEASE_VERSION`과 Dockerfile 기본 버전, 이미지 메타데이터, 시작 로그를 `1.0.24`로 맞췄습니다. 태그는 게시 작업이 성공해야 생성됩니다.

## 확인된 원인

- 로그의 ComfyUI는 `v0.7.0 / f59f71cf`입니다. 본체가 저절로 최신 버전으로 바뀌었다는 증거는 없습니다.
- 기존 시작 스크립트는 Torch `2.5.1`을 고정하면서 `transformers`, `diffusers`, `peft` 등을 버전 없이 매번 설치했습니다. 첨부 로그에서는 이 라이브러리들이 `torch.accelerator`를 호출해 WanVideoWrapper 등 6개 팩의 import가 실패했습니다. 로그에 두 라이브러리의 정확한 설치 버전은 기록되어 있지 않습니다.
- `git clone ... && git checkout ...`은 폴더가 이미 있으면 clone에서 실패하므로 checkout도 실행하지 않습니다. 기존 볼륨의 노드 버전을 강제 고정하지 못했습니다.
- ComfyUI 자체의 `requirements.txt` 설치가 빠져 `alembic`, workflow templates, embedded docs가 누락됐습니다.
- `|| echo`로 실패를 무시하고 설치 마커를 남겼습니다. `.installed`는 실제 Python 환경의 상태와 일치하지 않을 수 있습니다.
- 배너는 웹 서버가 응답하면 `ALL GOOD`을 표시했습니다. 실제로는 6개 노드 팩이 실패한 상태였습니다.
- 추가로 ONNX Runtime `1.18.0`은 cuDNN 8 계열이며 현재 Torch/CUDA 조합의 cuDNN 9와 맞지 않습니다. 이 문제는 첨부 로그의 직접적인 import 원인과는 별개의 GPU 실행 위험입니다.

## 고정한 범위

| 대상 | 고정 방식 |
|---|---|
| CUDA 기반 이미지 | `Dockerfile`의 SHA256 digest |
| OS 패키지 | Ubuntu `20260128T000000Z` 저장소 스냅샷 |
| Python | `3.10.6`, 소스 tarball SHA256 확인 |
| ComfyUI | `f59f71cf34067d46713f6243312f7f0b360d061f` (`v0.7.0`) |
| Node.js / npm | Node.js `18.20.8` 및 번들 npm, 공식 아카이브 SHA256 확인 |
| 프런트엔드 | 기존 시작 설정의 `1.37.2`, 패키지와 SHA256으로 고정 |
| 커스텀 노드 | 기존 20개 팩 전부, 각각 전체 40자리 커밋 |
| Python 라이브러리 | 336개 전체 전이 의존성의 정확한 버전 + SHA256 |
| 모델 | 기존 SCAIL 9개 + 선택 Q8, VACE 6개, ReActor 사전 다운로드의 URL·크기·SHA256 |
| 실행 환경 | 빌드 시 저장한 소스 해시 및 패키지 목록을 부팅 때 재검사 |
| 운영 배포 | GitHub Actions 출력의 `이미지@sha256:...` 사용 |

핵심 라이브러리는 Torch `2.5.1+cu124`, torchvision `0.20.1+cu124`, torchaudio `2.5.1+cu124`, Transformers `4.51.3`, Diffusers `0.35.1`, PEFT `0.17.1`, NumPy `1.26.4`, ONNX Runtime GPU `1.20.0`입니다. 선택한 버전은 메타데이터 의존성 해결과 휠 존재 검사를 통과한 후보이며, 이것만으로 전체 GPU 호환성을 입증하지는 않습니다.

| 노드 팩 | 커밋 앞 8자리 |
|---|---|
| ComfyUI-Manager | `fa009e72` |
| ComfyUI-Custom-Scripts | `f2838ed5` |
| rgthree-comfy | `8ff50e45` |
| was-node-suite-comfyui | `ea935d10` |
| ComfyUI-KJNodes | `7b132719` |
| ComfyUI_essentials | `9d9f4bed` |
| ComfyUI_Comfyroll_CustomNodes | `d78b780a` |
| ComfyUI-GGUF | `795e4515` |
| ComfyUI-ReActor | `d60458f2` |
| ComfyUI-Easy-Use | `23d9c365` |
| ComfyUI-VideoHelperSuite | `3234937f` |
| ComfyUI-FramePackWrapper | `a7c4b704` |
| ComfyUI-MultiGPU | `6e4181a7` |
| comfyui_controlnet_aux | `59b027e0` |
| ComfyUI_LayerStyle | `5840264d` |
| ComfyUI-Frame-Interpolation | `a969c01d` |
| ComfyUI-Impact-Pack | `51b7dcdf` |
| ComfyUI-WanVideoWrapper | `2ee9e2f3` |
| ComfyUI-WanAnimatePreprocess | `1a35b81a` |
| ComfyUI-SCAIL-Pose | `11402b15` |

원래 설치 스크립트의 **20개 팩을 모두 유지**합니다. 전체 커밋은 `locks/sources.json`, Python 패키지는 `locks/requirements-linux-cu124.lock`, 모델은 `locks/models.json`이 기준입니다. 커스텀 노드 삭제로 충돌을 회피하지 않습니다.

Manager도 설치·로드합니다. 시작 전 `network_mode=offline`, `security_level=strong`을 적용하고, 예약된 설치·복원·자동 복구 명령이 있으면 원본 큐를 보존한 채 시작을 중단합니다. WAS와 Ultralytics의 자동 패키지 설치도 차단합니다. 이후 의도적인 업데이트는 별도 유지보수 이미지에서 잠금을 갱신합니다.

WAS와 Impact의 Git 의존성 4개도 `locks/source-packages.json`에서 전체 커밋·아카이브 SHA256으로 고정합니다. Frame Interpolation은 upstream의 `requirements-no-cupy.txt`와 기존 Taichi 백엔드를 사용합니다. requirements 파일이 없는 노드는 빈 스냅샷과 명시적 경로 설정으로 처리합니다.

336개 패키지는 Linux 휠 322개와 소스 빌드 14개로 나눠 설치합니다. `binary.lock`으로 고정된 빌드 도구를 먼저 설치한 뒤, `source.lock`은 해시 검사와 `--no-build-isolation`을 사용해 설치합니다. 두 파일의 합집합이 전체 잠금과 정확히 일치하는지 테스트합니다. 공식 sdist 메타데이터와 Git setup.py의 요구사항은 `requirements/uv.toml`에 기록해 Windows 유지보수 환경에서 CUDA 빌드를 실행하지 않고도 잠금을 만들 수 있게 했습니다.

OpenCV 배포판을 서로 다른 버전으로 설치하지 않습니다. 일부 패키지의 배포판 이름 요구를 충족하기 위해 세 배포판을 모두 `4.11.0.86`으로 맞추고, 마지막에 contrib 휠을 다시 설치해 실제 `cv2` 파일을 확정합니다. 같은 이유로 ONNX Runtime 두 배포판을 `1.20.0`으로 맞추고 GPU 휠을 마지막에 설치합니다. CUDA 실제 세션 검사도 통과해야 합니다. SAM2는 upstream이 지원하는 portable 빌드이며, 선택적 CUDA 후처리 확장은 컴파일하지 않습니다.

기존 설치 명령의 `facelib==0.2.2`는 의존성 해결에 실패했습니다. ReActor 자체에 포함된 `r_facelib`을 유지하고, `facexlib`, BasicSR, GFPGAN, RealESRGAN, MTCNN 및 기존 attention 패키지는 별도로 고정합니다. 이는 ReActor 노드 팩 삭제가 아닙니다.

기존 Node.js 18, 프런트엔드 `1.37.2`, ReActor `inswapper_128.onnx` 사전 다운로드, Jupyter 설정, 시스템 도구와 `/workspace` 볼륨 선언을 유지합니다. 프런트엔드는 `requirements/overrides.txt`에서 명시적으로 선택하고 전체 잠금에 반영합니다. 코어 upstream requirements의 원본 바이트는 변경하지 않습니다. ReActor 모델은 `locks/models-reactor.json`의 커밋 URL과 SHA256으로 빌드 때 검증하며, 실패하면 빌드도 중단합니다.

기존 스크립트 네 개는 이미지의 `/opt/scail`에 포함되고, 부팅 때 아래 경로에 배치됩니다. 같은 파일은 다시 복사하지 않으며, 기존 파일 내용이 다르면 번호가 붙은 백업을 보존합니다.

```text
/workspace/A1/
├── startup_banner.sh
├── init_or_check_nodes.sh
├── SCAIL_down_a1.sh
└── Wan2.1_Vace_a1.sh
```

두 모델 다운로드 스크립트는 원래 모델 선택, 설명 주석, 병렬 다운로드 수(SCAIL 8 / VACE 5), 진행 표시, 소요 시간, 교육·커뮤니티 안내와 실패 파일 재시도 확인을 유지합니다. SCAIL의 Lightx2v도 포함하며 Q8 선택 항목도 주석으로 남깁니다. 변경점은 고정 커밋 URL·SHA256 검사, `HF_TOKEN` 환경 변수 사용, 누락·손상 파일의 실패 처리입니다. Aria2는 이미지에 설치하므로 실행 중 apt 업데이트가 필요하지 않습니다.

## 비공개 자료와 시작 배너

- 유료 워크플로우 원본·수정본·노드 연결·좌표·프롬프트·위젯 설정·입력 미디어는 배포하지 않습니다. 사용자가 자신의 비공개 워크플로우를 ComfyUI에서 직접 열어야 합니다.
- `requirements/node-types.json`에는 공개 커스텀 노드의 클래스 이름 33개와 프런트엔드 확장 이름 2개만 있습니다. 워크플로우 그래프가 아니며, 노드 등록 검사에만 사용합니다.
- `/workflows/`, `/private/`, `/attachments/`, 입력·출력 폴더, 로컬 도구·조사 파일, 로그, `.env`는 Git과 Docker 빌드에서 제외합니다. 배포 ZIP도 공개 파일만 명시적으로 선택해 만듭니다. 이미 Git에서 추적 중인 파일은 ignore 규칙만으로 제외되지 않으므로 커밋 대상 목록을 별도로 확인해야 합니다.
- Torch 2.5.1에서 지원하지 않는 `fp16_fast` 대신 비공개 워크플로우의 모델 로더에서 `fp16`을 선택해야 합니다. 예외를 `pass`로 무시하던 기존 소스 패치는 제거했습니다.
- 기존 시작 배너의 ASCII 그림, `ALL GOOD`, 준비 완료 문구, YouTube·카페·Discord 링크와 초기화 스크립트의 교육·커뮤니티 안내 6개를 유지합니다. 배너는 서버 응답 및 노드 등록·오류 로그 검사를 통과한 뒤 표시합니다. 전체 영상 생성 성공을 의미하지 않습니다.
- 설치 코드를 다시 작성하면서 예전 설치 절차를 설명하던 주석은 바뀌었습니다. 모든 주석을 그대로 보존한 수정은 아닙니다.

## 적용 순서

1. 기존 Pod와 정상 작동했던 이미지 주소/digest를 보존합니다. 기존 볼륨의 모델·입력·출력을 삭제할 필요가 없습니다.
2. 검사한 공개 배포 파일만 본인의 해당 GitHub 저장소에 반영합니다. 작업 폴더 전체나 유료 자료를 수동 업로드하지 않습니다. 실제 이미지 게시 성공 여부는 GitHub Actions 실행 결과에서 확인합니다.
3. 기존처럼 `main` push 시 GitHub Actions의 **Build and Push locked SCAIL v1.0.24**가 빌드하고, 검증 성공 후 GHCR에 게시합니다. **Run workflow**로도 실행할 수 있습니다. 따라서 실제 push는 이미지 게시를 함께 시작하는 작업입니다.
4. 빌드에는 실제 ComfyUI CPU 실행 및 `/object_info` 검사 단계가 포함됩니다. 원래 20개 노드 팩 중 하나라도 성공한 import 로그가 없거나, import 오류·필요한 공개 노드·프런트엔드 확장 누락이 있으면 빌드가 실패합니다. 비공개 워크플로우의 연결·설정은 이 검사에 포함되지 않습니다. 게시가 성공하면 `v1.0.24`와 `sha-<소스 커밋>` 태그가 생성됩니다. Summary에 표시되는 `ghcr.io/a01demort/40_scail_comfyui_classu@sha256:<digest>`를 기록합니다. 이전 릴리스 태그는 덮어쓰지 않습니다.
5. 테스트용 RunPod Pod의 컨테이너 이미지에 그 **digest 주소**를 넣습니다. 볼륨은 `/workspace`, HTTP 포트는 `8188`, `8888`입니다. 기존의 수동 `pip install`, 업데이트 명령, `/workspace`의 옛 시작 스크립트를 호출하는 Docker/Start Command 설정은 비웁니다. 이미지의 ENTRYPOINT가 실행되어야 합니다.
6. 로그에서 소스/패키지 일치, CUDA SDPA, 실제 ONNX CUDA 세션, 노드 등록 검사가 통과하는지 확인합니다. 실패하면 서버를 정상 준비 상태로 취급하지 않고 컨테이너가 종료됩니다.
7. Jupyter 터미널에서 모델을 준비합니다. 기존 파일도 전체 SHA256으로 검사합니다. SCAIL 기본 모델은 원래 9개이며 다운로드 공간을 확보해야 합니다. VACE 스크립트는 원래 6개 모델을 별도로 내려받습니다.

```bash
bash /workspace/A1/SCAIL_down_a1.sh
# VACE가 필요할 때:
bash /workspace/A1/Wan2.1_Vace_a1.sh
```

필요하면 RunPod 환경 변수 `HF_TOKEN`을 설정합니다. 토큰은 파일에 넣지 않습니다. 기존 모델이 잠금값과 다르면 해당 경로를 알리고, 삭제 후 재다운로드할지 기존처럼 Y/N으로 묻습니다. N 또는 입력 종료 시 파일을 보존하고 실패 상태로 종료합니다. NLF 모델도 포함되어 있어 워크플로우 실행 중 임의로 내려받을 필요가 없습니다.

8. 본인의 실제 이미지와 동영상을 비공개 Pod의 입력 폴더에 준비하고, ComfyUI에서 자신의 비공개 워크플로우와 해당 미디어를 선택합니다. 아래 경로는 예시이므로 실제 파일명으로 바꿉니다.
9. 아래 검사를 실행합니다.

```bash
bash /opt/scail/scripts/accept.sh /workspace/ComfyUI/input/reference.png /workspace/ComfyUI/input/motion.mp4
```

10. ComfyUI에서 비공개 워크플로우의 **전체 영상 생성**을 완료합니다. 저장된 영상, 프레임 수, 오디오, 인물 움직임, GPU 메모리 사용을 확인합니다. 같은 Pod를 재시작한 뒤 검사를 다시 실행하고 생성도 재확인합니다. 이 단계까지 통과한 digest를 운영 템플릿에 적용합니다.

소스는 `/opt/ComfyUI`, 고정 설정은 `/opt/scail`에 있으므로 `/workspace` 볼륨 마운트가 설치 코드를 가리지 않습니다. 입력·출력·모델은 기존 `/workspace/ComfyUI` 아래를 사용합니다. 새 UI 사용자 설정과 DB는 `/workspace/scail-user`, 로그는 `/workspace/scail-logs`에 있습니다. Manager는 유지하면서 이전 볼륨의 예약된 설치 작업이 자동으로 따라오지 않도록 별도 사용자 디렉터리를 사용합니다.

## 이후 업데이트와 롤백

운영 Pod에서 Manager 업데이트, `git pull`, `pip install -U`를 실행하는 방식은 사용하지 않습니다. 기본 환경은 `PIP_NO_INDEX=1`, `PIP_REQUIRE_HASHES=1`, Hugging Face offline 모드로 시작합니다. 부팅 중 패키지 설치·저장소 clone·fetch는 없습니다.

업데이트가 필요하면 별도 작업 복사본에서 다음 순서를 밟습니다.

1. 변경할 소스만 새 전체 커밋으로 지정하고, 해당 커밋의 `requirements.txt`를 `requirements/upstream`에 갱신합니다. `locks/sources.json`의 커밋과 requirements SHA256도 함께 갱신합니다.
2. `python scripts/requirements_input.py --write`로 입력 파일을 갱신합니다. 호환성 검토 후 `requirements/pins.txt`를 수정합니다.
3. 유지보수 환경에 `uv==0.8.15` 및 Python `packaging`을 준비하고 `bash scripts/lock.sh`를 실행합니다. 이 명령은 전체 잠금과 binary/source/shared-modules 설치 잠금을 함께 갱신합니다. Git 패키지를 바꾸면 source-packages manifest와 메타데이터도 함께 검토합니다. 의도적으로 더 새 패키지가 필요하면 스크립트의 cutoff 날짜도 검토 후 변경합니다. 잠금 파일을 만들 때만 의존성을 해결합니다.
4. 로컬 테스트 → 새 이미지 빌드/CPU import 검사 → 테스트 RunPod의 GPU 검사 → 전체 영상 생성 → 재시작 재검사를 통과시킵니다.
5. 운영 템플릿의 digest를 새 값으로 교체합니다. 이전 digest와 기존 사용자 설정/DB 백업을 보관합니다. 문제가 생기면 이전 digest의 새 Pod로 되돌립니다. 이후 코어 업데이트에 DB 마이그레이션이 포함된다면 코드만 롤백하지 말고 해당 버전의 DB 백업도 사용합니다.

관리자가 컨테이너를 직접 수정하거나 GPU/드라이버·입력 영상·모델을 바꾸는 것까지 물리적으로 막는 장치는 아닙니다. 정상 시작 경로의 자동 변경을 제거하고 변경을 탐지하는 구조입니다. 특히 다른 GPU 세대와 긴 영상의 VRAM 부족은 버전 고정만으로 보장할 수 없습니다.

## 이번 검증 결과

| 항목 | 결과 |
|---|---|
| 첨부 로그의 원인 분석 | 완료 |
| 공식 저장소 커밋/requirements 확인 | ComfyUI + 원래 커스텀 노드 20개 완료 |
| 공개 서버 노드 클래스 33개의 소스 등록 항목 확인 | 모두 존재; 실제 Linux import와는 별도 |
| 336개 패키지 의존성 해결 및 해시 잠금 | 통과 |
| CPython 3.10 / Linux glibc 2.31 배포 파일·해시 검사 | 휠 322개 + 소스 아카이브 14개 확인; 소스 컴파일은 Docker에서 검증 필요 |
| 기존 모델 선택과 크기/해시 고정 | SCAIL 9개 + 선택 Q8, VACE 6개, ReActor 사전 다운로드 포함 |
| Python 회귀 테스트 | 16개 통과; 20개 팩 보존, Manager 변경 차단, 다운로드 누락·손상·중단 파일 거부 포함 |
| Python 문법 / Bash 문법 | 통과 |
| Docker 이미지 빌드 및 Linux CPU import 검사 | 미실행 — Docker 엔진 없음; 14개 소스 패키지 컴파일·pip check·20개 팩 CPU import를 빌드 필수 단계로 구현 |
| RunPod GPU, 브라우저 import, 전체 영상, 재시작 검증 | 미실행 — Pod 접속 및 입력 미디어 미제공 |

**따라서 현재 결과는 수정 및 로컬 검증 완료이고, RunPod 무오류 실행 인증 완료는 아닙니다.** `accept.sh`도 사전 검사이며 전체 생성 성공의 대체물이 아닙니다.

## 근거

- [ComfyUI v0.7.0 필수 의존성](https://github.com/comfyanonymous/ComfyUI/blob/f59f71cf34067d46713f6243312f7f0b360d061f/requirements.txt)
- [고정 WanVideoWrapper의 요구사항](https://github.com/kijai/ComfyUI-WanVideoWrapper/blob/2ee9e2f3561b6f387024291d7d134ef8b2d6d344/requirements.txt)
- [고정 WanVideoWrapper의 fp16_fast 처리](https://github.com/kijai/ComfyUI-WanVideoWrapper/blob/2ee9e2f3561b6f387024291d7d134ef8b2d6d344/nodes_model_loading.py#L1070)
- [ONNX Runtime 공식 CUDA/cuDNN 호환표](https://onnxruntime.ai/docs/execution-providers/CUDA-ExecutionProvider.html#requirements)
- [Docker 이미지 digest 설명](https://docs.docker.com/dhi/explore/security-concepts/digests/)
