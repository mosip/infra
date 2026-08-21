#!/usr/bin/env bash
#
# write-rancher-runtime-tfvars.sh - Runtime Rancher import overrides for Terraform.
#
# Profile aws.tfvars sets placeholder rancher_import_url values. The workflow mints
# a short-lived import URL at plan/apply time. Because -var-file on the CLI overrides
# TF_VAR_* environment variables, pass this file as a second -var-file (later wins).
#
# Two modes:
#   1. Write only — pass --import-cmd (or use with --enable false for destroy)
#   2. Mint + write — pass --rancher-url, --token, --cluster-name with --enable true
#      (calls rancher-register-cluster.sh, then writes the tfvars file)
#
# Requires: bash, jq; rancher-register-cluster.sh when minting

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGISTER_SCRIPT="${SCRIPT_DIR}/rancher-register-cluster.sh"

OUT=""
ENABLE=""
IMPORT_CMD=""
RANCHER_URL=""
RANCHER_TOKEN=""
CLUSTER_NAME=""
PHASE="plan"
GITHUB_ENV_FILE="${GITHUB_ENV:-}"

usage() {
  cat <<'EOF'
Usage:
  write-rancher-runtime-tfvars.sh --out <path> --enable <true|false> [options]

  --out            Output tfvars path (e.g. $RUNNER_TEMP/rancher-runtime.tfvars)
  --enable         true to enable Rancher import, false to disable (destroy)

Write-only (enable=true):
  --import-cmd     Quoted kubectl apply import command from rancher-register-cluster.sh

Mint + write (enable=true; alternative to --import-cmd):
  --rancher-url    Rancher base URL
  --token          Rancher API bearer token
  --cluster-name   Rancher cluster name
  --phase plan     Plan-time mint log message (default)
  --phase apply    Pre-apply refresh log message

When minting and GITHUB_ENV is set/writable, appends RANCHER_RUNTIME_VARS_FILE=<out>.
EOF
}

die() { echo "[write-rancher-runtime][ERROR] $*" >&2; exit 1; }

require_arg() {
  local flag="$1"
  [[ $# -ge 2 && -n "${2:-}" && "$2" != --* ]] || die "$flag requires a value"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out)          require_arg --out "${2-}";          OUT="$2"; shift 2 ;;
    --enable)       require_arg --enable "${2-}";       ENABLE="$2"; shift 2 ;;
    --import-cmd)   require_arg --import-cmd "${2-}";   IMPORT_CMD="$2"; shift 2 ;;
    --rancher-url)  require_arg --rancher-url "${2-}";  RANCHER_URL="$2"; shift 2 ;;
    --token)        require_arg --token "${2-}";        RANCHER_TOKEN="$2"; shift 2 ;;
    --cluster-name) require_arg --cluster-name "${2-}"; CLUSTER_NAME="$2"; shift 2 ;;
    --phase)        require_arg --phase "${2-}";        PHASE="$2"; shift 2 ;;
    -h|--help)      usage; exit 0 ;;
    *)              die "Unknown argument: $1" ;;
  esac
done

[[ -n "$OUT" && -n "$ENABLE" ]] || { usage; exit 1; }
case "$ENABLE" in
  true|false) ;;
  *) die "--enable must be true or false (got: $ENABLE)" ;;
esac
case "$PHASE" in
  plan|apply) ;;
  *) die "--phase must be plan or apply (got: $PHASE)" ;;
esac
command -v jq >/dev/null 2>&1 || die "jq is required"

mint_import_cmd() {
  [[ -n "$RANCHER_URL" && -n "$RANCHER_TOKEN" && -n "$CLUSTER_NAME" ]] \
    || die "Mint mode requires --rancher-url, --token, and --cluster-name"
  [[ -x "$REGISTER_SCRIPT" ]] || die "Missing or not executable: $REGISTER_SCRIPT"

  if [[ "$PHASE" == "plan" ]]; then
    echo "Registering cluster '${CLUSTER_NAME}' in Rancher (plan-time placeholder)..."
  else
    echo "Refreshing Rancher import URL for cluster '${CLUSTER_NAME}' immediately before apply..."
  fi

  set -o pipefail
  IMPORT_CMD="$("$REGISTER_SCRIPT" \
    --rancher-url "$RANCHER_URL" \
    --token "$RANCHER_TOKEN" \
    --cluster-name "$CLUSTER_NAME" | tail -n1)"
  [[ -n "$IMPORT_CMD" ]] || die "Rancher registration returned empty import command"
}

if [[ "$ENABLE" == "true" ]]; then
  if [[ -n "$RANCHER_URL" || -n "$RANCHER_TOKEN" || -n "$CLUSTER_NAME" ]]; then
    [[ -n "$RANCHER_URL" && -n "$RANCHER_TOKEN" && -n "$CLUSTER_NAME" ]] \
      || die "Pass all of --rancher-url, --token, --cluster-name together, or use --import-cmd instead"
    [[ -z "$IMPORT_CMD" ]] || die "Use either --import-cmd or mint flags (--rancher-url/--token/--cluster-name), not both"
    mint_import_cmd
  fi
  [[ -n "$IMPORT_CMD" ]] || die "--import-cmd is required when --enable true (or pass mint flags)"
fi

umask 077
TMP="$(mktemp "${OUT}.tmp.XXXXXX")" || exit 1
trap 'rm -f -- "$TMP"' EXIT
{
  echo "enable_rancher_import = $ENABLE"
  if [[ "$ENABLE" == "true" ]]; then
    printf 'rancher_import_url    = %s\n' "$(printf '%s' "$IMPORT_CMD" | jq -Rs .)"
  else
    echo 'rancher_import_url    = ""'
  fi
} > "$TMP"
mv -f -- "$TMP" "$OUT"
trap - EXIT

if [[ -n "$GITHUB_ENV_FILE" && -w "$GITHUB_ENV_FILE" ]]; then
  echo "RANCHER_RUNTIME_VARS_FILE=$OUT" >> "$GITHUB_ENV_FILE"
fi

if [[ "$ENABLE" == "true" && -n "$RANCHER_URL" ]]; then
  if [[ "$PHASE" == "plan" ]]; then
    echo "Rancher import URL minted for: $CLUSTER_NAME (runtime -var-file; not written to profile aws.tfvars)"
  else
    echo "Refreshed Rancher import URL for apply (runtime -var-file)"
  fi
fi

echo "Wrote Rancher runtime tfvars: $OUT"
