#!/usr/bin/env bash
# Run deliberately in a maintenance checkout with uv 0.8.15 installed.
set -Eeuo pipefail
cd "$(dirname "$0")/.."
[[ "$(uv --version)" == 'uv 0.8.15'* ]] || { echo 'Requires uv 0.8.15' >&2; exit 1; }
python scripts/requirements_input.py
SAM2_BUILD_CUDA=0 uv --config-file requirements/uv.toml pip compile requirements/requirements.in \
  --python-version 3.10.6 --python-platform x86_64-unknown-linux-gnu \
  --default-index https://pypi.org/simple \
  --override requirements/pytorch-wheels.txt --override requirements/overrides.txt \
  --exclude-newer 2026-01-28T00:00:00Z \
  --build-constraints requirements/pins.txt \
  --generate-hashes --no-header --output-file locks/requirements-linux-cu124.lock
python scripts/audit_wheels.py
