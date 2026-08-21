#!/usr/bin/env bash
#
# rancher-grant-cluster-access.sh - Rancher cluster RBAC (batch apply, single grant, workflow patch).
#
# Subcommands:
#   apply         Merge grants catalog + env/workflow patches; apply all enabled teams (CI default)
#   grant-one     Grant one IdP group one role on one cluster (manual debugging)
#   list-bindings List clusterRoleTemplateBindings for a cluster
#   build-patch   Print WORKFLOW_RANCHER_PATCH JSON (apply runs this internally when needed)
#
# Legacy: first argument --rancher-url is treated as grant-one (no subcommand).
#
# Requires: bash 4+, curl, jq.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_GRANTS_FILE="${SCRIPT_DIR%/scripts}/config/rancher-access-grants.json"
GRANTS_FILE="${GRANTS_FILE:-$DEFAULT_GRANTS_FILE}"
GRANTS_JSON="${GRANTS_JSON:-}"
GRANTS_MODE="${GRANTS_MODE:-merge}"
DEFAULT_GROUP_AUTH_PREFIX="${DEFAULT_GROUP_AUTH_PREFIX:-keycloak_group}"
DEVOPS_GROUP_NAME="${RANCHER_DEVOPS_GROUP:-DEVOPS}"

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
Usage:
  rancher-grant-cluster-access.sh apply --rancher-url <url> --token <token> \
    [--cluster-name <name> | --cluster-id <id>] [--grants-file <path>] [options]

  rancher-grant-cluster-access.sh grant-one --rancher-url <url> --token <token> \
    [--cluster-name <name> | --cluster-id <id>] \
    [--group <name> | --group-principal-id <id>] [options]

  rancher-grant-cluster-access.sh list-bindings --rancher-url <url> --token <token> \
    [--cluster-name <name> | --cluster-id <id>]

  rancher-grant-cluster-access.sh build-patch [--grants-file <path>]

Subcommands:
  apply         Apply enabled grants from catalog + env/workflow patches (CI default)
  grant-one     Grant one group one role on one cluster
  list-bindings Print clusterRoleTemplateBindings JSON
  build-patch   Print WORKFLOW_RANCHER_PATCH JSON

Environment (batch): RANCHER_ACCESS_GRANTS, RANCHER_DEVOPS_*, WORKFLOW_*, WORKFLOW_RANCHER_PATCH
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

parse_common_args() {
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
      --grants-file)         require_arg --grants-file "${2-}";         GRANTS_FILE="$2"; shift 2 ;;
      --grants-json)         require_arg --grants-json "${2-}";         GRANTS_JSON="$2"; shift 2 ;;
      --grants-mode)         require_arg --grants-mode "${2-}";         GRANTS_MODE="$2"; shift 2 ;;
      --default-group-auth-prefix) require_arg --default-group-auth-prefix "${2-}"; DEFAULT_GROUP_AUTH_PREFIX="$2"; shift 2 ;;
      --fix-misbound-user)   FIX_MISBOUND_USER="true"; shift ;;
      --insecure)            INSECURE="true"; shift ;;
      -h|--help)             usage; exit 0 ;;
      *)                     die "Unknown argument: $1 (use --help)" ;;
    esac
  done
}

