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
LIST_BINDINGS="${LIST_BINDINGS:-false}"
FIX_MISBOUND_USER="${FIX_MISBOUND_USER:-false}"

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
  --group-principal-id <id>     Full principal id (e.g. keycloak_group://DEVOPS)
  --list-bindings               Print cluster role bindings and exit
  --fix-misbound-user           Remove wrong DEVOPS bindings (user principal, triple-slash group id, etc.)

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
    --role-template cluster-owner \
    --group-principal-id keycloak_group://DEVOPS \
    --fix-misbound-user
EOF
}

LAST_HTTP_STATUS=""
DELETIONS_PERFORMED="false"
DELETED_BINDING_IDS=()
CLUSTER_BINDINGS_JSON=""
CLUSTER_BINDINGS_CLUSTER_ID=""

err() { echo "[rancher-grant][ERROR] $*" >&2; }
die() { err "$*"; exit 1; }
log() { echo "[rancher-grant] $*" >&2; }

forbidden_hint() {
  err "API token lacks permission to manage cluster members (clusterRoleTemplateBindings)."
  err "Use a Rancher admin or service-account API token with cluster membership rights."
  err "Store it as RANCHER_API_TOKEN in the GitHub environment secret (not a personal restricted token)."
}

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
    --list-bindings)       LIST_BINDINGS="true"; shift ;;
    --fix-misbound-user)   FIX_MISBOUND_USER="true"; shift ;;
    --insecure)            INSECURE="true"; shift ;;
    -h|--help)             usage; exit 0 ;;
    *)                     die "Unknown argument: $1 (use --help)" ;;
  esac
done

[[ ${BASH_VERSINFO[0]} -ge 4 ]] || die "bash 4+ is required"
[[ -n "$RANCHER_URL" ]]          || die "--rancher-url is required"
[[ -n "$RANCHER_TOKEN" ]]         || die "--token is required"
[[ -n "$CLUSTER_NAME" || -n "$CLUSTER_ID" ]] || die "--cluster-name or --cluster-id is required"
if [[ "$LIST_BINDINGS" != "true" ]]; then
  [[ -n "$GROUP_NAME" || -n "$GROUP_PRINCIPAL_ID" ]] || die "--group or --group-principal-id is required"
fi
command -v curl >/dev/null 2>&1 || die "curl is required"
command -v jq   >/dev/null 2>&1 || die "jq is required"

if [[ -z "$GROUP_NAME" && -n "$GROUP_PRINCIPAL_ID" ]]; then
  GROUP_NAME="${GROUP_PRINCIPAL_ID##*/}"
fi

