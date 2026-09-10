#!/bin/bash
# Prepare Keycloak to use the shared external PostgreSQL server (mosip/mosip-infra#1955).
# Non-interactive Helmsman hook — reuses postgres-setup-config / postgres-postgresql
# from the postgres namespace, creates a dedicated keycloak-db-credentials secret,
# and runs keycloak-db-init before the Keycloak chart installs.

NS=keycloak
SRC_NS=postgres
DB_NAME="bitnami_keycloak"
DB_USER="bn_keycloak"
SU_SECRET_NAME="postgres-postgresql"
SU_SECRET_KEY="postgres-password"
DBUSER_SECRET_NAME="keycloak-db-credentials"
DBUSER_SECRET_KEY="password"
COPY_UTIL="$WORKDIR/utils/copy-cm-and-secrets/copy_cm_func.sh"
JOB_MANIFEST="$WORKDIR/utils/keycloak-db-init-job.yaml"

function configuring_keycloak_external_db() {
  echo "Configuring Keycloak to use shared external PostgreSQL..."

  if ! kubectl -n "$SRC_NS" get configmap postgres-setup-config >/dev/null 2>&1; then
    echo "ERROR: configmap postgres-setup-config not found in namespace $SRC_NS"
    exit 1
  fi
  if ! kubectl -n "$SRC_NS" get secret "$SU_SECRET_NAME" >/dev/null 2>&1; then
    echo "ERROR: secret $SU_SECRET_NAME not found in namespace $SRC_NS"
    exit 1
  fi

  "$COPY_UTIL" configmap postgres-setup-config "$SRC_NS" "$NS"
  "$COPY_UTIL" secret "$SU_SECRET_NAME" "$SRC_NS" "$NS"

  DB_HOST=$(kubectl get configmap postgres-setup-config -n "$NS" -o jsonpath='{.data.mosip-database-hostname-override}')
  DB_PORT=$(kubectl get configmap postgres-setup-config -n "$NS" -o jsonpath='{.data.mosip-database-port-override}')
  SU_USER="postgres"

  if [[ -z "$DB_HOST" || -z "$DB_PORT" ]]; then
    echo "ERROR: postgres-setup-config in $NS is missing host/port overrides"
    exit 1
  fi

  if ! kubectl get secret "$DBUSER_SECRET_NAME" -n "$NS" >/dev/null 2>&1; then
    KC_DB_PWD=$(openssl rand -base64 24)
    kubectl create secret generic "$DBUSER_SECRET_NAME" -n "$NS" \
      --from-literal="$DBUSER_SECRET_KEY=$KC_DB_PWD"
    echo "Created dedicated secret $DBUSER_SECRET_NAME in $NS"
  else
    echo "Secret $DBUSER_SECRET_NAME already exists in $NS, reusing it"
  fi

  echo "Running one-shot keycloak-db-init job (safe to re-run)..."
  kubectl delete job keycloak-db-init -n "$NS" --ignore-not-found
  sed -e "s/__DB_HOST__/$DB_HOST/g" \
      -e "s/__DB_PORT__/$DB_PORT/g" \
      -e "s/__DB_NAME__/$DB_NAME/g" \
      -e "s/__DB_USER__/$DB_USER/g" \
      -e "s/__SU_USER__/$SU_USER/g" \
      -e "s/__SU_SECRET_NAME__/$SU_SECRET_NAME/g" \
      -e "s/__SU_SECRET_KEY__/$SU_SECRET_KEY/g" \
      -e "s/__DBUSER_SECRET_NAME__/$DBUSER_SECRET_NAME/g" \
      -e "s/__DBUSER_SECRET_KEY__/$DBUSER_SECRET_KEY/g" \
      "$JOB_MANIFEST" | kubectl apply -n "$NS" -f -

  kubectl wait --for=condition=complete job/keycloak-db-init -n "$NS" --timeout=120s || true
  JOB_SUCCEEDED=$(kubectl get job keycloak-db-init -n "$NS" -o jsonpath='{.status.succeeded}' 2>/dev/null)
  if [[ "${JOB_SUCCEEDED:-0}" -ge 1 ]]; then
    echo "Removing copied superuser secret $SU_SECRET_NAME from $NS (no longer needed)"
    kubectl delete secret "$SU_SECRET_NAME" -n "$NS" --ignore-not-found
  else
    echo "ERROR: keycloak-db-init did not complete — check 'kubectl logs -n $NS job/keycloak-db-init'"
    exit 1
  fi

  return 0
}

set -e
set -o errexit
set -o nounset
set -o errtrace
set -o pipefail
configuring_keycloak_external_db
