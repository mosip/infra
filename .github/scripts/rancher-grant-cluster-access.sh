#!/usr/bin/env bash
#
# rancher-grant-cluster-access.sh - Grant a Keycloak (or other IdP) group access to a Rancher cluster.
#
# When clusters are registered with a personal/service API token, only that principal
# sees the cluster in Rancher UI. This script creates a clusterRoleTemplateBinding so
# an IdP group (e.g. DEVOPS) receives cluster-owner (or another role) without manual UI steps.
#
# Groups can be bound before the downstream cluster finishes importing (pending state).
#
# Requires: bash 4+, curl, jq.

set -euo pipefail

RANCHER_URL="${RANCHER_URL:-}"
RANCHER_TOKEN="${RANCHER_TOKEN:-}"
CLUSTER_NAME="${CLUSTER_NAME:-}"
CLUSTER_ID="${CLUSTER_ID:-}"
GROUP_NAME="${GROUP_NAME:-}"
GROUP_PRINCIPAL_ID="${GROUP_PRINCIPAL_ID:-}"
GROUP_AUTH_PREFIX="${GROUP_AUTH_PREFIX:-}"
ROLE_TEMPLATE_ID="${ROLE_TEMPLATE_ID:-cluster-owner}"
BINDING_NAME="${BINDING_NAME:-}"
INSECURE="${INSECURE:-false}"

usage() {
  cat <<'EOF'
Usage: rancher-grant-cluster-access.sh --rancher-url <url> --token <token> \
  [--cluster-name <name> | --cluster-id <id>] \
  [--group <name> | --group-principal-id <id>] [options]

Required:
  --rancher-url <url>           Rancher base URL (https://rancher.<env>.mosip.net, NO /v3)
  --token <token>               Rancher API bearer token (needs permission to manage cluster RBAC)

Cluster selector (one required):
  --cluster-name <name>         Rancher cluster name
  --cluster-id <id>             Rancher cluster id (e.g. c-m-xxxxx)

Group selector (one required unless GROUP_NAME / GROUP_PRINCIPAL_ID set):
  --group <name>                IdP group name as shown in Rancher (e.g. DEVOPS)
  --group-principal-id <id>     Full principal id (e.g. keycloakoidc_group://DEVOPS)

Optional:
  --role-template <id>          Rancher role template (default: cluster-owner)
  --group-auth-prefix <prefix>  Principal prefix when building group id (default: auto-detect)
  --binding-name <name>         Binding resource name (default: crtb-<group>-<role>)
  --insecure                    Skip TLS verification for Rancher API calls only
  -h, --help                    Show help

Environment (optional):
  GROUP_NAME, GROUP_PRINCIPAL_ID, GROUP_AUTH_PREFIX, ROLE_TEMPLATE_ID, BINDING_NAME

Example:
  rancher-grant-cluster-access.sh \
    --rancher-url https://rancher.mosip.net \
    --token "$RANCHER_TOKEN" \
    --cluster-name dev1 \
    --group DEVOPS \
    --role-template cluster-owner
EOF
}

err() { echo "[rancher-grant][ERROR] $*" >&2; }
die() { err "$*"; exit 1; }
log() { echo "[rancher-grant] $*" >&2; }

require_arg() {
  local flag="$1"
  [[ $# -ge 2 && -n "${2:-}" && "$2" != --* ]] || die "$flag requires a value"
}

urlencode() {
  jq -rn --arg v "$1" '$v|@uri'
}

slugify() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --rancher-url)         require_arg --rancher-url "${2-}";         RANCHER_URL="$2"; shift 2 ;;
    --token)               require_arg --token "${2-}";               RANCHER_TOKEN="$2"; shift 2 ;;
    --cluster-name)        require_arg --cluster-name "${2-}";        CLUSTER_NAME="$2"; shift 2 ;;
    --cluster-id)          require_arg --cluster-id "${2-}";          CLUSTER_ID="$2"; shift 2 ;;
    --group)               require_arg --group "${2-}";               GROUP_NAME="$2"; shift 2 ;;
    --group-principal-id)  require_arg --group-principal-id "${2-}";  GROUP_PRINCIPAL_ID="$2"; shift 2 ;;
    --role-template)       require_arg --role-template "${2-}";       ROLE_TEMPLATE_ID="$2"; shift 2 ;;
    --group-auth-prefix)   require_arg --group-auth-prefix "${2-}";   GROUP_AUTH_PREFIX="$2"; shift 2 ;;
    --binding-name)        require_arg --binding-name "${2-}";        BINDING_NAME="$2"; shift 2 ;;
    --insecure)            INSECURE="true"; shift ;;
    -h|--help)             usage; exit 0 ;;
    *)                     die "Unknown argument: $1 (use --help)" ;;
  esac
