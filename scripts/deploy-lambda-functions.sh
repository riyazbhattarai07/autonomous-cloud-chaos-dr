#!/usr/bin/env bash
# Package each Lambda source dir into a zip and update the deployed function.
# Run after `terraform apply` has created the functions.
set -euo pipefail

PROJECT="${PROJECT:-chaos-dr}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/build"
mkdir -p "$BUILD"

declare -A FUNCS=(
  ["orchestrator"]="${PROJECT}-orchestrator"
  ["alert_handler"]="${PROJECT}-alert-handler"
  ["failover_trigger"]="${PROJECT}-failover-trigger"
)

for dir in "${!FUNCS[@]}"; do
  fn="${FUNCS[$dir]}"
  zip_path="$BUILD/${dir}.zip"
  echo "==> packaging $dir -> $zip_path"
  ( cd "$ROOT/src/$dir" && zip -qr "$zip_path" . -x '*.pyc' '__pycache__/*' )

  echo "==> updating function code: $fn"
  aws lambda update-function-code \
    --function-name "$fn" \
    --zip-file "fileb://$zip_path" \
    --no-cli-pager >/dev/null
done

echo "Done."
