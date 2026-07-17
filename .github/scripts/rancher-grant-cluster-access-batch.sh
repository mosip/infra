#!/usr/bin/env bash
#
# rancher-grant-cluster-access-batch.sh - Apply multiple Rancher cluster RBAC grants.
#
# Configuration layers (merged in order; later layers override earlier for the same group):
#   1. Base file: .github/config/rancher-access-grants.json (repo defaults)
#      - DEVOPS is cluster-owner by default; other groups use enabled true/false
#   2. Environment patch: RANCHER_ACCESS_GRANTS (JSON array, merge by group name)
#   3. DEVOPS shortcuts: RANCHER_DEVOPS_ROLE, RANCHER_DEVOPS_ENABLED (per-environment)
#   4. Workflow patch: WORKFLOW_RANCHER_PATCH (from Actions UI inputs — highest priority)
#   5. CLI --grants-json replaces everything (testing / ad-hoc only)
#
# Grant entry fields:
#   group             (required) IdP group name, e.g. DEVOPS
#   role              (required) Rancher role template id, e.g. cluster-owner
#   enabled           (optional) true/false — default true; false skips the grant
#   principal_id      (optional) Full principal id, e.g. keycloak_group://DEVOPS
#   group_auth_prefix (optional) Prefix when building principal id
#   fix_misbound_user (optional) true/false — repair wrong DEVOPS bindings

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GRANT_SCRIPT="${SCRIPT_DIR}/rancher-grant-cluster-access.sh"
GRANTS_FILE="${GRANTS_FILE:-${SCRIPT_DIR%/scripts}/config/rancher-access-grants.json}"
GRANTS_JSON="${GRANTS_JSON:-}"
GRANTS_MODE="${GRANTS_MODE:-merge}"
RANCHER_URL="${RANCHER_URL:-}"
RANCHER_TOKEN="${RANCHER_TOKEN:-}"
CLUSTER_NAME="${CLUSTER_NAME:-}"
CLUSTER_ID="${CLUSTER_ID:-}"
DEFAULT_GROUP_AUTH_PREFIX="${DEFAULT_GROUP_AUTH_PREFIX:-keycloak_group}"
DEVOPS_GROUP_NAME="${RANCHER_DEVOPS_GROUP:-DEVOPS}"

usage() {
  cat <<'EOF'
Usage: rancher-grant-cluster-access-batch.sh --rancher-url <url> --token <token> \
  [--cluster-name <name> | --cluster-id <id>] [options]

Required:
  --rancher-url <url>     Rancher base URL
  --token <token>         Rancher API bearer token

Cluster selector (one required):
  --cluster-name <name>
  --cluster-id <id>

Grant sources (default mode = merge):
  --grants-file <path>    Base defaults (default: .github/config/rancher-access-grants.json)
  --grants-json '<json>'  Full replace — skips base file and env patches
  --grants-mode <mode>    merge (default) or replace

Optional:
  --default-group-auth-prefix <prefix>  Default principal prefix (default: keycloak_group)
  -h, --help

Environment (per GitHub environment / shell):
  RANCHER_ACCESS_GRANTS    JSON array — merge patch by group (overrides base file fields)
  RANCHER_DEVOPS_ROLE      Override DEVOPS role only, e.g. cluster-member
  RANCHER_DEVOPS_ENABLED   true/false — enable or disable DEVOPS grant for this env
  RANCHER_DEVOPS_GROUP     DEVOPS group name if not "DEVOPS" (default: DEVOPS)
  WORKFLOW_RANCHER_PATCH   JSON array from workflow_dispatch inputs (highest priority)
EOF
}

err() { echo "[rancher-grant-batch][ERROR] $*" >&2; }
log() { echo "[rancher-grant-batch] $*" >&2; }
die() { err "$*"; exit 1; }

