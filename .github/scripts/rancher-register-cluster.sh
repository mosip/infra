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
# Requires: bash 4+, curl, jq.

set -euo pipefail

RANCHER_URL="${RANCHER_URL:-}"        # e.g. https://rancher.mosip.net  (NO /v3)
RANCHER_TOKEN="${RANCHER_TOKEN:-}"    # token-xxxxx:yyyyy (Bearer)
CLUSTER_NAME="${CLUSTER_NAME:-}"
INSECURE="${INSECURE:-false}"         # skip TLS verify for Rancher API calls only
MAX_ATTEMPTS="${MAX_ATTEMPTS:-30}"
SLEEP_SECONDS="${SLEEP_SECONDS:-2}"

usage() {
  cat <<'EOF'
Usage: rancher-register-cluster.sh --rancher-url <url> --token <token> --cluster-name <name> [--insecure]

Required (flags or env vars RANCHER_URL / RANCHER_TOKEN / CLUSTER_NAME):
  --rancher-url <url>     Rancher base URL (https://rancher.<env>.mosip.net)
  --token <token>        Rancher API bearer token (scoped, created once by DevOps)
  --cluster-name <name>  Cluster name ([a-zA-Z0-9._-]+ only)

Optional:
  --insecure             Skip TLS verification for Rancher API calls only (not the import URL)
  -h, --help             Show help

Environment (optional):
  MAX_ATTEMPTS           Poll attempts for registration token (default: 30)
  SLEEP_SECONDS          Seconds between poll attempts (default: 2)

Output (stdout, last line): "kubectl apply -f https://<host>/v3/import/<id>.yaml"
EOF
}

err() { echo "[rancher-register][ERROR] $*" >&2; }
die() { err "$*"; exit 1; }
log() { echo "[rancher-register] $*" >&2; }

require_arg() {
  local flag="$1"
  [[ $# -ge 2 && -n "${2:-}" && "$2" != --* ]] || die "$flag requires a value"
}

urlencode() {
  jq -rn --arg v "$1" '$v|@uri'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --rancher-url)   require_arg --rancher-url "${2-}"; RANCHER_URL="$2"; shift 2 ;;
    --token)         require_arg --token "${2-}";       RANCHER_TOKEN="$2"; shift 2 ;;
    --cluster-name)  require_arg --cluster-name "${2-}"; CLUSTER_NAME="$2"; shift 2 ;;
    --insecure)      INSECURE="true"; shift ;;
    -h|--help)       usage; exit 0 ;;
    *)               die "Unknown argument: $1 (use --help)" ;;
  esac
done

[[ ${BASH_VERSINFO[0]} -ge 4 ]] || die "bash 4+ is required"
[[ -n "$RANCHER_URL" ]]        || die "--rancher-url is required"
[[ -n "$RANCHER_TOKEN" ]]       || die "--token is required"
[[ -n "$CLUSTER_NAME" ]]         || die "--cluster-name is required"
command -v curl >/dev/null 2>&1 || die "curl is required"
command -v jq   >/dev/null 2>&1 || die "jq is required"

