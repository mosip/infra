#!/bin/bash
# =============================================================================
# eSignet Standalone 2.0.0 - eSignet API Testrig Pre-install Setup
# =============================================================================
# Prepares the esignet-mock namespace for the esignet-apitestrig release.
# keycloak-host and keycloak-client-secrets are already present in esignet-mock ns
# (copied by esignet-postinstall-keycloak-init.sh). postgres-postgresql is copied,
# and the s3-esignet-apitestrig / apitestrig-esignet-apitestrig secrets referenced
# by extraEnvVarsSecret are created here (chart doesn't create them itself); stale
# testrig CMs are deleted so the chart recreates them.
# =============================================================================
set -euo pipefail

NS=esignet-mock
COPY_UTIL="$WORKDIR/utils/copy-cm-and-secrets/copy_cm_func.sh"
MINIO_ROOT_PASSWORD_VAL="${MINIO_ROOT_PASSWORD:?ERROR: MINIO_ROOT_PASSWORD must be set}"

echo "================================================"
echo "eSignet Standalone 2.0.0 - eSignet API Testrig Pre-install"
echo "================================================"

echo "Deleting stale testrig configmaps in $NS"
kubectl -n "$NS" delete --ignore-not-found=true configmap s3
kubectl -n "$NS" delete --ignore-not-found=true configmap db
kubectl -n "$NS" delete --ignore-not-found=true configmap apitestrig

echo "Creating s3-esignet-apitestrig secret in $NS"
kubectl -n "$NS" create secret generic s3-esignet-apitestrig \
  --from-literal=s3-user-secret="$MINIO_ROOT_PASSWORD_VAL" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Creating apitestrig-esignet-apitestrig secret in $NS"
kubectl -n "$NS" create secret generic apitestrig-esignet-apitestrig \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Copying postgres-postgresql secret to $NS"
$COPY_UTIL secret postgres-postgresql postgres "$NS"

echo "eSignet API Testrig pre-install setup completed."
