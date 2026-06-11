#!/bin/bash
# =============================================================================
# eSignet 1.7.1 - Mock Relying Party UI CRE Pre-install
# =============================================================================
# Ensures esignet-cre namespace exists and verifies mock-relying-party-service
# is available in the esignet-cre namespace before UI deployment.
# =============================================================================
set -euo pipefail

ESIGNET_NS="esignet-cre"

echo "================================================"
echo "eSignet 1.7.1 - Mock Relying Party UI CRE Pre-install"
echo "================================================"

kubectl create namespace "$ESIGNET_NS" --dry-run=client -o yaml | kubectl apply -f -

if kubectl -n "$ESIGNET_NS" get svc mock-relying-party-service &>/dev/null; then
  echo "Mock relying party service found in $ESIGNET_NS."
else
  echo "WARNING: Mock relying party service not found in $ESIGNET_NS. UI depends on the service being deployed."
fi

echo "Mock relying party UI CRE pre-install completed."