validate_cluster_connection() {
  [[ ${BASH_VERSINFO[0]} -ge 4 ]] || die "bash 4+ is required"
  [[ -n "$RANCHER_URL" ]]          || die "--rancher-url is required"
  [[ -n "$RANCHER_TOKEN" ]]         || die "--token is required"
  [[ -n "$CLUSTER_NAME" || -n "$CLUSTER_ID" ]] || die "--cluster-name or --cluster-id is required"
  command -v curl >/dev/null 2>&1 || die "curl is required"
  command -v jq   >/dev/null 2>&1 || die "jq is required"
  RANCHER_URL="${RANCHER_URL%/}"
  [[ "$RANCHER_URL" =~ ^https:// ]] \
    || die "RANCHER_URL must begin with https:// (got: $RANCHER_URL)"
}

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
    invalidate_bindings_cache
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
  local target="$1" json id name principal role
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
      return 0
    fi
    BINDING_NAME=""
    create_status=0
    create_binding "$candidate" || create_status=$?
    if (( create_status == 0 )); then
      log "Cluster access granted successfully with principal '${candidate}'"
      log_cluster_bindings
      return 0
    fi
    if (( create_status == 2 )); then
      err "Cannot grant cluster access: Rancher API token is forbidden from managing cluster members."
      return 1
    fi
    if (( create_status == 3 )); then
      err "Cannot grant cluster access: Rancher rejected all generated binding names; re-run the workflow in a few minutes."
      return 1
    fi
  done < <(alternate_group_principal_ids "$auth_prefix" "$GROUP_NAME")
  return 1
}

reset_single_grant_state() {
  DELETIONS_PERFORMED="false"
  DELETED_BINDING_IDS=()
  BINDING_NAME=""
}

run_single_grant() {
  local create_status=0

  if [[ -z "$CLUSTER_ID" ]]; then
    log "Looking up cluster '${CLUSTER_NAME}' in Rancher ..."
    if ! CLUSTER_ID="$(fetch_cluster_id_by_name)"; then
      err "Cluster '$CLUSTER_NAME' not found in Rancher"
      return 1
    fi
  fi
  log "Target cluster id=${CLUSTER_ID}"

  if [[ "$LIST_BINDINGS" == "true" ]]; then
    list_cluster_bindings
    return 0
  fi

  GROUP_PRINCIPAL_ID="$(resolve_group_principal_id)"
  validate_group_principal "$GROUP_PRINCIPAL_ID" \
    || { err "Refusing to bind a non-group principal: ${GROUP_PRINCIPAL_ID}"; return 1; }

  if [[ "$FIX_MISBOUND_USER" == "true" && -n "$GROUP_NAME" ]]; then
    remove_misbound_user_bindings \
      || { err "Failed while removing misbound user bindings for group '$GROUP_NAME'"; return 1; }
    reconcile_stale_group_bindings "$GROUP_PRINCIPAL_ID" \
      || { err "Failed while reconciling stale group bindings for group '$GROUP_NAME'"; return 1; }
    remove_stale_role_bindings "$GROUP_PRINCIPAL_ID" \
      || { err "Failed while removing stale role bindings for group '$GROUP_NAME'"; return 1; }
    if [[ "$DELETIONS_PERFORMED" == "true" ]]; then
      wait_for_deleted_bindings
    fi
  fi

  validate_role_template_exists "$ROLE_TEMPLATE_ID" "${GROUP_NAME:-$GROUP_PRINCIPAL_ID}" \
    || return 1

  log "Granting role '${ROLE_TEMPLATE_ID}' to group '${GROUP_NAME:-$GROUP_PRINCIPAL_ID}' on cluster '${CLUSTER_ID}' ..."

  if binding_exists "$GROUP_PRINCIPAL_ID"; then
    log "Binding already exists for group='${GROUP_PRINCIPAL_ID}' role='${ROLE_TEMPLATE_ID}' (skipping)"
    log_cluster_bindings
    return 0
  fi

  BINDING_NAME=""
  create_status=0
  create_binding "$GROUP_PRINCIPAL_ID" || create_status=$?
  if (( create_status == 0 )); then
    log "Cluster access granted successfully"
    log_cluster_bindings
    return 0
  fi
  if (( create_status == 2 )); then
    err "Cannot grant cluster access: Rancher API token is forbidden from managing cluster members."
    return 1
  fi
  if (( create_status == 3 )); then
    err "Cannot grant cluster access: Rancher rejected all generated binding names; re-run the workflow in a few minutes."
    return 1
  fi

  if (( create_status == 1 )) && [[ "${LAST_HTTP_STATUS:-}" != "409" ]] && [[ -n "$GROUP_NAME" ]]; then
    retry_alternate_principals
    return $?
  fi

  err "Failed to create clusterRoleTemplateBinding for group '${GROUP_NAME:-$GROUP_PRINCIPAL_ID}'"
  return 1
}

bool_enabled() {
  case "$1" in
    [tT][rR][uU][eE]|1|[yY][eE][sS]) echo true ;;
    *) echo false ;;
  esac
}

trim_whitespace() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

