#!/bin/bash
# =============================================================================
# eSignet 1.7.1 - Database Init Pre-install (postgres-init-esignet)
# =============================================================================
# Based on: deploy/postgres/postgres-init.sh
# postgres-init-esignet runs in the postgres namespace so it can access
# postgres-postgresql secret natively. This hook pre-creates all esignet
# namespaces so the postInstall hook can copy db-common-secrets into each.
# Namespaces are created here at priority -16 because the namespace-specific
# preinstall hooks (esignet-mosipid1/mosipid2/sunbird) only run at priority -14.
# =============================================================================
set -euo pipefail

echo "================================================"
echo "eSignet 1.7.1 - Database Init Pre-install"
echo "================================================"

for NS in esignet esignet-mosipid1 esignet-mosipid2 esignet-sunbird; do
  kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -
  kubectl label namespace "$NS" istio-injection=enabled --overwrite
  echo "Namespace $NS ready."
done

echo "Database init pre-install completed."
