#!/bin/bash
# Pre-install / pre-upgrade hook for keycloak-db-init (KEYCLOAK_DB=external).
# Ported from mosip/keycloak#215 (deploy/install.sh, external DB option).
#
# - Copies the PostgreSQL superuser Secret (postgres-postgresql) from the
#   postgres namespace, where the infra postgresql role (MOSIP platform) or the
#   postgres chart (esignet-standalone) created it. Host and port come from the
#   DSF. The Secret is removed again by keycloak-db-init-postinstall.sh after
#   the init Job.
# - Creates Keycloak's own DB password Secret (keycloak-db-credentials) once;
#   it is never shared with any other module's DB credentials.

set -euo pipefail

NS=keycloak
SRC_NS=postgres
COPY_UTIL="$WORKDIR/utils/copy-cm-and-secrets/copy_cm_func.sh"
DBUSER_SECRET_NAME="keycloak-db-credentials"
DBUSER_SECRET_KEY="password"

if ! kubectl -n "$SRC_NS" get secret postgres-postgresql >/dev/null 2>&1; then
  echo "ERROR: secret postgres-postgresql not found in namespace $SRC_NS."
  echo "KEYCLOAK_DB=external needs the shared PostgreSQL first (MOSIP platform:"
  echo "terraform.yml COMPONENT=configure with postgresql; esignet-standalone: the"
  echo "postgres app of this DSF). Or set KEYCLOAK_DB=bundled."
  exit 1
fi
"$COPY_UTIL" secret postgres-postgresql "$SRC_NS" "$NS"

if kubectl -n "$NS" get secret "$DBUSER_SECRET_NAME" >/dev/null 2>&1; then
  echo "Secret $DBUSER_SECRET_NAME already exists in $NS, reusing it as-is."
else
  kubectl -n "$NS" create secret generic "$DBUSER_SECRET_NAME" \
    --from-literal="$DBUSER_SECRET_KEY=$(openssl rand -base64 24)"
  echo "Created $DBUSER_SECRET_NAME in $NS."
fi