RANCHER_URL="${RANCHER_URL%/}"
[[ "$RANCHER_URL" =~ ^https:// ]] \
  || die "RANCHER_URL must begin with https:// (got: $RANCHER_URL)"

api() {
  local method="$1" path="$2" body="${3:-}"
  local tmp status curl_args=()
  tmp="$(mktemp "${TMPDIR:-/tmp}/rancher-api.XXXXXX")"

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
    LAST_HTTP_STATUS=""
    err "Rancher API ${method} ${path}: curl failed"
    [[ -s "$tmp" ]] && cat "$tmp" >&2
    rm -f "$tmp"
    return 1
  fi

  LAST_HTTP_STATUS="$status"
  if [[ ! "$status" =~ ^[0-9]+$ ]] || (( status >= 400 )); then
    err "Rancher API ${method} ${path} failed with HTTP ${status:-unknown}"
    [[ -s "$tmp" ]] && cat "$tmp" >&2
    [[ "$status" == "403" ]] && forbidden_hint
    rm -f "$tmp"
    return 1
  fi

  cat "$tmp"
  rm -f "$tmp"
}

invalidate_bindings_cache() {
  CLUSTER_BINDINGS_JSON=""
  CLUSTER_BINDINGS_CLUSTER_ID=""
}

fetch_cluster_bindings() {
  if [[ "$CLUSTER_BINDINGS_CLUSTER_ID" == "$CLUSTER_ID" && -n "$CLUSTER_BINDINGS_JSON" ]]; then
    printf '%s' "$CLUSTER_BINDINGS_JSON"
    return 0
  fi
  if ! CLUSTER_BINDINGS_JSON="$(api GET "/v3/clusterroletemplatebindings?clusterId=$(urlencode "$CLUSTER_ID")")"; then
    return 1
  fi
  CLUSTER_BINDINGS_CLUSTER_ID="$CLUSTER_ID"
  printf '%s' "$CLUSTER_BINDINGS_JSON"
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
    log "Could not list auth configs; defaulting to keycloak_group (MOSIP Keycloak SAML)"
    printf '%s' "keycloak_group"
    return 0
  fi
  provider="$(jq -r '
    [.data[]? |
      select((.enabled // false) == true) |
      (.type // "") | sub("Config$"; "")
    ] |
    map(select(. != "" and test("^[A-Za-z][A-Za-z0-9]*$"))) |
    .[0] // empty
  ' <<<"$json")"
  if [[ -n "$provider" ]]; then
    log "Detected auth provider: ${provider}"
    printf '%s' "${provider}_group"
    return 0
  fi
  log "No enabled external auth provider detected; defaulting to keycloak_group"
  printf '%s' "keycloak_group"
}

is_group_principal() {
  local principal="$1"
  [[ "$principal" == *"_group://"* ]]
}

validate_group_principal() {
  local principal="$1"
  if is_group_principal "$principal"; then
    return 0
  fi
  err "Principal is not a group (expected id containing '_group://'): ${principal}"
  return 1
}

constructed_group_principal_ids() {
  local prefix="$1" name="$2"
  printf '%s\n' \
    "${prefix}://${name}" \
    "${prefix}:///${name}"
}

resolve_group_principal_id() {
  local candidate
  if [[ -n "$GROUP_PRINCIPAL_ID" ]]; then
    validate_group_principal "$GROUP_PRINCIPAL_ID" \
      || die "GROUP_PRINCIPAL_ID must be a group principal (e.g. keycloak_group://DEVOPS)"
    printf '%s' "$GROUP_PRINCIPAL_ID"
    return 0
  fi

  if [[ -z "$GROUP_AUTH_PREFIX" ]]; then
    GROUP_AUTH_PREFIX="$(detect_group_auth_prefix)"
    log "Using group auth prefix: ${GROUP_AUTH_PREFIX}"
  fi

  IFS= read -r candidate < <(constructed_group_principal_ids "$GROUP_AUTH_PREFIX" "$GROUP_NAME")
  [[ -n "$candidate" ]] || die "Could not resolve a group principal for '${GROUP_NAME}'"
  log "Using constructed group principal: ${candidate}"
  printf '%s' "$candidate"
}

alternate_group_principal_ids() {
  local prefix="$1" name="$2"
  constructed_group_principal_ids "$prefix" "$name"
  printf '%s\n' \
    "keycloakoidc_group://${name}" \
    "keycloakoidc_group:///${name}" \
    "keycloak_group://${name}" \
    "keycloak_group:///${name}"
}

delete_binding_by_id() {
  local id="$1"
  if api DELETE "/v3/clusterroletemplatebindings/$(urlencode "$id")" >/dev/null; then
    invalidate_bindings_cache
    DELETIONS_PERFORMED="true"
    DELETED_BINDING_IDS+=("$id")
    return 0
  fi
  return 1
}

unique_binding_suffix() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 4
  else
    printf '%04x%04x' "$((RANDOM % 65536))" "$((RANDOM % 65536))"
  fi
}

planned_binding_name() {
  local binding_label="${GROUP_NAME:-${GROUP_PRINCIPAL_ID##*/}}"
  if [[ -n "$BINDING_NAME" ]]; then
    printf '%s' "$BINDING_NAME"
    return 0
  fi
  if [[ "$DELETIONS_PERFORMED" == "true" ]]; then
    printf 'crtb-%s-%s-%s' \
      "$(slugify "$binding_label")" \
      "$(slugify "$ROLE_TEMPLATE_ID")" \
      "$(unique_binding_suffix)"
    return 0
  fi
  printf 'crtb-%s-%s' "$(slugify "$binding_label")" "$(slugify "$ROLE_TEMPLATE_ID")"
}

wait_for_deleted_bindings() {
  local id json attempt max_attempts=15 sleep_seconds=1
  (( ${#DELETED_BINDING_IDS[@]} == 0 )) && return 0
  log "Waiting for Rancher to remove ${#DELETED_BINDING_IDS[@]} deleted binding(s) ..."
  for (( attempt=1; attempt<=max_attempts; attempt++ )); do
    if ! json="$(fetch_cluster_bindings)"; then
      err "Could not verify binding cleanup (attempt ${attempt}/${max_attempts})"
      sleep "$sleep_seconds"
      continue
    fi
    for id in "${DELETED_BINDING_IDS[@]}"; do
      if jq -e --arg id "$id" '.data[]? | select(.id == $id)' <<<"$json" >/dev/null; then
        log "Binding ${id} still present (attempt ${attempt}/${max_attempts}) ..."
        sleep "$sleep_seconds"
        continue 2
      fi
    done
    log "Deleted bindings no longer listed by Rancher"
    return 0
  done
  err "Timed out waiting for Rancher to remove deleted bindings; continuing anyway"
  return 0
}

update_group_binding() {
  local id="$1" name="$2" principal="$3" body
  body="$(jq -nc \
    --arg type "clusterRoleTemplateBinding" \
    --arg id "$id" \
    --arg name "$name" \
    --arg clusterId "$CLUSTER_ID" \
    --arg groupPrincipalId "$principal" \
    --arg roleTemplateId "$ROLE_TEMPLATE_ID" \
    '{
      type: $type,
      id: $id,
      name: $name,
      clusterId: $clusterId,
      groupPrincipalId: $groupPrincipalId,
      roleTemplateId: $roleTemplateId
    }')"
  if api PUT "/v3/clusterroletemplatebindings/$(urlencode "$id")" "$body" >/dev/null; then
    invalidate_bindings_cache
    return 0
  fi
  return 1
}

remove_misbound_user_bindings() {
  local json id principal
  if ! json="$(fetch_cluster_bindings)"; then
    err "Could not list bindings while checking for misbound user entries"
    return 1
  fi
  while IFS=$'\t' read -r id principal; do
    [[ -n "$id" ]] || continue
    log "Removing misbound user clusterRoleTemplateBinding id=${id} userPrincipalId=${principal}"
    delete_binding_by_id "$id" || err "Failed to delete binding ${id}"
  done < <(jq -r --arg name "$GROUP_NAME" '
    [.data[]? |
      select((.userPrincipalId // "") != "") |
      select((.groupPrincipalId // "") == "") |
      select(
        (.userPrincipalId // "") | endswith("/" + $name) or endswith("://" + $name) or endswith($name)
      ) |
      [.id, .userPrincipalId] |
      @tsv
    ] | .[]
  ' <<<"$json")
}

reconcile_stale_group_bindings() {
  local target="$1" json rows id name principal role
  [[ -n "$GROUP_NAME" ]] || return 0
  if ! json="$(fetch_cluster_bindings)"; then
    err "Could not list bindings while reconciling stale group entries"
    return 1
  fi
  while IFS=$'\t' read -r id name principal role; do
    [[ -n "$id" ]] || continue
    if [[ "$role" == "$ROLE_TEMPLATE_ID" ]]; then
      log "Repairing group clusterRoleTemplateBinding id=${id} groupPrincipalId=${principal} -> ${target}"
      if ! update_group_binding "$id" "$name" "$target"; then
        log "Repair failed; deleting binding id=${id}"
        delete_binding_by_id "$id" || err "Failed to delete binding ${id}"
      fi
      continue
    fi
    log "Removing stale group clusterRoleTemplateBinding id=${id} groupPrincipalId=${principal} role=${role}"
    delete_binding_by_id "$id" || err "Failed to delete binding ${id}"
  done < <(jq -r --arg target "$target" --arg name "$GROUP_NAME" --arg role "$ROLE_TEMPLATE_ID" '
    [.data[]? |
      select((.groupPrincipalId // "") != "") |
      select((.groupPrincipalId // "") != $target) |
      select(
        (.groupPrincipalId // "") as $p |
        ($p | endswith("_group://" + $name)) or
        ($p | endswith("_group:///" + $name)) or
        ($p | endswith("_user://" + $name)) or
        ($p | endswith("_user:///" + $name))
      ) |
      [.id, .name, .groupPrincipalId, .roleTemplateId] |
      @tsv
    ] | .[]
  ' <<<"$json")
}

remove_stale_role_bindings() {
  local target="$1" json id role
  if ! json="$(fetch_cluster_bindings)"; then
    err "Could not list bindings while checking for stale role entries"
    return 1
  fi
  while IFS=$'\t' read -r id role; do
    [[ -n "$id" ]] || continue
    log "Removing stale role clusterRoleTemplateBinding id=${id} groupPrincipalId=${target} role=${role}"
    delete_binding_by_id "$id" || err "Failed to delete binding ${id}"
  done < <(jq -r --arg target "$target" --arg role "$ROLE_TEMPLATE_ID" '
    [.data[]? |
      select((.groupPrincipalId // "") == $target) |
      select((.roleTemplateId // "") != $role) |
      [.id, .roleTemplateId] |
      @tsv
    ] | .[]
  ' <<<"$json")
}

binding_exists() {
  local principal="$1" json
  if ! json="$(fetch_cluster_bindings)"; then
    die "Failed to list cluster role template bindings"
  fi
  jq -e --arg gid "$principal" --arg role "$ROLE_TEMPLATE_ID" '
    (.data // [])[] |
    select((.groupPrincipalId // "") == $gid and (.roleTemplateId // "") == $role)
  ' <<<"$json" >/dev/null
}

list_cluster_bindings() {
  local json
  if ! json="$(fetch_cluster_bindings)"; then
    die "Failed to list cluster role template bindings"
  fi
  jq '[.data[]? | {
    id,
    name,
    roleTemplateId,
    groupPrincipalId,
    userPrincipalId,
    userId
  }]' <<<"$json"
}

log_cluster_bindings() {
  log "Current clusterRoleTemplateBindings on ${CLUSTER_ID}:"
  list_cluster_bindings | jq -c '.[]' >&2 || true
}

create_binding() {
  local principal="$1" body response binding_label attempt max_attempts=10
  validate_group_principal "$principal" || return 1
  binding_label="${GROUP_NAME:-${principal##*/}}"
  if [[ -z "$BINDING_NAME" ]]; then
    BINDING_NAME="$(planned_binding_name)"
  fi

  for (( attempt=1; attempt<=max_attempts; attempt++ )); do
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
      invalidate_bindings_cache
      jq -r '{id, name, clusterId, groupPrincipalId, roleTemplateId}' <<<"$response" >&2
      return 0
    fi
    if [[ "${LAST_HTTP_STATUS:-}" == "403" ]]; then
      return 2
    fi
    if [[ "${LAST_HTTP_STATUS:-}" == "409" ]]; then
      BINDING_NAME="crtb-$(slugify "$binding_label")-$(slugify "$ROLE_TEMPLATE_ID")-$(unique_binding_suffix)"
      log "Binding name conflict (attempt ${attempt}/${max_attempts}); retrying as '${BINDING_NAME}' ..."
      sleep 1
      continue
    fi
    return 1
  done
  [[ "${LAST_HTTP_STATUS:-}" == "409" ]] && return 3
  return 1
}

retry_alternate_principals() {
  local auth_prefix="${GROUP_AUTH_PREFIX:-}" create_status=0 candidate
  [[ -z "$auth_prefix" ]] && auth_prefix="$(detect_group_auth_prefix)"
  while IFS= read -r candidate; do
    [[ "$candidate" == "$GROUP_PRINCIPAL_ID" ]] && continue
    log "Retrying with alternate group principal: ${candidate}"
    if binding_exists "$candidate"; then
      log "Binding already exists for group='${candidate}' role='${ROLE_TEMPLATE_ID}' (skipping)"
      exit 0
    fi
    BINDING_NAME=""
    create_status=0
    create_binding "$candidate" || create_status=$?
    if (( create_status == 0 )); then
      log "Cluster access granted successfully with principal '${candidate}'"
      log_cluster_bindings
      exit 0
    fi
    if (( create_status == 2 )); then
      die "Cannot grant cluster access: Rancher API token is forbidden from managing cluster members."
    fi
    if (( create_status == 3 )); then
      die "Cannot grant cluster access: Rancher rejected all generated binding names; re-run the workflow in a few minutes."
    fi
  done < <(alternate_group_principal_ids "$auth_prefix" "$GROUP_NAME")
}

if [[ -z "$CLUSTER_ID" ]]; then
  log "Looking up cluster '${CLUSTER_NAME}' in Rancher ..."
  if ! CLUSTER_ID="$(fetch_cluster_id_by_name)"; then
    die "Cluster '$CLUSTER_NAME' not found in Rancher"
  fi
fi
log "Target cluster id=${CLUSTER_ID}"

if [[ "$LIST_BINDINGS" == "true" ]]; then
  list_cluster_bindings
  exit 0
fi

GROUP_PRINCIPAL_ID="$(resolve_group_principal_id)"
validate_group_principal "$GROUP_PRINCIPAL_ID" \
  || die "Refusing to bind a non-group principal: ${GROUP_PRINCIPAL_ID}"

if [[ "$FIX_MISBOUND_USER" == "true" && -n "$GROUP_NAME" ]]; then
  remove_misbound_user_bindings || true
  reconcile_stale_group_bindings "$GROUP_PRINCIPAL_ID" || true
  remove_stale_role_bindings "$GROUP_PRINCIPAL_ID" || true
  if [[ "$DELETIONS_PERFORMED" == "true" ]]; then
    wait_for_deleted_bindings
  fi
fi

log "Granting role '${ROLE_TEMPLATE_ID}' to group '${GROUP_NAME:-$GROUP_PRINCIPAL_ID}' on cluster '${CLUSTER_ID}' ..."

if binding_exists "$GROUP_PRINCIPAL_ID"; then
  log "Binding already exists for group='${GROUP_PRINCIPAL_ID}' role='${ROLE_TEMPLATE_ID}' (skipping)"
  log_cluster_bindings
  exit 0
fi

BINDING_NAME=""
create_status=0
create_binding "$GROUP_PRINCIPAL_ID" || create_status=$?
if (( create_status == 0 )); then
  log "Cluster access granted successfully"
  log_cluster_bindings
  exit 0
fi
if (( create_status == 2 )); then
  die "Cannot grant cluster access: Rancher API token is forbidden from managing cluster members."
fi
if (( create_status == 3 )); then
  die "Cannot grant cluster access: Rancher rejected all generated binding names; re-run the workflow in a few minutes."
fi

if (( create_status == 1 )) && [[ "${LAST_HTTP_STATUS:-}" != "409" ]] && [[ -n "$GROUP_NAME" ]]; then
  retry_alternate_principals
fi

die "Failed to create clusterRoleTemplateBinding. Set RANCHER_GROUP_PRINCIPAL_ID=keycloak_group://DEVOPS (or pass --group-principal-id) and ensure RANCHER_API_TOKEN can manage cluster members."
