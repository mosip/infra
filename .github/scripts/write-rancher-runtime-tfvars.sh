#!/usr/bin/env bash
#
# write-rancher-runtime-tfvars.sh - Runtime Rancher import overrides for Terraform.
#
# Profile aws.tfvars sets placeholder rancher_import_url values. The workflow mints
# a short-lived import URL at plan/apply time. Because -var-file on the CLI overrides
# TF_VAR_* environment variables, pass this file as a second -var-file (later wins).
#
# Requires: bash, jq

set -euo pipefail

OUT=""
ENABLE=""
IMPORT_CMD=""

usage() {
  cat <<'EOF'
Usage:
  write-rancher-runtime-tfvars.sh --out <path> --enable <true|false> [--import-cmd <cmd>]

  --out         Output tfvars path (e.g. $RUNNER_TEMP/rancher-runtime.tfvars)
  --enable      true to enable Rancher import, false to disable (destroy)
  --import-cmd  Quoted kubectl apply import command from rancher-register-cluster.sh
                Required when --enable true
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out)        OUT="$2"; shift 2 ;;
    --enable)     ENABLE="$2"; shift 2 ;;
    --import-cmd) IMPORT_CMD="$2"; shift 2 ;;
    -h|--help)    usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

[[ -n "$OUT" && -n "$ENABLE" ]] || { usage; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 1; }

{
  echo "enable_rancher_import = $ENABLE"
  if [[ "$ENABLE" == "true" ]]; then
    [[ -n "$IMPORT_CMD" ]] || { echo "--import-cmd is required when --enable true" >&2; exit 1; }
    printf 'rancher_import_url    = %s\n' "$(printf '%s' "$IMPORT_CMD" | jq -Rs .)"
  else
    echo 'rancher_import_url    = ""'
  fi
} > "$OUT"

echo "Wrote Rancher runtime tfvars: $OUT"
