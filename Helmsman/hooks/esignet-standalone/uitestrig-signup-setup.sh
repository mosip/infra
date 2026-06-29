#!/bin/bash
# =============================================================================
# eSignet 1.7.1 - Signup UI Testrig Pre-install Setup
# =============================================================================
# Prepares the signup-uitestrig namespace.
# Copies keycloak resources from keycloak ns, MinIO s3 secret from minio ns,
# and postgres-postgresql from postgres ns.
# Stale uitestrig CMs are deleted so the chart recreates them from set: values.
# =============================================================================
set -euo pipefail

NS=signup-uitestrig
COPY_UTIL="$WORKDIR/utils/copy-cm-and-secrets/copy_cm_func.sh"

echo "================================================"
echo "eSignet 1.7.1 - Signup UI Testrig Pre-install"
echo "================================================"

echo "Ensuring $NS namespace exists with Istio injection disabled"
kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace "$NS" istio-injection=disabled --overwrite

echo "Deleting stale uitestrig configmaps in $NS"
kubectl -n "$NS" delete --ignore-not-found=true configmap s3
kubectl -n "$NS" delete --ignore-not-found=true configmap db
kubectl -n "$NS" delete --ignore-not-found=true configmap uitestrig

echo "Copying resources to $NS"
$COPY_UTIL configmap keycloak-host keycloak "$NS"
$COPY_UTIL secret keycloak-client-secrets keycloak "$NS"
$COPY_UTIL secret s3 minio "$NS"
$COPY_UTIL secret postgres-postgresql postgres "$NS"

echo "Signup UI Testrig pre-install setup completed."
