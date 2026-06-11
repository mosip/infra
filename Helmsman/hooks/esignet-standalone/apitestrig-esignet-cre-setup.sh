#!/bin/bash
# =============================================================================
# eSignet 1.7.1 - eSignet-CRE API Testrig Pre-install Setup
# =============================================================================
# Prepares the esignet-cre namespace for the esignet-cre-apitestrig release.
# keycloak-host and keycloak-client-secrets are already present in esignet-cre
# (copied by esignet-postinstall-keycloak-init.sh). Only postgres-postgresql
# needs to be copied; stale testrig CMs are deleted so the chart recreates them.
# =============================================================================
set -euo pipefail

NS=esignet-cre
COPY_UTIL="$WORKDIR/utils/copy-cm-and-secrets/copy_cm_func.sh"

echo "================================================"
echo "eSignet 1.7.1 - eSignet-CRE API Testrig Pre-install"
echo "================================================"

echo "Deleting stale testrig configmaps in $NS"
kubectl -n "$NS" delete --ignore-not-found=true configmap s3
kubectl -n "$NS" delete --ignore-not-found=true configmap db
kubectl -n "$NS" delete --ignore-not-found=true configmap apitestrig

echo "Copying postgres-postgresql secret to $NS"
$COPY_UTIL secret postgres-postgresql postgres "$NS"

echo "eSignet-CRE API Testrig pre-install setup completed."
