#!/usr/bin/env bash
#
# rancher-register-cluster.sh - Mint a Rancher cluster import URL via the API.
#
# Lets the infra pipeline register/import a downstream cluster WITHOUT any human
# logging into Rancher as admin. A scoped Rancher API token (created once by
# DevOps) is used to:
#   1. Find or create an "imported" cluster by name in Rancher.
#   2. Find or create its cluster registration token.
#   3. Print the import command in the exact quoted form Terraform expects:
#        "kubectl apply -f https://<rancher-host>/v3/import/<id>.yaml"
#
# The printed value can be fed straight into TF_VAR_rancher_import_url.
#
# Requires: curl, jq.

set -euo pipefail

RANCHER_URL="${RANCHER_URL:-}"        # e.g. https://rancher.mosip.net  (NO /v3)
RANCHER_TOKEN="${RANCHER_TOKEN:-}"    # token-xxxxx:yyyyy (Bearer)
CLUSTER_NAME="${CLUSTER_NAME:-}"
INSECURE="${INSECURE:-false}"         # use insecureCommand (self-signed Rancher TLS)

usage() {
  cat <<'EOF'
Usage: rancher-register-cluster.sh --rancher-url <url> --token <token> --cluster-name <name> [--insecure]

Required (flags or env vars RANCHER_URL / RANCHER_TOKEN / CLUSTER_NAME):
  --rancher-url <url>     Rancher base URL (https://rancher.<env>.mosip.net)
  --token <token>        Rancher API bearer token (scoped, created once by DevOps)
  --cluster-name <name>  Cluster name to register/import in Rancher

Optional:
  --insecure             Emit the insecure import command (self-signed Rancher TLS)
  -h, --help             Show help

Output (stdout, last line): "kubectl apply -f https://<host>/v3/import/<id>.yaml"
EOF
}

err() { echo "[rancher-register][ERROR] $*" >&2; }
die() { err "$*"; exit 1; }
log() { echo "[rancher-register] $*" >&2; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --rancher-url)   RANCHER_URL="$2"; shift 2 ;;
    --token)         RANCHER_TOKEN="$2"; shift 2 ;;
    --cluster-name)  CLUSTER_NAME="$2"; shift 2 ;;
    --insecure)      INSECURE="true"; shift ;;
    -h|--help)       usage; exit 0 ;;
    *)               die "Unknown argument: $1 (use --help)" ;;
  esac
done

[[ -n "$RANCHER_URL" ]]   || die "--rancher-url is required"
[[ -n "$RANCHER_TOKEN" ]] || die "--token is required"
[[ -n "$CLUSTER_NAME" ]]  || die "--cluster-name is required"
command -v curl >/dev/null 2>&1 || die "curl is required"
command -v jq   >/dev/null 2>&1 || die "jq is required"

RANCHER_URL="${RANCHER_URL%/}"

api() {
  local method="$1" path="$2" body="${3:-}"
  local args=(-fsSL -X "$method"
    -H "Authorization: Bearer ${RANCHER_TOKEN}"
    -H "Content-Type: application/json"
    -H "Accept: application/json")
  [[ "$INSECURE" == "true" ]] && args+=(-k)
  [[ -n "$body" ]] && args+=(-d "$body")
  curl "${args[@]}" "${RANCHER_URL}${path}"
}

CLUSTER_JUST_CREATED="false"

log "Looking up cluster '${CLUSTER_NAME}' in Rancher ..."
CLUSTER_ID="$(api GET "/v3/clusters?name=${CLUSTER_NAME}" | jq -r '.data[0].id // empty')"

if [[ -z "$CLUSTER_ID" ]]; then
  log "Cluster not found; creating imported cluster '${CLUSTER_NAME}' ..."
  CLUSTER_ID="$(api POST "/v3/clusters" \
    "{\"type\":\"cluster\",\"name\":\"${CLUSTER_NAME}\",\"import\":true}" \
    | jq -r '.id // empty')"
  [[ -n "$CLUSTER_ID" ]] || die "Failed to create cluster in Rancher"
  CLUSTER_JUST_CREATED="true"
  log "Created cluster id=${CLUSTER_ID} (Rancher will auto-create a default registration token)"
else
  log "Found existing cluster id=${CLUSTER_ID}"
