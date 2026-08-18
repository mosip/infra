#!/usr/bin/env bash
#
# rancher-grant-cluster-access.sh - Grant a Keycloak (or other IdP) group access to a Rancher cluster.
# rancher-grant-cluster-access.sh - Rancher cluster RBAC (batch apply, single grant, workflow patch).
#
# When clusters are registered with a personal/service API token, only that principal
# sees the cluster in Rancher UI. This script creates a clusterRoleTemplateBinding so
# an IdP group (e.g. DEVOPS) receives cluster-owner (or another role) without manual UI steps.
# Subcommands:
#   apply         Merge grants catalog + env/workflow patches; apply all enabled teams (CI default)
#   grant-one     Grant one IdP group one role on one cluster (manual debugging)
#   list-bindings List clusterRoleTemplateBindings for a cluster
#   build-patch   Print WORKFLOW_RANCHER_PATCH JSON (apply runs this internally when needed)
#
# Groups can be bound before the downstream cluster finishes importing (pending state).
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

[9 lines collapsed]

usage() {
  cat <<'EOF'
Usage: rancher-grant-cluster-access.sh --rancher-url <url> --token <token> \
  [--cluster-name <name> | --cluster-id <id>] \
  [--group <name> | --group-principal-id <id>] [options]
Usage:
  rancher-grant-cluster-access.sh apply --rancher-url <url> --token <token> \
    [--cluster-name <name> | --cluster-id <id>] [--grants-file <path>] [options]
Required:
  --rancher-url <url>           Rancher base URL (https://rancher.<env>.mosip.net, NO /v3)
  --token <token>               Rancher API bearer token (needs permission to manage cluster RBAC)
  rancher-grant-cluster-access.sh grant-one --rancher-url <url> --token <token> \
    [--cluster-name <name> | --cluster-id <id>] \
    [--group <name> | --group-principal-id <id>] [options]
Cluster selector (one required):
  --cluster-name <name>         Rancher cluster name
  --cluster-id <id>             Rancher cluster id (e.g. c-m-xxxxx)
  rancher-grant-cluster-access.sh list-bindings --rancher-url <url> --token <token> \
    [--cluster-name <name> | --cluster-id <id>]
Group selector (one required unless GROUP_NAME / GROUP_PRINCIPAL_ID set):
  --group <name>                IdP group name as shown in Rancher (e.g. DEVOPS)
  --group-principal-id <id>     Full principal id (e.g. keycloak_group://DEVOPS)
  --list-bindings               Print cluster role bindings and exit
  --fix-misbound-user           Remove wrong DEVOPS bindings (user principal, triple-slash group id, etc.)
  rancher-grant-cluster-access.sh build-patch [--grants-file <path>]
Optional:
  --role-template <id>          Rancher role template (default: cluster-owner)
  --group-auth-prefix <prefix>  Principal prefix when building group id (default: auto-detect)
  --binding-name <name>         Binding resource name (default: crtb-<group>-<role>)
  --insecure                    Skip TLS verification for Rancher API calls only
  -h, --help                    Show help
Subcommands:
  apply         Apply enabled grants from catalog + env/workflow patches (CI default)
  grant-one     Grant one group one role on one cluster
  list-bindings Print clusterRoleTemplateBindings JSON
  build-patch   Print WORKFLOW_RANCHER_PATCH JSON
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
Environment (batch): RANCHER_ACCESS_GRANTS, RANCHER_DEVOPS_*, WORKFLOW_*, WORKFLOW_RANCHER_PATCH
EOF
}

[26 lines collapsed]

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
[[ ${BASH_VERSINFO[0]} -ge 4 ]] || die "bash 4+ is required"
[[ -n "$RANCHER_URL" ]]          || die "--rancher-url is required"
[[ -n "$RANCHER_TOKEN" ]]         || die "--token is required"
[[ -n "$CLUSTER_NAME" || -n "$CLUSTER_ID" ]] || die "--cluster-name or --cluster-id is required"
if [[ "$LIST_BINDINGS" != "true" ]]; then
  [[ -n "$GROUP_NAME" || -n "$GROUP_PRINCIPAL_ID" ]] || die "--group or --group-principal-id is required"
fi
command -v curl >/dev/null 2>&1 || die "curl is required"
command -v jq   >/dev/null 2>&1 || die "jq is required"
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
if [[ -z "$GROUP_NAME" && -n "$GROUP_PRINCIPAL_ID" ]]; then
  GROUP_NAME="${GROUP_PRINCIPAL_ID##*/}"
fi
RANCHER_URL="${RANCHER_URL%/}"
[[ "$RANCHER_URL" =~ ^https:// ]] \
  || die "RANCHER_URL must begin with https:// (got: $RANCHER_URL)"
api() {
  local method="$1" path="$2" body="${3:-}"
  local tmp status curl_args=()

[385 lines collapsed]

    log "Retrying with alternate group principal: ${candidate}"
    if binding_exists "$candidate"; then
      log "Binding already exists for group='${candidate}' role='${ROLE_TEMPLATE_ID}' (skipping)"
      exit 0
      return 0
    fi
