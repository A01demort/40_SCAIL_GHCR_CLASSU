#!/usr/bin/env bash
# Check the runtime and input media before generation.
set -Eeuo pipefail
export PATH="/workspace/.scail/current/venv/bin:$PATH"
if [[ $# -ne 2 ]]; then
  echo 'Usage: accept.sh /path/to/reference-image /path/to/motion-video' >&2
  exit 2
fi
python /opt/scail/scripts/integrity.py check
python /opt/scail/scripts/gpu_probe.py
python /opt/scail/scripts/models.py check
python /opt/scail/scripts/check_inputs.py --image "$1" --video "$2"
python /opt/scail/scripts/verify_workflow.py --log /workspace/scail-logs/comfyui.log
echo 'Pre-generation checks passed. Run the complete workflow and verify the resulting video before approving this image digest.'
