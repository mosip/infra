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

log() { echo "[build-rancher-workflow-patch] $*" >&2; }
die() { log "ERROR: $*"; exit 1; }

trim_whitespace() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

command -v jq >/dev/null 2>&1 || die "jq is required"
if [[ ! -f "$CATALOG_FILE" ]]; then
  RESOLVE_SCRIPT="${SCRIPT_DIR}/resolve-rancher-grants-catalog.sh"
  if [[ -x "$RESOLVE_SCRIPT" ]]; then
    CATALOG_FILE="$("$RESOLVE_SCRIPT")"
  elif [[ -f "$DEFAULT_CATALOG" ]]; then
    log "Catalog not found — using $DEFAULT_CATALOG"
    CATALOG_FILE="$DEFAULT_CATALOG"
  else
    die "Missing grants catalog and no resolver/default script"
  fi
fi

jq empty "$CATALOG_FILE" || die "Invalid JSON catalog: $CATALOG_FILE"

dup="$(jq -r '.[].group' "$CATALOG_FILE" | sort | uniq -d)"
if [[ -n "$dup" ]]; then
  die "$(printf 'Duplicate group names in catalog:\n%s' "$dup")"
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
    '. + [
      (
        {
          group: $g,
          role: $r,
          enabled: $e
        } + $x
      )
    ]' <<<"$patch")"
}

bool_enabled() {
  case "${1,,}" in
    true|1|yes) echo true ;;
    *) echo false ;;
  esac
}

GRANT_ENABLED="$(bool_enabled "$GRANT_GROUP_ACCESS")"
OWNER_ENABLED_BOOL="$(bool_enabled "$OWNER_ENABLED")"

# When grant-group-access is checked, enable every non-DEVOPS team from the catalog
# (roles/principal_id come from JSON — overrides enabled:false defaults in the file).
# When unchecked, disable non-DEVOPS teams for this run (DEVOPS always from base JSON).
while IFS=$'\t' read -r group role; do
  [[ -n "$group" ]] || continue
  [[ "$group" == "$DEVOPS_GROUP" ]] && continue
  [[ -n "$role" ]] || role="cluster-member"
  add_entry "$group" "$role" "$GRANT_ENABLED" false
done < <(jq -r '.[] | [.group, (.role // "cluster-member")] | @tsv' "$CATALOG_FILE")

# Optional extra cluster-owner (DEVOPS remains owner from base JSON — both can be owners).
if [[ "$OWNER_ENABLED_BOOL" == "true" ]]; then
  g="$(trim_whitespace "$OWNER_GROUP")"
  if [[ -n "$g" ]]; then
    if jq -e --arg g "$g" 'map(select(.group == $g)) | length > 0' <<<"$patch" >/dev/null; then
      patch="$(jq -c --arg g "$g" \
        'map(if .group == $g then .role = "cluster-owner" | .enabled = true else . end)' <<<"$patch")"
    else
      fix="false"
      # Repair legacy DEVOPS principal bindings when granting cluster-owner to DEVOPS again.
      [[ "$g" == "$DEVOPS_GROUP" ]] && fix="true"
      add_entry "$g" "cluster-owner" true "$fix"
    fi
  fi
fi

printf '%s' "$patch"
