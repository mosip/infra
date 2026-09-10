#!/bin/bash
# =============================================================================
# eSignet 1.7.1 - eSignet-MOSIPID2 API Testrig Pre-install Setup
# =============================================================================
# Prepares the esignet-mosipid2 namespace for the esignet-mosipid2-apitestrig release.
# keycloak-host and keycloak-client-secrets are already present in esignet-mosipid2
# (copied by esignet-postinstall-keycloak-init.sh). Only postgres-postgresql
# needs to be copied; stale testrig CMs are deleted so the chart recreates them.
# =============================================================================
set -euo pipefail

NS=esignet-mosipid2
COPY_UTIL="$WORKDIR/utils/copy-cm-and-secrets/copy_cm_func.sh"

echo "================================================"
echo "eSignet 1.7.1 - eSignet-MOSIPID2 API Testrig Pre-install"
echo "================================================"

echo "Deleting stale testrig configmaps in $NS"
kubectl -n "$NS" delete --ignore-not-found=true configmap s3
kubectl -n "$NS" delete --ignore-not-found=true configmap db
kubectl -n "$NS" delete --ignore-not-found=true configmap apitestrig

echo "Copying postgres-postgresql secret to $NS"
$COPY_UTIL secret postgres-postgresql postgres "$NS"

echo "eSignet-MOSIPID2 API Testrig pre-install setup completed."
