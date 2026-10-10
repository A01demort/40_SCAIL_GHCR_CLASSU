#!/usr/bin/env bash
# Build-time checks require neither Python packages nor a GPU.
set -Eeuo pipefail
cd "$(dirname "$0")/.."
python scripts/requirements_input.py
python - <<'PY'
import ast
import json
from pathlib import Path
for path in Path('scripts').glob('*.py'):
    ast.parse(path.read_text(encoding='utf-8'), filename=str(path))
for path in Path('locks').glob('*.json'):
    json.loads(path.read_text(encoding='utf-8'))
print('Installer syntax and manifests verified.')
PY
for script in *.sh scripts/*.sh; do bash -n "$script"; done
