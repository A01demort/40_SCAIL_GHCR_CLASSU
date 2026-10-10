#!/bin/bash
export PIP_CONSTRAINT=/opt/scail-runtime-fix/constraints.txt
export UV_CONSTRAINT="$PIP_CONSTRAINT"
exec /opt/nvidia/nvidia_entrypoint.sh "$@"
