#!/usr/bin/env bash
#
# build-rancher-workflow-patch.sh - Build Rancher grant patch from GitHub Actions workflow inputs.
#
# DEVOPS cluster-owner is NOT configured here — it is always applied from
# rancher-access-grants.json (and optional per-env vars). This script only
# controls optional JSON team grants and an extra cluster-owner group.
#
# Environment (set by terraform.yml from workflow_dispatch inputs):
#   WORKFLOW_DEVOPS_GROUP              DEVOPS group name to skip when disabling others (default: DEVOPS)
#   WORKFLOW_GRANT_GROUP_ACCESS        true | false — apply non-DEVOPS groups per JSON merge
#   WORKFLOW_CLUSTER_OWNER_GROUP_ENABLED  true | false — grant cluster-owner to named group
#   WORKFLOW_CLUSTER_OWNER_GROUP       Group name for cluster-owner override
#   WORKFLOW_GRANTS_CATALOG            Path to rancher-access-grants.json (optional)

set -euo pipefail

DEVOPS_GROUP="${WORKFLOW_DEVOPS_GROUP:-DEVOPS}"
GRANT_GROUP_ACCESS="${WORKFLOW_GRANT_GROUP_ACCESS:-false}"
OWNER_ENABLED="${WORKFLOW_CLUSTER_OWNER_GROUP_ENABLED:-false}"
OWNER_GROUP="${WORKFLOW_CLUSTER_OWNER_GROUP:-}"
CATALOG_FILE="${WORKFLOW_GRANTS_CATALOG:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "$CATALOG_FILE" ]]; then
  CATALOG_FILE="${SCRIPT_DIR%/scripts}/config/rancher-access-grants.json"
fi
DEFAULT_CATALOG="${SCRIPT_DIR}/rancher-access-grants.default.json"

command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 1; }
if [[ ! -f "$CATALOG_FILE" ]]; then
  if [[ -f "$DEFAULT_CATALOG" ]]; then
    echo "[build-rancher-workflow-patch] Catalog not found at $CATALOG_FILE — using $DEFAULT_CATALOG" >&2
    CATALOG_FILE="$DEFAULT_CATALOG"
  else
    echo "Missing grants catalog: $CATALOG_FILE" >&2
    exit 1
  fi
fi

patch='[]'

add_entry() {
  local group="$1" role="$2" enabled="$3" fix="${4:-false}"
  local extra='{}'
  if [[ "$fix" == "true" ]]; then
    extra='{"fix_misbound_user":true}'
  fi
  patch="$(jq -c \
    --arg g "$group" --arg r "$role" --argjson e "$enabled" --argjson x "$extra" \
    '. + [({group:$g, role:$r, enabled:$e} + $x)]' <<<"$patch")"
}

bool_enabled() {
  case "${1,,}" in
    true|1|yes) echo true ;;
    *) echo false ;;
  esac
}

catalog_role_for() {
  local group="$1"
  jq -r --arg g "$group" '
    .[] | select(.group == $g) | .role // empty
  ' "$CATALOG_FILE" | head -n1
}

# When grant-group-access is off, disable every non-DEVOPS catalog group for this run.
# DEVOPS stays cluster-owner from the base JSON layer (not patched here).
if [[ "$(bool_enabled "$GRANT_GROUP_ACCESS")" != "true" ]]; then
  while IFS= read -r group; do
    [[ -n "$group" ]] || continue
    [[ "$group" == "$DEVOPS_GROUP" ]] && continue
    role="$(catalog_role_for "$group")"
    [[ -n "$role" ]] || role="cluster-member"
    add_entry "$group" "$role" false false
  done < <(jq -r '.[].group' "$CATALOG_FILE")
fi

# Optional extra cluster-owner (DEVOPS remains owner from base JSON — both can be owners).
if [[ "$(bool_enabled "$OWNER_ENABLED")" == "true" ]]; then
  g="${OWNER_GROUP// /}"
  if [[ -n "$g" ]]; then
    if jq -e --arg g "$g" 'map(select(.group == $g)) | length > 0' <<<"$patch" >/dev/null; then
      patch="$(jq -c --arg g "$g" \
        'map(if .group == $g then .role = "cluster-owner" | .enabled = true else . end)' <<<"$patch")"
    else
      fix="false"
      [[ "$g" == "$DEVOPS_GROUP" ]] && fix="true"
      add_entry "$g" "cluster-owner" true "$fix"
    fi
  fi
fi

printf '%s' "$patch"