RANCHER_URL="${RANCHER_URL%/}"
[[ "$RANCHER_URL" =~ ^https:// ]] \
  || die "RANCHER_URL must begin with https:// (got: $RANCHER_URL)"
[[ "$CLUSTER_NAME" =~ ^[a-zA-Z0-9._-]+$ ]] \
  || die "CLUSTER_NAME must contain only [a-zA-Z0-9._-] (got: $CLUSTER_NAME)"
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

json_cluster_create_body() {
  jq -nc --arg name "$CLUSTER_NAME" '{type: "cluster", name: $name, import: true}'
}

json_registration_token_body() {
  jq -nc --arg clusterId "$CLUSTER_ID" '{type: "clusterRegistrationToken", clusterId: $clusterId}'
}

extract_manifest_url() {
  local raw="$1"
  [[ -n "$raw" ]] || return 1
  if [[ "$raw" =~ (https://[^[:space:]]+/v3/import/[^[:space:]]+\.yaml) ]]; then
    echo "${BASH_REMATCH[1]}"
    return 0
  fi
  return 1
}

build_terraform_import_cmd() {
  local url=""

  url="$(extract_manifest_url "$MANIFEST_URL" || true)"
  if [[ -n "$url" ]]; then
    echo "kubectl apply -f ${url}"
    return 0
  fi

  if [[ -n "$IMPORT_TOKEN" ]]; then
    echo "kubectl apply -f ${RANCHER_URL}/v3/import/${IMPORT_TOKEN}.yaml"
    return 0
  fi

  for candidate in "$COMMAND" "$INSECURE_CMD"; do
    url="$(extract_manifest_url "$candidate" || true)"
    if [[ -n "$url" ]]; then
      echo "kubectl apply -f ${url}"
      return 0
    fi
  done

  return 1
}

token_fields_ready() {
  [[ -n "$IMPORT_TOKEN" ]] && return 0
  extract_manifest_url "$MANIFEST_URL" >/dev/null 2>&1 && return 0
  local candidate
  for candidate in "$COMMAND" "$INSECURE_CMD"; do
    extract_manifest_url "$candidate" >/dev/null 2>&1 && return 0
  done
  return 1
}

fetch_cluster_id_by_name() {
  local json count id
  json="$(api GET "/v3/clusters?name=$(urlencode "$CLUSTER_NAME")" || true)"
  [[ -n "$json" ]] || return 1
  count="$(jq -r --arg name "$CLUSTER_NAME" '[.data[]? | select(.name == $name)] | length' <<<"$json")"
  if (( count > 1 )); then
    die "Multiple Rancher clusters named '$CLUSTER_NAME'; resolve duplicates manually"
  fi
  id="$(jq -r --arg name "$CLUSTER_NAME" '[.data[]? | select(.name == $name)][0].id // empty' <<<"$json")"
  [[ -n "$id" ]] || return 1
  printf '%s' "$id"
}

pick_best_token_json() {
  local list="$1"
  jq -c '
    (.data // []) as $d |
    if ($d | length) == 0 then empty
    else
      ([$d[] | select(.name == "default-token")] | .[0]) //
      ([$d[] | select((.status.manifestUrl // .status.command // .status.token // "") != "")] | .[-1]) //
      $d[-1]
    end
  ' <<<"$list"
}

read_token_fields_from_list() {
  local list="$1" token_obj
  token_obj="$(pick_best_token_json "$list" || true)"
  [[ -n "$token_obj" ]] || return 1
  mapfile -t _token_fields < <(jq -r '
    def pick($k): (.status[$k] // .[$k] // "");
    pick("manifestUrl"), pick("command"), pick("insecureCommand"), pick("token")
  ' <<<"$token_obj")
  MANIFEST_URL="${_token_fields[0]:-}"
  COMMAND="${_token_fields[1]:-}"
  INSECURE_CMD="${_token_fields[2]:-}"
  IMPORT_TOKEN="${_token_fields[3]:-}"
}

fetch_registration_token_list() {
  api GET "/v3/clusterregistrationtokens?clusterId=$(urlencode "$CLUSTER_ID")"
}

try_create_registration_token() {
  log "Attempting to create a registration token (optional) ..."
  if api POST "/v3/clusterregistrationtokens" "$(json_registration_token_body)"; then
    log "Registration token create request accepted"
  else
    log "Registration token create skipped or denied (default-token may already exist)"
  fi
}

CLUSTER_JUST_CREATED="false"
MANIFEST_URL=""
COMMAND=""
INSECURE_CMD=""
IMPORT_TOKEN=""

log "Looking up cluster '${CLUSTER_NAME}' in Rancher ..."
CLUSTER_ID="$(fetch_cluster_id_by_name || true)"

if [[ -z "$CLUSTER_ID" ]]; then
  log "Cluster not found; creating imported cluster '${CLUSTER_NAME}' ..."
  create_response=""
  if create_response="$(api POST "/v3/clusters" "$(json_cluster_create_body)")"; then
    CLUSTER_ID="$(jq -r '.id // empty' <<<"$create_response")"
  fi
  if [[ -z "$CLUSTER_ID" ]]; then
    log "Create failed or conflict; re-checking if cluster already exists..."
    CLUSTER_ID="$(fetch_cluster_id_by_name || true)"
    CLUSTER_JUST_CREATED="false"
  else
    CLUSTER_JUST_CREATED="true"
    log "Created cluster id=${CLUSTER_ID} (Rancher will auto-create a default registration token)"
  fi
  [[ -n "$CLUSTER_ID" ]] || die "Failed to create or find cluster '$CLUSTER_NAME' in Rancher"
else
  log "Found existing cluster id=${CLUSTER_ID}"
fi

log "Resolving cluster registration token ..."
POST_TRIED="false"
TOKEN_LIST=""

for ((attempt = 1; attempt <= MAX_ATTEMPTS; attempt++)); do
  TOKEN_LIST="$(fetch_registration_token_list || true)"
  TOKEN_COUNT=0
  if [[ -n "$TOKEN_LIST" ]]; then
    TOKEN_COUNT="$(jq -r '(.data // []) | length' <<<"$TOKEN_LIST" 2>/dev/null || echo 0)"
  fi
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

  log "Waiting for registration token status (attempt ${attempt}/${MAX_ATTEMPTS}) ..."
  sleep "$SLEEP_SECONDS"
done

IMPORT_CMD=""
if ! IMPORT_CMD="$(build_terraform_import_cmd)"; then
  err "Could not determine import command. Token summary:"
  if [[ -n "$TOKEN_LIST" ]]; then
    jq '{count: (.data|length), tokens: [.data[]? | {name, command: .status.command, manifestUrl: .status.manifestUrl, token: (if .status.token then "set" else "empty" end)}]}' \
      <<<"$TOKEN_LIST" >&2 || true
  fi
  die "Registration token status never became ready"
fi

if [[ ! "$IMPORT_CMD" =~ ^kubectl[[:space:]]+apply[[:space:]]+-f[[:space:]]+https://[^[:space:]]+/v3/import/[^[:space:]]+\.yaml$ ]]; then
  die "Import command is not in Terraform-compatible form: $IMPORT_CMD"
fi

manifest_url="$(extract_manifest_url "$IMPORT_CMD" || true)"
[[ -n "$manifest_url" ]] \
  || die "Could not extract import manifest URL from: $IMPORT_CMD"
[[ "$manifest_url" == "${RANCHER_URL}/v3/import/"* ]] \
  || die "Import URL host does not match RANCHER_URL (got: $manifest_url)"

log "Import command resolved."
printf '"%s"\n' "$IMPORT_CMD"
