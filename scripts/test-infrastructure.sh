#!/usr/bin/env bash
# Quick post-deploy smoke test.
set -euo pipefail
PROJECT="${PROJECT:-chaos-dr}"

echo "== Chaos target instances =="
aws ec2 describe-instances \
  --filters "Name=tag:ChaosTarget,Values=true" "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].[InstanceId,State.Name,PublicIpAddress]' --output table

echo "== FIS experiment templates =="
aws fis list-experiment-templates \
  --query 'experimentTemplates[].[id,description]' --output table

echo "== Orchestrator: list templates =="
aws lambda invoke \
  --function-name "${PROJECT}-orchestrator" \
  --payload '{"action":"list_templates"}' \
  --cli-binary-format raw-in-base64-out /tmp/orx.json >/dev/null
cat /tmp/orx.json; echo
