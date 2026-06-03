#!/bin/bash
# =============================================================================
# eSignet 1.7.1 - Mock Relying Party UI Pre-install
# =============================================================================
# Prepares for mock relying party UI deployment.
# =============================================================================
set -euo pipefail

echo "================================================"
echo "eSignet 1.7.1 - Mock Relying Party UI Pre-install"
echo "================================================"

# Ensure esignet namespace exists
kubectl create namespace esignet --dry-run=client -o yaml | kubectl apply -f -

# Verify mock relying party service is available
if kubectl -n esignet get svc mock-relying-party-service &>/dev/null; then
  echo "Mock relying party service found."
else
  echo "WARNING: Mock relying party service not found. UI depends on the service being deployed."
fi

echo "Mock relying party UI pre-install completed."
