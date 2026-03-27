FROM nvidia/cuda:12.4.1-cudnn-runtime-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV PIP_CACHE_DIR=/workspace/.cache/pip

# 시스템 패키지 및 빌드 도구 + Jupyter 필수 패키지
RUN apt-get update && apt-get install -y \
    git wget curl ffmpeg libgl1 \
    build-essential libssl-dev zlib1g-dev libbz2-dev \
    libreadline-dev libsqlite3-dev libncurses5-dev \
    libncursesw5-dev xz-utils tk-dev libffi-dev \
    liblzma-dev software-properties-common \
    locales sudo tzdata xterm nano \
    nodejs npm && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Python 3.10.6 소스 설치 + pip 심볼릭 링크
WORKDIR /tmp
RUN wget https://www.python.org/ftp/python/3.10.6/Python-3.10.6.tgz && \
    tar xzf Python-3.10.6.tgz && cd Python-3.10.6 && \
    ./configure --enable-optimizations && \
    make -j$(nproc) && make altinstall && \
    ln -sf /usr/local/bin/python3.10 /usr/bin/python && \
    ln -sf /usr/local/bin/python3.10 /usr/bin/python3 && \
    ln -sf /usr/local/bin/pip3.10 /usr/bin/pip && \
    ln -sf /usr/local/bin/pip3.10 /usr/local/bin/pip && \
    cd / && rm -rf /tmp/*

# ComfyUI 설치
WORKDIR /workspace
RUN mkdir -p /workspace && chmod -R 777 /workspace && \
    chown -R root:root /workspace && \
    git clone https://github.com/comfyanonymous/ComfyUI.git /workspace/ComfyUI && \
    cd /workspace/ComfyUI && \
    git fetch --tags && \
    git checkout v0.7.0

WORKDIR /workspace/ComfyUI

# Node.js 18 설치 (Ubuntu 22.04 안정 방식)
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl gnupg && \
    mkdir -p /etc/apt/keyrings && \
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg && \
    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_18.x nodistro main" > /etc/apt/sources.list.d/nodesource.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends nodejs && \
    node -v && npm -v && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# JupyterLab 고정 버전 설치
RUN pip install --no-cache-dir jupyterlab==3.6.6 jupyter-server==1.23.6

# ReActor ONNX 모델 미리 다운로드
RUN echo '🔧 ReActor ONNX 모델 설치' && \
    mkdir -p /workspace/ComfyUI/models/insightface && \
    wget -q -O /workspace/ComfyUI/models/insightface/inswapper_128.onnx \
    https://huggingface.co/datasets/Gourieff/ReActor/resolve/main/models/inswapper_128.onnx || echo '⚠️ ONNX 다운로드 실패'

# Jupyter 설정 파일
RUN mkdir -p /root/.jupyter && \
    echo "c.NotebookApp.allow_origin = '*'
\
c.NotebookApp.ip = '0.0.0.0'
\
c.NotebookApp.open_browser = False
\
c.NotebookApp.token = ''
\
c.NotebookApp.password = ''
\
c.NotebookApp.terminado_settings = {'shell_command': ['/bin/bash']}" \
> /root/.jupyter/jupyter_notebook_config.py

# A1 폴더 생성 + 초기화/배너 스크립트 복사
RUN mkdir -p /workspace/A1
COPY init_or_check_nodes.sh /workspace/A1/init_or_check_nodes.sh
COPY startup_banner.sh /workspace/A1/startup_banner.sh
RUN chmod +x /workspace/A1/init_or_check_nodes.sh && \
    chmod +x /workspace/A1/startup_banner.sh

# Wan2.1_Vace_a1.sh 스크립트 복사 및 실행 권한 부여
COPY Wan2.1_Vace_a1.sh /workspace/A1/Wan2.1_Vace_a1.sh
RUN chmod +x /workspace/A1/Wan2.1_Vace_a1.sh

# SCAIL_down_a1.sh 스크립트 복사 및 실행 권한 부여
COPY SCAIL_down_a1.sh /workspace/A1/SCAIL_down_a1.sh
RUN chmod +x /workspace/A1/SCAIL_down_a1.sh

# 볼륨 마운트
VOLUME ["/workspace"]

# 포트 설정
EXPOSE 8188
EXPOSE 8888

# JSON CMD 형식으로 시그널 처리 안정화
CMD ["bash", "-lc", "echo 'A1(AI) : https://www.youtube.com/@A01demort' && /workspace/A1/init_or_check_nodes.sh && echo '의존성 확인 완료 - 서비스 시작' && (jupyter lab --ip=0.0.0.0 --port=8888 --allow-root --ServerApp.root_dir=/workspace --ServerApp.token='' --ServerApp.password='' & python -u /workspace/ComfyUI/main.py --listen 0.0.0.0 --port=8188 --front-end-version Comfy-Org/ComfyUI_frontend@1.37.2 & /workspace/A1/startup_banner.sh & wait)"]
