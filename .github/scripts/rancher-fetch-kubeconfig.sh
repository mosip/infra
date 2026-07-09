#!/usr/bin/env bash
#
# rancher-fetch-kubeconfig.sh - Fetch a cluster kubeconfig from Rancher via API.
#
# Replaces the manual Rancher UI step: Cluster → Kubeconfig File → Copy/Download.
# Uses the same scoped API token as rancher-register-cluster.sh.
#
# Requires: bash 4+, curl, jq.

set -euo pipefail

RANCHER_URL="${RANCHER_URL:-}"
RANCHER_TOKEN="${RANCHER_TOKEN:-}"
CLUSTER_NAME="${CLUSTER_NAME:-}"
CLUSTER_ID="${CLUSTER_ID:-}"
INSECURE="${INSECURE:-false}"
MAX_ATTEMPTS="${MAX_ATTEMPTS:-60}"
SLEEP_SECONDS="${SLEEP_SECONDS:-5}"

usage() {
  cat <<'EOF'
Usage: rancher-fetch-kubeconfig.sh --rancher-url <url> --token <token> [--cluster-name <name> | --cluster-id <id>] [--insecure]

Required:
  --rancher-url <url>     Rancher base URL (https://rancher.<env>.mosip.net, NO /v3)
  --token <token>         Rancher API bearer token

Cluster selector (one required):
  --cluster-name <name>   Rancher cluster name ([a-zA-Z0-9._-]+)
  --cluster-id <id>       Rancher cluster id (e.g. c-m-xxxxx)

Optional:
  --insecure              Skip TLS verification for Rancher API calls only
  -h, --help              Show help

Environment (optional):
  MAX_ATTEMPTS            Wait attempts for cluster to become active (default: 60)
  SLEEP_SECONDS           Seconds between wait attempts (default: 5)

Output (stdout): raw kubeconfig YAML (for GitHub KUBECONFIG environment secret).
Logs go to stderr.

Note: Run after infra deploy + Rancher import. The cluster must reach state "active".
EOF
}

err() { echo "[rancher-kubeconfig][ERROR] $*" >&2; }
die() { err "$*"; exit 1; }
log() { echo "[rancher-kubeconfig] $*" >&2; }

require_arg() {
  local flag="$1"
  [[ $# -ge 2 && -n "${2:-}" && "$2" != --* ]] || die "$flag requires a value"
}

urlencode() {
  jq -rn --arg v "$1" '$v|@uri'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --rancher-url)   require_arg --rancher-url "${2-}";   RANCHER_URL="$2"; shift 2 ;;
    --token)         require_arg --token "${2-}";         RANCHER_TOKEN="$2"; shift 2 ;;
    --cluster-name)  require_arg --cluster-name "${2-}";  CLUSTER_NAME="$2"; shift 2 ;;
    --cluster-id)    require_arg --cluster-id "${2-}";    CLUSTER_ID="$2"; shift 2 ;;
    --insecure)      INSECURE="true"; shift ;;
    -h|--help)       usage; exit 0 ;;
    *)               die "Unknown argument: $1 (use --help)" ;;
  esac
done

[[ ${BASH_VERSINFO[0]} -ge 4 ]] || die "bash 4+ is required"
[[ -n "$RANCHER_URL" ]]        || die "--rancher-url is required"
[[ -n "$RANCHER_TOKEN" ]]       || die "--token is required"
[[ -n "$CLUSTER_NAME" || -n "$CLUSTER_ID" ]] || die "--cluster-name or --cluster-id is required"
command -v curl >/dev/null 2>&1 || die "curl is required"
command -v jq   >/dev/null 2>&1 || die "jq is required"

