#!/bin/bash
# =============================================================================
# eSignet 1.7.1 - Database Init Pre-install (postgres-init-esignet)
# =============================================================================
# Based on: deploy/postgres/postgres-init.sh
# postgres-init-esignet runs in the postgres namespace so it can access
# postgres-postgresql secret natively. This hook only ensures the esignet
# namespace exists so the postInstall hook can copy db-common-secrets there.
#
# Environment Variables:
#   ESIGNET_NS   - eSignet namespace (default: esignet)
# =============================================================================
set -euo pipefail

ESIGNET_NS="${ESIGNET_NS:-esignet}"

echo "================================================"
echo "eSignet 1.7.1 - Database Init Pre-install"
echo "================================================"

# Ensure esignet namespace exists with Istio injection enabled so that
# the postInstall hook can copy db-common-secrets into it.
kubectl create namespace "$ESIGNET_NS" --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace "$ESIGNET_NS" istio-injection=enabled --overwrite

echo "Database init pre-install completed."
