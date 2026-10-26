# syntax=docker/dockerfile:1
FROM nvidia/cuda:12.4.1-cudnn-runtime-ubuntu20.04

ENV DEBIAN_FRONTEND=noninteractive
ENV PIP_CACHE_DIR=/workspace/.cache/pip
ENV PIP_CONSTRAINT=/opt/scail-runtime-fix/constraints.txt
ENV UV_CONSTRAINT=/opt/scail-runtime-fix/constraints.txt

# 시스템 패키지 및 빌드 도구 설치
RUN apt-get update && apt-get install -y \
    git wget curl ffmpeg libgl1 libzbar0 \
    build-essential libssl-dev zlib1g-dev libbz2-dev \
    libreadline-dev libsqlite3-dev libncurses5-dev \
    libncursesw5-dev xz-utils tk-dev libffi-dev \
    liblzma-dev software-properties-common \
    locales sudo tzdata xterm nano \
    nodejs npm && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Python 3.10.6 소스 설치 + 심볼릭 링크 설정
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
    mkdir -p /opt/scail-workspace && \
    git clone --depth 1 --branch v0.7.0 https://github.com/comfyanonymous/ComfyUI.git /opt/scail-workspace/ComfyUI && \
    ln -s /opt/scail-workspace/ComfyUI /workspace/ComfyUI

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
COPY runtime/constraints.txt runtime/required.txt /opt/scail-runtime-fix/
RUN pip install --no-cache-dir jupyterlab==3.6.6 jupyter-server==1.23.6

# ReActor ONNX 모델 사전 다운로드
RUN echo 'ReActor ONNX 모델 설치' && \
    mkdir -p /workspace/ComfyUI/models/insightface && \
    wget -q -O /workspace/ComfyUI/models/insightface/inswapper_128.onnx \
    https://huggingface.co/datasets/Gourieff/ReActor/resolve/main/models/inswapper_128.onnx || echo 'ONNX 다운로드 실패'

# Jupyter 설정 파일 생성 (heredoc으로 Dockerfile 파싱 안전화)
RUN mkdir -p /root/.jupyter && cat > /root/.jupyter/jupyter_notebook_config.py <<'PYCONF'
c.NotebookApp.allow_origin = '*'
c.NotebookApp.ip = '0.0.0.0'
c.NotebookApp.open_browser = False
c.NotebookApp.terminado_settings = {'shell_command': ['/bin/bash']}
PYCONF

# A1 폴더 생성 + 초기화/배너 스크립트 복사
RUN mkdir -p /opt/scail-workspace/A1 && \
    ln -s /opt/scail-workspace/A1 /workspace/A1
COPY init_or_check_nodes.sh /opt/scail-workspace/A1/init_or_check_nodes.sh
COPY init_or_check_nodes.sh /opt/scail-runtime-fix/init_or_check_nodes.sh
COPY startup_banner.sh /opt/scail-workspace/A1/startup_banner.sh
RUN chmod +x /workspace/A1/init_or_check_nodes.sh && \
    chmod +x /workspace/A1/startup_banner.sh

# Wan2.1_Vace_a1.sh 스크립트 복사 및 실행 권한
COPY Wan2.1_Vace_a1.sh /opt/scail-workspace/A1/Wan2.1_Vace_a1.sh
RUN chmod +x /workspace/A1/Wan2.1_Vace_a1.sh

# SCAIL_down_a1.sh 스크립트 복사 및 실행 권한
COPY SCAIL_down_a1.sh /opt/scail-workspace/A1/SCAIL_down_a1.sh
RUN chmod +x /workspace/A1/SCAIL_down_a1.sh

COPY runtime/bootstrap.py runtime/workspace.py runtime/entrypoint.sh runtime/start.sh /opt/scail-runtime-fix/
RUN --mount=type=cache,target=/workspace/.cache/pip \
    chmod +x /opt/scail-runtime-fix/entrypoint.sh && \
    python -B /opt/scail-runtime-fix/bootstrap.py --build /workspace/A1/init_or_check_nodes.sh

# RunPod Secure Cloud mounts an empty volume over /workspace. Keep the complete
# built workspace outside that mount and restore missing files at container boot.
WORKDIR /workspace
RUN unlink /workspace/A1 && unlink /workspace/ComfyUI
WORKDIR /workspace/ComfyUI

ENTRYPOINT ["/opt/scail-runtime-fix/entrypoint.sh"]

# 볼륨 마운트
VOLUME ["/workspace"]

# 포트 설정
EXPOSE 8188
EXPOSE 8888

# JSON CMD 형식(시그널 처리 안정화)
CMD ["bash", "-lc", "exec bash /opt/scail-runtime-fix/start.sh"]
