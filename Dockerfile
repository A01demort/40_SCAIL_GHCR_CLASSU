FROM nvidia/cuda:12.4.1-cudnn-runtime-ubuntu20.04@sha256:ff358fa3aee9b0eb07ea9975ffcc81b300512d590c79f7d9aaa10dd27a832e2f
ARG SCAIL_RELEASE_VERSION=1.0.24
ENV SCAIL_RELEASE_VERSION=${SCAIL_RELEASE_VERSION}
LABEL org.opencontainers.image.version="${SCAIL_RELEASE_VERSION}" \
      org.opencontainers.image.source="https://github.com/A01demort/40_SCAIL_GHCR_CLASSU"
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ENV DEBIAN_FRONTEND=noninteractive PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1 PYTHONNOUSERSITE=1
# Fixed Ubuntu snapshot: apt dependencies do not follow today's repository.
RUN rm -f /etc/apt/sources.list.d/*.list && \
    printf '%s\n' \
      'deb [check-valid-until=no] https://snapshot.ubuntu.com/ubuntu/20260128T000000Z/ focal main universe restricted multiverse' \
      'deb [check-valid-until=no] https://snapshot.ubuntu.com/ubuntu/20260128T000000Z/ focal-updates main universe restricted multiverse' \
      'deb [check-valid-until=no] https://snapshot.ubuntu.com/ubuntu/20260128T000000Z/ focal-security main universe restricted multiverse' > /etc/apt/sources.list && \
    apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates git wget curl ffmpeg aria2 libgl1 libegl1 libglib2.0-0 libgomp1 libzbar0 \
      build-essential pkg-config libcairo2-dev libssl-dev zlib1g-dev libbz2-dev libreadline-dev \
      libsqlite3-dev libncurses5-dev libncursesw5-dev xz-utils tk-dev libffi-dev liblzma-dev \
      software-properties-common locales sudo tzdata xterm nano gnupg util-linux && \
    rm -rf /var/lib/apt/lists/*
# Node.js 18 및 번들 npm 유지. 저장소 최신 버전 대신 검증한 배포 아카이브로 고정합니다.
RUN curl --fail --location --retry 3 -o /tmp/node.tar.xz https://nodejs.org/dist/v18.20.8/node-v18.20.8-linux-x64.tar.xz && \
    echo '5467ee62d6af1411d46b6a10e3fb5cacc92734dbcef465fea14e7b90993001c9  /tmp/node.tar.xz' | sha256sum -c - && \
    tar -xJf /tmp/node.tar.xz -C /usr/local --strip-components=1 && \
    rm /tmp/node.tar.xz && node --version && npm --version
WORKDIR /tmp
RUN curl --fail --location --retry 3 -o python.tgz https://www.python.org/ftp/python/3.10.6/Python-3.10.6.tgz && \
    echo '848cb06a5caa85da5c45bd7a9221bb821e33fc2bdcba088c127c58fad44e6343  python.tgz' | sha256sum -c - && \
    tar xzf python.tgz && cd Python-3.10.6 && \
    ./configure --enable-optimizations && make -j"$(nproc)" && make altinstall && \
    ln -s /usr/local/bin/python3.10 /usr/local/bin/python && \
    ln -s /usr/local/bin/python3.10 /usr/local/bin/python3 && \
    ln -s /usr/local/bin/pip3.10 /usr/local/bin/pip && \
    ln -s /usr/local/bin/pip3.10 /usr/local/bin/pip3 && \
    cd / && rm -rf /tmp/Python-3.10.6 /tmp/python.tgz
COPY locks /opt/scail/locks
COPY requirements /opt/scail/requirements
COPY scripts /opt/scail/scripts
COPY init_or_check_nodes.sh startup_banner.sh SCAIL_down_a1.sh Wan2.1_Vace_a1.sh /opt/scail/
# 기존 Jupyter 설정 파일 유지
COPY config/jupyter_notebook_config.py /root/.jupyter/jupyter_notebook_config.py
# Only static checks run during the image build. GPU setup runs on RunPod.
RUN python /opt/scail/scripts/requirements_input.py && \
    chmod +x /opt/scail/*.sh /opt/scail/scripts/*.sh && \
    /opt/scail/scripts/smoke.sh
ENV WAS_BLOCK_AUTO_INSTALL=true YOLO_AUTOINSTALL=false NO_ALBUMENTATIONS_UPDATE=1 \
    HF_HOME=/workspace/.cache/huggingface
WORKDIR /workspace
# 기존 /workspace 볼륨 선언 유지
VOLUME ["/workspace"]
EXPOSE 8188 8888
HEALTHCHECK --interval=60s --timeout=30s --start-period=3600s --retries=3 \
  CMD python /opt/scail/scripts/verify_workflow.py --log /workspace/scail-logs/comfyui.log --timeout 10 || exit 1
ENTRYPOINT ["/opt/scail/scripts/start.sh"]
