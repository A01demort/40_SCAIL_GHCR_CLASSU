#!/bin/bash
set -e
export PIP_CONSTRAINT=/opt/scail-runtime-fix/constraints.txt
export UV_CONSTRAINT="$PIP_CONSTRAINT"
python -B /opt/scail-runtime-fix/workspace.py
exec /opt/nvidia/nvidia_entrypoint.sh "$@"