build_workflow_patch() {
  local catalog_file="${1:-${WORKFLOW_GRANTS_CATALOG:-$GRANTS_FILE}}"
  local devops_group="${WORKFLOW_DEVOPS_GROUP:-DEVOPS}"
  local grant_enabled owner_enabled_bool patch dup g extra

  command -v jq >/dev/null 2>&1 || die "jq is required"
  [[ -f "$catalog_file" ]] || die "Missing grants catalog: $catalog_file"
  jq empty "$catalog_file" || die "Invalid JSON catalog: $catalog_file"

  dup="$(jq -r '.[].group' "$catalog_file" | sort | uniq -d)"
  if [[ -n "$dup" ]]; then
    die "$(printf 'Duplicate group names in catalog:\n%s' "$dup")"
  fi

  grant_enabled="$(bool_enabled "${WORKFLOW_GRANT_GROUP_ACCESS:-false}")"
  owner_enabled_bool="$(bool_enabled "${WORKFLOW_CLUSTER_OWNER_GROUP_ENABLED:-false}")"

  patch="$(jq -c --arg devops "$devops_group" --argjson enabled "$grant_enabled" '
    map(
      select(.group != null and .group != "" and .group != $devops) |
      {
        group: .group,
        role: (if .role == null or .role == "" then "cluster-member" else .role end),
        enabled: $enabled
      }
    )
  ' "$catalog_file")"

  if [[ "$owner_enabled_bool" == "true" ]]; then
    g="$(trim_whitespace "${WORKFLOW_CLUSTER_OWNER_GROUP:-}")"
    if [[ -n "$g" ]]; then
      if jq -e --arg g "$g" 'map(select(.group == $g)) | length > 0' <<<"$patch" >/dev/null; then
        patch="$(jq -c --arg g "$g" \
          'map(if .group == $g then .role = "cluster-owner" | .enabled = true else . end)' <<<"$patch")"
      else
        extra='{}'
        [[ "$g" == "$devops_group" ]] && extra='{"fix_misbound_user":true}'
        patch="$(jq -c --arg g "$g" --argjson x "$extra" \
          '. + [{group: $g, role: "cluster-owner", enabled: true} + $x]' <<<"$patch")"
      fi
    fi
  fi

  printf '%s' "$patch"
}