done

[[ ${BASH_VERSINFO[0]} -ge 4 ]] || die "bash 4+ is required"
[[ -n "$RANCHER_URL" ]]          || die "--rancher-url is required"
[[ -n "$RANCHER_TOKEN" ]]         || die "--token is required"
[[ -n "$CLUSTER_NAME" || -n "$CLUSTER_ID" ]] || die "--cluster-name or --cluster-id is required"
[[ -n "$GROUP_NAME" || -n "$GROUP_PRINCIPAL_ID" ]] || die "--group or --group-principal-id is required"
command -v curl >/dev/null 2>&1 || die "curl is required"
command -v jq   >/dev/null 2>&1 || die "jq is required"

RANCHER_URL="${RANCHER_URL%/}"
[[ "$RANCHER_URL" =~ ^https:// ]] \
  || die "RANCHER_URL must begin with https:// (got: $RANCHER_URL)"

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

detect_group_auth_prefix() {
  local json provider
  if ! json="$(api GET "/v3/authconfigs")"; then
    log "Could not list auth configs; using default keycloakoidc_group prefix"
    printf '%s' "keycloakoidc_group"
    return 0
  fi
  provider="$(jq -r '
    [.data[]? | select((.enabled // false) == true) | .type] |
    map(select(test("^(keycloakoidc|keycloak|openldap|azuread|activedirectory|okta|github|google)$"))) |
    .[0] // empty
  ' <<<"$json")"
  case "$provider" in
    keycloakoidc)      printf '%s' "keycloakoidc_group" ;;
    keycloak)          printf '%s' "keycloak_group" ;;
    openldap)          printf '%s' "openldap_group" ;;
    azuread)           printf '%s' "azuread_group" ;;
    activedirectory)   printf '%s' "activedirectory_group" ;;
    okta)              printf '%s' "okta_group" ;;
    github)            printf '%s' "github_group" ;;
    google)            printf '%s' "google_group" ;;
    *)
      log "No known external auth provider detected (enabled=$provider); defaulting to keycloakoidc_group"
      printf '%s' "keycloakoidc_group"
      ;;
  esac
}