require_arg() {
  local flag="$1"
  [[ $# -ge 2 && -n "${2:-}" && "$2" != --* ]] || die "$flag requires a value"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --rancher-url)                 require_arg --rancher-url "${2-}"; RANCHER_URL="$2"; shift 2 ;;
    --token)                       require_arg --token "${2-}"; RANCHER_TOKEN="$2"; shift 2 ;;
    --cluster-name)                require_arg --cluster-name "${2-}"; CLUSTER_NAME="$2"; shift 2 ;;
    --cluster-id)                  require_arg --cluster-id "${2-}"; CLUSTER_ID="$2"; shift 2 ;;
    --grants-json)                 require_arg --grants-json "${2-}"; GRANTS_JSON="$2"; shift 2 ;;
    --grants-file)                 require_arg --grants-file "${2-}"; GRANTS_FILE="$2"; shift 2 ;;
    --grants-mode)                 require_arg --grants-mode "${2-}"; GRANTS_MODE="$2"; shift 2 ;;
    --default-group-auth-prefix)   require_arg --default-group-auth-prefix "${2-}"; DEFAULT_GROUP_AUTH_PREFIX="$2"; shift 2 ;;
    -h|--help)                     usage; exit 0 ;;
    *)                             die "Unknown argument: $1" ;;
  esac
done

[[ -x "$GRANT_SCRIPT" ]] || die "Missing grant script: $GRANT_SCRIPT"
command -v jq >/dev/null 2>&1 || die "jq is required"
[[ -n "$RANCHER_URL" ]] || die "--rancher-url is required"
[[ -n "$RANCHER_TOKEN" ]] || die "--token is required"
[[ -n "$CLUSTER_NAME" || -n "$CLUSTER_ID" ]] || die "--cluster-name or --cluster-id is required"