fi

extract_token_fields() {
  jq -r '
    def pick($k): (.status[$k] // .[$k] // "");
    {
      manifestUrl: pick("manifestUrl"),
      command: pick("command"),
      insecureCommand: pick("insecureCommand"),
      token: pick("token")
    }
  '
}

fetch_registration_token_list() {
  api GET "/v3/clusterregistrationtokens?clusterId=${CLUSTER_ID}"
}

pick_best_token_json() {
  local list="$1"
  echo "$list" | jq -c '
    (.data // []) as $d |
    if ($d | length) == 0 then empty
    else
      ([$d[] | select(.name == "default-token")] | .[0]) //
      ([$d[] | select((.status.manifestUrl // .status.command // .status.token // "") != "")] | .[-1]) //
      $d[-1]
    end
  '
}

read_token_fields_from_list() {
  local list="$1" token_obj fields
  token_obj="$(pick_best_token_json "$list" || true)"
  [[ -n "$token_obj" ]] || return 1
  fields="$(echo "$token_obj" | extract_token_fields)"
  MANIFEST_URL="$(echo "$fields" | jq -r '.manifestUrl')"
  COMMAND="$(echo "$fields" | jq -r '.command')"
  INSECURE_CMD="$(echo "$fields" | jq -r '.insecureCommand')"
  IMPORT_TOKEN="$(echo "$fields" | jq -r '.token')"
}

token_fields_ready() {
  [[ -n "$COMMAND" || -n "$INSECURE_CMD" || -n "$MANIFEST_URL" || -n "$IMPORT_TOKEN" ]]
}

MANIFEST_URL=""
COMMAND=""
INSECURE_CMD=""
IMPORT_TOKEN=""

try_create_registration_token() {
  log "Attempting to create a registration token (optional) ..."
  if api POST "/v3/clusterregistrationtoken" \
    "{\"type\":\"clusterRegistrationToken\",\"clusterId\":\"${CLUSTER_ID}\"}" >/dev/null 2>&1; then
    log "Registration token create request accepted"
  else
    log "Registration token create skipped or denied (HTTP 403 is normal if default-token already exists)"
  fi
}

log "Resolving cluster registration token ..."
POST_TRIED="false"

for attempt in $(seq 1 45); do
  TOKEN_LIST="$(fetch_registration_token_list)"
  TOKEN_COUNT="$(echo "$TOKEN_LIST" | jq -r '(.data // []) | length')"
  read_token_fields_from_list "$TOKEN_LIST" || true
  if token_fields_ready; then
    break
  fi

  if [[ "$POST_TRIED" != "true" && "$TOKEN_COUNT" -eq 0 ]]; then
    if [[ "$CLUSTER_JUST_CREATED" == "true" && "$attempt" -lt 8 ]]; then
      :
    else
      POST_TRIED="true"
      try_create_registration_token
    fi
  fi

  log "Waiting for registration token status (attempt ${attempt}/45) ..."
  sleep 2
done

IMPORT_CMD=""
if [[ "$INSECURE" == "true" && -n "$INSECURE_CMD" ]]; then
  IMPORT_CMD="$INSECURE_CMD"
elif [[ -n "$COMMAND" ]]; then
  IMPORT_CMD="$COMMAND"
elif [[ -n "$MANIFEST_URL" ]]; then
  IMPORT_CMD="kubectl apply -f ${MANIFEST_URL}"
elif [[ -n "$IMPORT_TOKEN" ]]; then
  IMPORT_CMD="kubectl apply -f ${RANCHER_URL}/v3/import/${IMPORT_TOKEN}.yaml"
fi

if [[ -z "$IMPORT_CMD" ]]; then
  err "Could not determine import command. Token summary:"
  echo "$TOKEN_LIST" | jq '{count: (.data|length), tokens: [.data[] | {name, command: .status.command, manifestUrl: .status.manifestUrl, token: (if .status.token then "set" else "empty" end)}]}' >&2 || true
  die "Registration token status never became ready"
fi

IMPORT_CMD="$(echo "$IMPORT_CMD" | sed -E 's/.*(kubectl apply -f https:\/\/[^ ]+\.yaml).*/\1/')"

log "Import command resolved."
printf '"%s"\n' "$IMPORT_CMD"