search_group_principal_id() {
  local name="$1" json principal
  if ! json="$(api POST "/v3/principals?action=search" "$(jq -nc --arg name "$name" '{name: $name, principalType: "grp"}')")"; then
    return 1
  fi
  principal="$(jq -r --arg name "$name" '
    [.data[]? | select((.principalType // "") == "grp" or (.principalType // "") == "group")
      | select((.name // "") == $name or (.loginName // "") == $name or (.displayName // "") == $name)
    ][0].id // empty
  ' <<<"$json")"
  [[ -n "$principal" ]] || return 1
  printf '%s' "$principal"
}

resolve_group_principal_id() {
  local prefix candidate
  if [[ -n "$GROUP_PRINCIPAL_ID" ]]; then
    printf '%s' "$GROUP_PRINCIPAL_ID"
    return 0
  fi

  if candidate="$(search_group_principal_id "$GROUP_NAME" || true)" && [[ -n "$candidate" ]]; then
    log "Resolved group principal via Rancher search: ${candidate}"
    printf '%s' "$candidate"
    return 0
  fi

  if [[ -z "$GROUP_AUTH_PREFIX" ]]; then
    GROUP_AUTH_PREFIX="$(detect_group_auth_prefix)"
    log "Using group auth prefix: ${GROUP_AUTH_PREFIX}"
  fi

  candidate="${GROUP_AUTH_PREFIX}://${GROUP_NAME}"
  log "Using constructed group principal: ${candidate}"
  printf '%s' "$candidate"
}

alternate_group_principal_ids() {
  local prefix="$1" name="$2"
  printf '%s\n' \
    "${prefix}://${name}" \
    "${prefix}:///${name}" \
    "keycloakoidc_group://${name}" \
    "keycloakoidc_group:///${name}" \
    "keycloak_group://${name}" \
    "keycloak_group:///${name}"
}

binding_exists() {
  local principal="$1" json
  if ! json="$(api GET "/v3/clusterroletemplatebindings?clusterId=$(urlencode "$CLUSTER_ID")")"; then
    die "Failed to list cluster role template bindings"
  fi
  jq -e --arg gid "$principal" --arg role "$ROLE_TEMPLATE_ID" '
    (.data // [])[] |
    select((.groupPrincipalId // "") == $gid and (.roleTemplateId // "") == $role)
  ' <<<"$json" >/dev/null
}

create_binding() {
  local principal="$1" body response binding_label
  binding_label="${GROUP_NAME:-${principal##*/}}"
  if [[ -z "$BINDING_NAME" ]]; then
    BINDING_NAME="crtb-$(slugify "$binding_label")-$(slugify "$ROLE_TEMPLATE_ID")"
  fi
  body="$(jq -nc \
    --arg type "clusterRoleTemplateBinding" \
    --arg name "$BINDING_NAME" \
    --arg clusterId "$CLUSTER_ID" \
    --arg groupPrincipalId "$principal" \
    --arg roleTemplateId "$ROLE_TEMPLATE_ID" \
    '{
      type: $type,
      name: $name,
      clusterId: $clusterId,
      groupPrincipalId: $groupPrincipalId,
      roleTemplateId: $roleTemplateId
    }')"

  if response="$(api POST "/v3/clusterroletemplatebindings" "$body")"; then
    jq -r '{id, name, clusterId, groupPrincipalId, roleTemplateId}' <<<"$response" >&2
    return 0
  fi
  return 1
}

if [[ -z "$CLUSTER_ID" ]]; then
  log "Looking up cluster '${CLUSTER_NAME}' in Rancher ..."
  if ! CLUSTER_ID="$(fetch_cluster_id_by_name)"; then
    die "Cluster '$CLUSTER_NAME' not found in Rancher"
  fi
fi
log "Target cluster id=${CLUSTER_ID}"

GROUP_PRINCIPAL_ID="$(resolve_group_principal_id)"
log "Granting role '${ROLE_TEMPLATE_ID}' to group '${GROUP_NAME:-$GROUP_PRINCIPAL_ID}' on cluster '${CLUSTER_ID}' ..."

if binding_exists "$GROUP_PRINCIPAL_ID"; then
  log "Binding already exists for group='${GROUP_PRINCIPAL_ID}' role='${ROLE_TEMPLATE_ID}' (skipping)"
  exit 0
fi

BINDING_NAME=""
if create_binding "$GROUP_PRINCIPAL_ID"; then
  log "Cluster access granted successfully"
  exit 0
fi

if [[ -n "$GROUP_NAME" ]]; then
  prefix="${GROUP_AUTH_PREFIX:-}"
  [[ -z "$prefix" ]] && prefix="$(detect_group_auth_prefix)"
  while IFS= read -r candidate; do
    [[ "$candidate" == "$GROUP_PRINCIPAL_ID" ]] && continue
    log "Retrying with alternate group principal: ${candidate}"
    if binding_exists "$candidate"; then
      log "Binding already exists for group='${candidate}' role='${ROLE_TEMPLATE_ID}' (skipping)"
      exit 0
    fi
    BINDING_NAME=""
    if create_binding "$candidate"; then
      log "Cluster access granted successfully with principal '${candidate}'"
      exit 0
    fi
  done < <(alternate_group_principal_ids "$prefix" "$GROUP_NAME")
fi

die "Failed to create clusterRoleTemplateBinding. Pass --group-principal-id explicitly (copy from an existing cluster member in Rancher UI)."
