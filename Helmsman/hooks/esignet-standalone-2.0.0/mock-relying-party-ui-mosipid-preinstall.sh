#!/bin/bash
# =============================================================================
# eSignet Standalone 2.0.0 - Mock Relying Party UI MOSIPID Pre-install
# =============================================================================
# Ensures esignet-mosipid namespace exists and verifies mock-relying-party-service
# is available in the esignet-mosipid namespace before UI deployment.
# =============================================================================
set -euo pipefail

ESIGNET_NS="esignet-mosipid"

echo "================================================"
echo "eSignet Standalone 2.0.0 - Mock Relying Party UI MOSIPID Pre-install"
echo "================================================"

kubectl create namespace "$ESIGNET_NS" --dry-run=client -o yaml | kubectl apply -f -

if kubectl -n "$ESIGNET_NS" get svc mock-relying-party-service &>/dev/null; then
  echo "Mock relying party service found in $ESIGNET_NS."
else
  echo "WARNING: Mock relying party service not found in $ESIGNET_NS. UI depends on the service being deployed."
fi

echo "Mock relying party UI MOSIPID pre-install completed."
