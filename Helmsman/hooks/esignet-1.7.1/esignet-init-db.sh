#!/bin/bash
# =============================================================================
# eSignet 1.7.1 - Database Init Pre-install (postgres-init-esignet)
# =============================================================================
# Based on: deploy/postgres/postgres-init.sh
# Copies postgres secrets from postgres namespace to esignet namespace
# before the postgres-init helm chart runs DB initialization.
#
# Environment Variables:
#   ESIGNET_NS   - eSignet namespace (default: esignet)
# =============================================================================
set -euo pipefail

ESIGNET_NS="${ESIGNET_NS:-esignet}"
POSTGRES_NS="postgres"

echo "================================================"
echo "eSignet 1.7.1 - Database Init Pre-install"
echo "================================================"

# --- Step 1: Ensure esignet namespace exists with istio ---
kubectl create namespace "$ESIGNET_NS" --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace "$ESIGNET_NS" istio-injection=enabled --overwrite

# --- Step 2: Copy postgres-postgresql secret from postgres to esignet ---
# Source: deploy/postgres/postgres-init.sh -> ../copy_cm_func.sh secret postgres-postgresql postgres esignet
echo "Copying postgres-postgresql secret to $ESIGNET_NS namespace"
kubectl -n "$POSTGRES_NS" get secret postgres-postgresql -o yaml | \
  sed "s/namespace: $POSTGRES_NS/namespace: $ESIGNET_NS/g" | \
  kubectl apply -f -

# --- Step 3: Copy db-common-secrets from postgres to esignet ---
# Source: deploy/postgres/postgres-init.sh -> ../copy_cm_func.sh secret db-common-secrets postgres esignet
echo "Copying db-common-secrets to $ESIGNET_NS namespace"
kubectl -n "$POSTGRES_NS" get secret db-common-secrets -o yaml | \
  sed "s/namespace: $POSTGRES_NS/namespace: $ESIGNET_NS/g" | \
  kubectl apply -f -

# --- Step 4: Copy postgres-config configmap from postgres to esignet ---
echo "Copying postgres-config configmap to $ESIGNET_NS namespace"
kubectl -n "$POSTGRES_NS" get configmap postgres-config -o yaml | \
  sed "s/namespace: $POSTGRES_NS/namespace: $ESIGNET_NS/g" | \
  kubectl apply -f -

echo "Database init pre-install completed."