RANCHER_URL="${RANCHER_URL%/}"
[[ "$RANCHER_URL" =~ ^https:// ]] \
  || die "RANCHER_URL must begin with https:// (got: $RANCHER_URL)"
if [[ -n "$CLUSTER_NAME" ]]; then
  [[ "$CLUSTER_NAME" =~ ^[a-zA-Z0-9._-]+$ ]] \
    || die "CLUSTER_NAME must contain only [a-zA-Z0-9._-] (got: $CLUSTER_NAME)"
fi
[[ "$MAX_ATTEMPTS" =~ ^[0-9]+$ && "$MAX_ATTEMPTS" -gt 0 ]] \
  || die "MAX_ATTEMPTS must be a positive integer (got: $MAX_ATTEMPTS)"
[[ "$SLEEP_SECONDS" =~ ^[0-9]+$ && "$SLEEP_SECONDS" -gt 0 ]] \
  || die "SLEEP_SECONDS must be a positive integer (got: $SLEEP_SECONDS)"

api() {
  local method="$1" path="$2" body="${3:-}"
  local tmp status curl_args=()
  tmp="$(mktemp "${TMPDIR:-/tmp}/rancher-api.XXXXXX")"
  trap "rm -f $(printf %q "$tmp")" RETURN

  curl_args=(
    -sS
    -o "$tmp"
    -w "%{http_code}"
    -X "$method"
    -H "Authorization: Bearer ${RANCHER_TOKEN}"
    -H "Content-Type: application/json"
    -H "Accept: application/json"
    --connect-timeout 10
    --max-time 60
  )
  [[ "$INSECURE" == "true" ]] && curl_args+=(-k)
  [[ -n "$body" ]] && curl_args+=(-d "$body")

  if ! status="$(curl "${curl_args[@]}" "${RANCHER_URL}${path}")"; then
    err "Rancher API ${method} ${path}: curl failed"
    [[ -s "$tmp" ]] && cat "$tmp" >&2
    return 1
  fi

  if [[ ! "$status" =~ ^[0-9]+$ ]] || (( status >= 400 )); then
    err "Rancher API ${method} ${path} failed with HTTP ${status:-unknown}"
    [[ -s "$tmp" ]] && cat "$tmp" >&2
    return 1
  fi

  cat "$tmp"
}

fetch_cluster_id_by_name() {
  local json count id
  if ! json="$(api GET "/v3/clusters?name=$(urlencode "$CLUSTER_NAME")")"; then
    die "Failed to query Rancher clusters by name"
  fi
  count="$(jq -r --arg name "$CLUSTER_NAME" '[.data[]? | select(.name == $name)] | length' <<<"$json")"
  if (( count > 1 )); then
    die "Multiple Rancher clusters named '$CLUSTER_NAME'; resolve duplicates manually"
  fi
  id="$(jq -r --arg name "$CLUSTER_NAME" '[.data[]? | select(.name == $name)][0].id // empty' <<<"$json")"
  [[ -n "$id" ]] || return 1
  printf '%s' "$id"
}

cluster_is_active() {
  local json state
  if ! json="$(api GET "/v3/clusters/$(urlencode "$CLUSTER_ID")")"; then
    die "Failed to query Rancher cluster '$CLUSTER_ID'"
  fi
  state="$(jq -r '.state // empty' <<<"$json")"
  [[ "$state" == "active" ]]
}

wait_for_cluster_active() {
  local attempt
  for ((attempt = 1; attempt <= MAX_ATTEMPTS; attempt++)); do
    if cluster_is_active; then
      log "Cluster ${CLUSTER_ID} is active"
      return 0
    fi
    log "Waiting for cluster ${CLUSTER_ID} to become active (attempt ${attempt}/${MAX_ATTEMPTS}) ..."
    sleep "$SLEEP_SECONDS"
  done
  die "Cluster ${CLUSTER_ID} did not become active within $((MAX_ATTEMPTS * SLEEP_SECONDS)) seconds"
}

generate_kubeconfig_yaml() {
  local response config
  response="$(api POST "/v3/clusters/$(urlencode "$CLUSTER_ID")?action=generateKubeconfig" '{}')"
  config="$(jq -r '.config // empty' <<<"$response")"
  [[ -n "$config" && "$config" != "null" ]] || die "generateKubeconfig returned empty config"
  printf '%s\n' "$config"
}

validate_kubeconfig_yaml() {
  local cfg="$1"
  grep -q '^apiVersion:' <<<"$cfg" || return 1
  grep -q '^kind: Config' <<<"$cfg" || return 1
  grep -q '^clusters:' <<<"$cfg" || return 1
  return 0
}

if [[ -z "$CLUSTER_ID" ]]; then
  log "Looking up cluster '${CLUSTER_NAME}' in Rancher ..."
  if ! CLUSTER_ID="$(fetch_cluster_id_by_name)"; then
    die "Cluster '$CLUSTER_NAME' not found in Rancher"
  fi
fi
log "Using Rancher cluster id=${CLUSTER_ID}"

wait_for_cluster_active

log "Generating kubeconfig via Rancher API ..."
KUBECONFIG_YAML="$(generate_kubeconfig_yaml)"
validate_kubeconfig_yaml "$KUBECONFIG_YAML" \
  || die "Rancher returned data that does not look like a kubeconfig"

log "Kubeconfig fetched successfully ($(wc -l <<<"$KUBECONFIG_YAML") lines)."
printf '%s\n' "$KUBECONFIG_YAML"