# jq: merge grant arrays by .group; enabled defaults true; drop enabled==false
JQ_MERGE='
  def enabled_grant:
    if has("enabled") then .enabled == true else true end;
  def to_map:
    map(select((.group // "") != "")) | map({(.group): .}) | add // {};
  def from_maps($bm; $om):
    (($bm | keys) + ($om | keys) | unique) as $keys
    | [$keys[] | ($bm[.] // {}) * ($om[.] // {}) | select(enabled_grant)];
  .[0] as $base | .[1] as $patch | from_maps($base | to_map; $patch | to_map)
'

load_base_grants() {
  local default_file="${SCRIPT_DIR}/rancher-access-grants.default.json"
  if [[ -f "$GRANTS_FILE" ]]; then
    cat "$GRANTS_FILE"
  elif [[ -f "$default_file" ]]; then
    log "Grants catalog not found at $GRANTS_FILE — using built-in default ($default_file)"
    cat "$default_file"
  else
    log "No grants catalog; using minimal DEVOPS cluster-owner default"
    printf '%s' '[{"group":"DEVOPS","role":"cluster-owner","enabled":true,"principal_id":"keycloak_group://DEVOPS","fix_misbound_user":true}]'
  fi
}

build_devops_patch() {
  local obj='{}'
  if [[ -n "${RANCHER_DEVOPS_ROLE:-}" ]]; then
    obj="$(jq -c --arg g "$DEVOPS_GROUP_NAME" --arg r "$RANCHER_DEVOPS_ROLE" \
      '{group:$g, role:$r}')"
  fi
  if [[ -n "${RANCHER_DEVOPS_ENABLED:-}" ]]; then
    local enabled_json
    case "${RANCHER_DEVOPS_ENABLED,,}" in
      true|1|yes)  enabled_json=true ;;
      false|0|no) enabled_json=false ;;
      *) die "RANCHER_DEVOPS_ENABLED must be true or false (got: $RANCHER_DEVOPS_ENABLED)" ;;
    esac
    obj="$(jq -c --arg g "$DEVOPS_GROUP_NAME" --argjson e "$enabled_json" \
      --argjson cur "$obj" '($cur | if .group then . else {group:$g} end) * {group:$g, enabled:$e}')"
  fi
  if [[ "$obj" == "{}" ]]; then
    printf '%s' '[]'
  else
    jq -c --argjson o "$obj" '[$o]'
  fi
}

resolve_grants_json() {
  if [[ -n "$GRANTS_JSON" ]]; then
    log "Using --grants-json (full replace, ignoring base file and env patches)"
    printf '%s' "$GRANTS_JSON"
    return 0
  fi

  if [[ "$GRANTS_MODE" == "replace" && -n "${RANCHER_ACCESS_GRANTS:-}" ]]; then
    log "Using RANCHER_ACCESS_GRANTS (replace mode)"
    printf '%s' "$RANCHER_ACCESS_GRANTS"
    return 0
  fi

  local base env_patch devops_patch merged
  base="$(load_base_grants)"
  env_patch="${RANCHER_ACCESS_GRANTS:-[]}"
  devops_patch="$(build_devops_patch)"

  merged="$(jq -c -s "$JQ_MERGE" <(printf '%s' "$base") <(printf '%s' "$env_patch"))"
  if [[ "$devops_patch" != "[]" ]]; then
    merged="$(jq -c -s "$JQ_MERGE" <(printf '%s' "$merged") <(printf '%s' "$devops_patch"))"
    log "Applied DEVOPS env shortcuts (group=$DEVOPS_GROUP_NAME)"
  fi
  if [[ -n "${WORKFLOW_RANCHER_PATCH:-}" && "$WORKFLOW_RANCHER_PATCH" != "[]" ]]; then
    merged="$(jq -c -s "$JQ_MERGE" <(printf '%s' "$merged") <(printf '%s' "$WORKFLOW_RANCHER_PATCH"))"
    log "Applied workflow_dispatch patch (Actions UI selections)"
  fi
  if [[ -n "${RANCHER_ACCESS_GRANTS:-}" ]]; then
    log "Merged RANCHER_ACCESS_GRANTS patch onto base file"
  else
    log "Using base grants from $GRANTS_FILE"
  fi
  printf '%s' "$merged"
}

GRANTS="$(resolve_grants_json)"
echo "$GRANTS" | jq -e 'type == "array"' >/dev/null || die "Grants must be a JSON array"

COUNT="$(echo "$GRANTS" | jq 'length')"
if [[ "$COUNT" -eq 0 ]]; then
  log "No enabled grants to apply (all groups disabled or empty config)"
  exit 0
fi

log "Effective grant plan ($COUNT enabled):"
echo "$GRANTS" | jq -r '.[] | "  - \(.group): \(.role) (enabled=\(.enabled // true))"'

FAILURES=0
for i in $(seq 0 $((COUNT - 1))); do
  GROUP="$(echo "$GRANTS" | jq -r ".[$i].group // empty")"
  ROLE="$(echo "$GRANTS" | jq -r ".[$i].role // empty")"
  PRINCIPAL_ID="$(echo "$GRANTS" | jq -r ".[$i].principal_id // empty")"
  AUTH_PREFIX="$(echo "$GRANTS" | jq -r ".[$i].group_auth_prefix // empty")"
  FIX_MISBOUND="$(echo "$GRANTS" | jq -r ".[$i].fix_misbound_user // false")"

  [[ -n "$GROUP" && -n "$ROLE" ]] || die "Grant index $i must include group and role after merge"

  ARGS=(
    --rancher-url "$RANCHER_URL"
    --token "$RANCHER_TOKEN"
    --group "$GROUP"
    --role-template "$ROLE"
  )
  [[ -n "$CLUSTER_NAME" ]] && ARGS+=(--cluster-name "$CLUSTER_NAME")
  [[ -n "$CLUSTER_ID" ]] && ARGS+=(--cluster-id "$CLUSTER_ID")
  if [[ -n "$PRINCIPAL_ID" ]]; then
    ARGS+=(--group-principal-id "$PRINCIPAL_ID")
  else
    ARGS+=(--group-auth-prefix "${AUTH_PREFIX:-$DEFAULT_GROUP_AUTH_PREFIX}")
  fi
  [[ "$FIX_MISBOUND" == "true" ]] && ARGS+=(--fix-misbound-user)

  log "[$((i + 1))/$COUNT] Applying group=$GROUP role=$ROLE"
  if ! "$GRANT_SCRIPT" "${ARGS[@]}"; then
    err "Grant failed for group=$GROUP role=$ROLE"
    FAILURES=$((FAILURES + 1))
  fi
done

if [[ "$FAILURES" -gt 0 ]]; then
  die "$FAILURES grant(s) failed"
fi

log "All $COUNT grant(s) applied successfully."