JQ_MERGE='
  def enabled_grant:
    if has("enabled") then .enabled == true else false end;
  def to_map:
    map(select((.group // "") != "")) | map({(.group): .}) | add // {};
  def from_maps($bm; $om):
    (($bm | keys) + ($om | keys) | unique) as $keys
    | [$keys[] | ($bm[.] // {}) * ($om[.] // {}) | select(enabled_grant)];
  .[0] as $base | .[1] as $patch | from_maps($base | to_map; $patch | to_map)
'

validate_role() {
  local role="$1" group="$2"
  [[ -n "$role" ]] || die "Grant for group '$group' has empty role"
  if [[ "$role" =~ ^(cluster-[A-Za-z0-9-]+|rt-[A-Za-z0-9-]+)$ ]]; then
    return 0
  fi
  die "Invalid role '$role' for group '$group' (expected cluster-* or rt-* template id; see .github/config/README.md)"
}

role_template_exists() {
  local role="$1" json
  if ! json="$(api GET "/v3/roletemplates/$(urlencode "$role")")"; then
    return 1
  fi
  jq -e --arg id "$role" '(.id // "") == $id' <<<"$json" >/dev/null 2>&1
}

validate_role_template_exists() {
  local role="$1" group="$2"
  if role_template_exists "$role"; then
    return 0
  fi
  err "Role template '$role' for group '$group' was not found in Rancher."
  err "Use Rancher UI → Users & Authentication → Roles → Cluster, or:"
  err "  curl -sS -H \"Authorization: Bearer \$TOKEN\" \"\${RANCHER_URL}/v3/roletemplates\" | jq '.data[] | {id, name}'"
  err "Override per environment via GitHub variable RANCHER_ACCESS_GRANTS (see .github/config/README.md)."
  return 1
}

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
  local bad dup
  bad="$(printf '%s' "$json" | jq -r '
    .[] |
    select(
      ((.group // "") | test("^[^[:space:][:cntrl:]]+$") | not)
      or ((.role // "") | test("^(cluster-[A-Za-z0-9-]+|rt-[A-Za-z0-9-]+)$") | not)
    )
    | "  - group=\(.group // "MISSING") role=\(.role // "MISSING")"
  ' 2>/dev/null || true)"
  if [[ -n "$bad" ]]; then
    die "$(printf 'Invalid grant entries in %s:\n%s' "$label" "$bad")"
  fi
  dup="$(printf '%s' "$json" | jq -r '[.[].group // ""] | group_by(.) | map(select(length > 1 and .[0] != "")) | .[][0]' | sort -u)"
  if [[ -n "$dup" ]]; then
    die "$(printf 'Duplicate group names in %s:\n%s' "$label" "$dup")"
  fi
}

load_base_grants() {
  local base
  [[ -f "$GRANTS_FILE" ]] || die "Missing grants catalog: $GRANTS_FILE"
  base="$(cat "$GRANTS_FILE")"
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

cmd_apply_batch() {
  local grants count=0 failures=0 index=0 grant
  local group role principal_id auth_prefix fix_misbound

  parse_common_args "$@"
  validate_cluster_connection
  case "$GRANTS_MODE" in
    merge|replace) ;;
    *) die "GRANTS_MODE must be merge or replace (got: $GRANTS_MODE)" ;;
  esac

  if [[ -z "${WORKFLOW_RANCHER_PATCH:-}" ]]; then
    WORKFLOW_RANCHER_PATCH="$(build_workflow_patch "$GRANTS_FILE")"
    export WORKFLOW_RANCHER_PATCH
    log "Workflow Rancher patch: $WORKFLOW_RANCHER_PATCH"
  fi

  grants="$(resolve_grants_json)"
  grants="$(printf '%s' "$grants" | jq -c '[.[] | select(.enabled == true)]')"
  count="$(printf '%s' "$grants" | jq 'length')"
  if [[ "$count" -eq 0 ]]; then
    log "No enabled grants to apply (all groups disabled or empty config)"
    return 0
  fi

  log "Effective grant plan ($count enabled):"
  printf '%s' "$grants" | jq -r '.[] | "  - \(.group): \(.role) (enabled=true)"'

  while IFS= read -r grant; do
    index=$((index + 1))
    mapfile -t _fields < <(jq -r '
      .group // "",
      .role // "",
      .principal_id // "",
      .group_auth_prefix // "",
      (.fix_misbound_user // false | tostring)
    ' <<<"$grant")
    group="${_fields[0]:-}"
    role="${_fields[1]:-}"
    principal_id="${_fields[2]:-}"
    auth_prefix="${_fields[3]:-}"
    fix_misbound="${_fields[4]:-false}"

    validate_group "$group"
    validate_role "$role" "$group"

    reset_single_grant_state
    GROUP_NAME="$group"
    ROLE_TEMPLATE_ID="$role"
    GROUP_PRINCIPAL_ID="${principal_id:-}"
    GROUP_AUTH_PREFIX="${auth_prefix:-$DEFAULT_GROUP_AUTH_PREFIX}"
    FIX_MISBOUND_USER="$fix_misbound"
    LIST_BINDINGS="false"

    log "[$index/$count] Grant: group=$group role=$role principal=${principal_id:-<built from $GROUP_AUTH_PREFIX>} fix_misbound=$fix_misbound"

    if ! run_single_grant; then
      err "Grant failed for group=$group role=$role"
      failures=$((failures + 1))
    fi
  done < <(printf '%s' "$grants" | jq -c '.[]')

  if [[ "$failures" -gt 0 ]]; then
    die "$failures grant(s) failed"
  fi
  log "All $count grant(s) applied successfully."
}

cmd_grant_one() {
  parse_common_args "$@"
  validate_cluster_connection
  [[ -n "$GROUP_NAME" || -n "$GROUP_PRINCIPAL_ID" ]] || die "--group or --group-principal-id is required"
  if [[ -z "$GROUP_NAME" && -n "$GROUP_PRINCIPAL_ID" ]]; then
    GROUP_NAME="${GROUP_PRINCIPAL_ID##*/}"
  fi
  reset_single_grant_state
  LIST_BINDINGS="false"
  run_single_grant || exit 1
}

cmd_list_bindings() {
  parse_common_args "$@"
  validate_cluster_connection
  LIST_BINDINGS="true"
  run_single_grant || exit 1
}

cmd_build_patch() {
  local catalog="$GRANTS_FILE"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --grants-file) require_arg --grants-file "${2-}"; catalog="$2"; shift 2 ;;
      -h|--help) usage; exit 0 ;;
      *) die "Unknown argument: $1" ;;
    esac
  done
  build_workflow_patch "$catalog"
}

main() {
  local sub="${1:-}"

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
  LIST_BINDINGS="false"
  FIX_MISBOUND_USER="false"
  GRANTS_FILE="${GRANTS_FILE:-$DEFAULT_GRANTS_FILE}"
  GRANTS_JSON="${GRANTS_JSON:-}"
  GRANTS_MODE="${GRANTS_MODE:-merge}"
  DEFAULT_GROUP_AUTH_PREFIX="${DEFAULT_GROUP_AUTH_PREFIX:-keycloak_group}"

  if [[ "$sub" == "--rancher-url" ]]; then
    cmd_grant_one "$@"
    return
  fi

  case "$sub" in
    apply)         shift; cmd_apply_batch "$@" ;;
    grant-one)     shift; cmd_grant_one "$@" ;;
    list-bindings) shift; cmd_list_bindings "$@" ;;
    build-patch)   shift; cmd_build_patch "$@" ;;
    -h|--help|"")  usage ;;
    *)             die "Unknown subcommand: $sub (use apply, grant-one, list-bindings, or build-patch)" ;;
  esac
}

main "$@"
