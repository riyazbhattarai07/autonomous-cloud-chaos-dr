#!/usr/bin/env bash
# Trigger a single chaos experiment by type.
# Usage: ./run-experiment.sh cpu-stress
set -euo pipefail
PROJECT="${PROJECT:-chaos-dr}"
TYPE="${1:-cpu-stress}"

aws lambda invoke \
  --function-name "${PROJECT}-orchestrator" \
  --payload "{\"action\":\"run_experiment\",\"experiment_type\":\"${TYPE}\"}" \
  --cli-binary-format raw-in-base64-out /tmp/run.json >/dev/null
cat /tmp/run.json; echo
echo "Follow logs: aws logs tail /aws/fis/${PROJECT}-experiments --follow"
