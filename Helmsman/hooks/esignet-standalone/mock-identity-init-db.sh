#!/bin/bash
# =============================================================================
# eSignet 1.7.1 - Mock Identity System DB Init Pre-install
# =============================================================================
# Based on: esignet-mock-services/deploy/postgres/init_db.sh
# Ensures postgres-postgresql secret is present in the esignet namespace
# before postgres-init-mock-identity helm chart runs DB initialization.
#
# Environment Variables:
#   ESIGNET_NS - eSignet namespace (default: esignet)
# =============================================================================
set -euo pipefail

ESIGNET_NS="${ESIGNET_NS:-esignet-mock}"
POSTGRES_NS="postgres"
COPY_UTIL="$WORKDIR/utils/copy-cm-and-secrets/copy_cm_func.sh"

echo "================================================"
echo "eSignet 1.7.1 - Mock Identity DB Init Pre-install"
echo "================================================"

# --- Step 1: Ensure esignet namespace exists with istio ---
kubectl create namespace "$ESIGNET_NS" --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace "$ESIGNET_NS" istio-injection=enabled --overwrite

# --- Step 2: Copy postgres-postgresql secret to esignet namespace ---
echo "Copying postgres-postgresql secret to $ESIGNET_NS namespace"
$COPY_UTIL secret postgres-postgresql "$POSTGRES_NS" "$ESIGNET_NS"

echo "Mock identity DB init pre-install completed."
