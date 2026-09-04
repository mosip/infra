#!/bin/bash
# =============================================================================
# eSignet 1.7.1 - Signup API Testrig Pre-install Setup
# =============================================================================
# Prepares the signup namespace for the esignet-signup-apitestrig release.
# keycloak-host and keycloak-client-secrets are already present in signup ns
# (copied by signup-keycloak-init-postinstall.sh). Only postgres-postgresql
# needs to be copied; stale testrig CMs are deleted so the chart recreates them.
# =============================================================================
set -euo pipefail

NS=signup
COPY_UTIL="$WORKDIR/utils/copy-cm-and-secrets/copy_cm_func.sh"

echo "================================================"
echo "eSignet 1.7.1 - Signup API Testrig Pre-install"
echo "================================================"

echo "Deleting stale testrig configmaps in $NS"
kubectl -n "$NS" delete --ignore-not-found=true configmap s3
kubectl -n "$NS" delete --ignore-not-found=true configmap db
kubectl -n "$NS" delete --ignore-not-found=true configmap apitestrig

echo "Copying postgres-postgresql secret to $NS"
$COPY_UTIL secret postgres-postgresql postgres "$NS"

echo "Signup API Testrig pre-install setup completed."
