#!/usr/bin/env bash
set -Eeuo pipefail
cd /opt/ComfyUI
log=$(mktemp)
python /opt/scail/scripts/runtime_policy.py --user-dir /tmp/scail-smoke-user
python -u main.py --cpu --listen 127.0.0.1 --port 18188 --disable-auto-launch \
  --user-directory /tmp/scail-smoke-user --database-url sqlite:///:memory: >"$log" 2>&1 &
pid=$!
cleanup() { kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; }
trap cleanup EXIT
if ! python /opt/scail/scripts/verify_workflow.py --url http://127.0.0.1:18188 --log "$log"; then
  cat "$log"
  exit 1
fi
cat "$log"
