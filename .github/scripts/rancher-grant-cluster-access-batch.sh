#!/usr/bin/env bash
#
# rancher-grant-cluster-access-batch.sh - Apply multiple Rancher cluster RBAC grants.
#
# Configuration layers (merged in order; later layers override earlier for the same group):
#   1. Base file: .github/config/rancher-access-grants.json (repo defaults)
#   2. Environment patch: RANCHER_ACCESS_GRANTS (JSON array, merge by group name)
#   3. DEVOPS shortcuts: RANCHER_DEVOPS_ROLE, RANCHER_DEVOPS_ENABLED (per-environment)
#   4. Workflow patch: WORKFLOW_RANCHER_PATCH (from Actions UI inputs — highest priority)
#   5. CLI --grants-json replaces everything (testing / ad-hoc only)

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
EOF
}

err() { echo "[rancher-grant-batch][ERROR] $*" >&2; }
log() { echo "[rancher-grant-batch] $*" >&2; }
die() { err "$*"; exit 1; }

require_arg() {
  local flag="$1"
  [[ $# -ge 2 && -n "${2:-}" && "$2" != --* ]] || die "$flag requires a value"
}

# Valid Rancher role template ids: built-in cluster-* roles or custom rt-* templates.
validate_role() {
  local role="$1" group="$2"
  [[ -n "$role" ]] || die "Grant for group '$group' has empty role"
  if [[ "$role" =~ ^(cluster-[a-z0-9-]+|rt-[a-z0-9]+)$ ]]; then
    return 0
  fi
  die "Invalid role '$role' for group '$group' (expected cluster-* or rt-* template id)"
}

# IdP group names: non-empty, no whitespace/control chars (allows TL+ARCHITECT).
validate_group() {
  local group="$1"
  [[ -n "$group" ]] || die "Grant entry has empty group name"
  if [[ "$group" =~ [[:space:]] ]] || [[ "$group" =~ [[:cntrl:]] ]]; then
    die "Invalid group name '$group' (must not contain spaces or control characters)"
  fi
}

validate_json_array() {
  local label="$1" json="$2"
  [[ -n "${json// }" ]] || return 0
  printf '%s' "$json" | jq -e 'type == "array"' >/dev/null \
    || die "Invalid JSON in $label (must be a JSON array)"
}

validate_grants_array() {
  local label="$1" json="$2"
  validate_json_array "$label" "$json"
  [[ -n "${json// }" ]] || return 0
  local bad
  bad="$(printf '%s' "$json" | jq -r '
    .[] |
    select(
      ((.group // "") | test("^[[:graph:]]+$") | not)
      or ((.role // "") | test("^(cluster-[a-z0-9-]+|rt-[a-z0-9]+)$") | not)
    )
    | "  - group=\(.group // "MISSING") role=\(.role // "MISSING")"
  ' 2>/dev/null || true)"
  if [[ -n "$bad" ]]; then
    die "$(printf 'Invalid grant entries in %s:\n%s' "$label" "$bad")"
  fi
  local dup
  dup="$(printf '%s' "$json" | jq -r '[.[].group // ""] | group_by(.) | map(select(length > 1 and .[0] != "")) | .[][0]' | sort -u)"
  if [[ -n "$dup" ]]; then
    die "$(printf 'Duplicate group names in %s:\n%s' "$label" "$dup")"
  fi
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

[[ -f "$GRANT_SCRIPT" ]] || die "Missing grant script: $GRANT_SCRIPT"
chmod +x "$GRANT_SCRIPT" 2>/dev/null || true
command -v jq >/dev/null 2>&1 || die "jq is required"
[[ -n "$RANCHER_URL" ]] || die "--rancher-url is required"
[[ -n "$RANCHER_TOKEN" ]] || die "--token is required"
[[ -n "$CLUSTER_NAME" || -n "$CLUSTER_ID" ]] || die "--cluster-name or --cluster-id is required"

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
  local base
  if [[ -f "$GRANTS_FILE" ]]; then
    base="$(cat "$GRANTS_FILE")"
  elif [[ -f "$default_file" ]]; then
    log "Grants catalog not found at $GRANTS_FILE — using built-in default ($default_file)"
    base="$(cat "$default_file")"
  else
    log "No grants catalog; using minimal DEVOPS cluster-owner default"
    base='[{"group":"DEVOPS","role":"cluster-owner","enabled":true,"principal_id":"keycloak_group://DEVOPS","fix_misbound_user":true}]'
  fi
  validate_grants_array "base grants file ($GRANTS_FILE)" "$base"
  printf '%s' "$base"
}

build_devops_patch() {
  local obj='{}'
  if [[ -n "${RANCHER_DEVOPS_ROLE:-}" ]]; then
    validate_role "$RANCHER_DEVOPS_ROLE" "$DEVOPS_GROUP_NAME"
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
    validate_grants_array "--grants-json" "$GRANTS_JSON"
    log "Using --grants-json (full replace, ignoring base file and env patches)"
    printf '%s' "$GRANTS_JSON"
    return 0
  fi

  if [[ "$GRANTS_MODE" == "replace" && -n "${RANCHER_ACCESS_GRANTS:-}" ]]; then
    validate_grants_array "RANCHER_ACCESS_GRANTS" "$RANCHER_ACCESS_GRANTS"
    log "Using RANCHER_ACCESS_GRANTS (replace mode)"
    printf '%s' "$RANCHER_ACCESS_GRANTS"
    return 0
  fi

  local base env_patch devops_patch merged workflow_patch
  base="$(load_base_grants)"
  env_patch="${RANCHER_ACCESS_GRANTS:-[]}"
  devops_patch="$(build_devops_patch)"
  workflow_patch="${WORKFLOW_RANCHER_PATCH:-[]}"

  validate_json_array "RANCHER_ACCESS_GRANTS" "$env_patch"
  validate_json_array "WORKFLOW_RANCHER_PATCH" "$workflow_patch"

  merged="$(jq -c -s "$JQ_MERGE" <(printf '%s' "$base") <(printf '%s' "$env_patch"))"
  if [[ "$devops_patch" != "[]" ]]; then
    merged="$(jq -c -s "$JQ_MERGE" <(printf '%s' "$merged") <(printf '%s' "$devops_patch"))"
    log "Applied DEVOPS env shortcuts (group=$DEVOPS_GROUP_NAME)"
  fi
  if [[ -n "${WORKFLOW_RANCHER_PATCH:-}" && "$WORKFLOW_RANCHER_PATCH" != "[]" ]]; then
    merged="$(jq -c -s "$JQ_MERGE" <(printf '%s' "$merged") <(printf '%s' "$workflow_patch"))"
    log "Applied workflow_dispatch patch (Actions UI selections)"
  fi
  if [[ -n "${RANCHER_ACCESS_GRANTS:-}" ]]; then
    log "Merged RANCHER_ACCESS_GRANTS patch onto base file"
  else
    log "Using base grants from $GRANTS_FILE"
  fi
  validate_grants_array "merged grant plan" "$merged"
  printf '%s' "$merged"
}

GRANTS="$(resolve_grants_json)"
COUNT="$(printf '%s' "$GRANTS" | jq 'length')"
if [[ "$COUNT" -eq 0 ]]; then
  log "No enabled grants to apply (all groups disabled or empty config)"
  exit 0
fi

log "Effective grant plan ($COUNT enabled):"
printf '%s' "$GRANTS" | jq -r '.[] | "  - \(.group): \(.role) (enabled=\(.enabled // true))"'

FAILURES=0
INDEX=0
while IFS= read -r grant; do
  INDEX=$((INDEX + 1))
  GROUP="$(jq -r '.group // empty' <<<"$grant")"
  ROLE="$(jq -r '.role // empty' <<<"$grant")"
  PRINCIPAL_ID="$(jq -r '.principal_id // empty' <<<"$grant")"
  AUTH_PREFIX="$(jq -r '.group_auth_prefix // empty' <<<"$grant")"
  FIX_MISBOUND="$(jq -r '.fix_misbound_user // false' <<<"$grant")"
  ENABLED="$(jq -r '.enabled // true' <<<"$grant")"

  validate_group "$GROUP"
  validate_role "$ROLE" "$GROUP"

  PRINCIPAL_DISPLAY="${PRINCIPAL_ID:-<built from ${AUTH_PREFIX:-$DEFAULT_GROUP_AUTH_PREFIX}>}"
  log "[$INDEX/$COUNT] Grant: group=$GROUP role=$ROLE principal=$PRINCIPAL_DISPLAY fix_misbound=$FIX_MISBOUND enabled=$ENABLED"

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

  if ! "$GRANT_SCRIPT" "${ARGS[@]}"; then
    err "Grant failed for group=$GROUP role=$ROLE"
    FAILURES=$((FAILURES + 1))
  fi
done < <(printf '%s' "$GRANTS" | jq -c '.[]')

if [[ "$FAILURES" -gt 0 ]]; then
  die "$FAILURES grant(s) failed"
fi

log "All $COUNT grant(s) applied successfully."
