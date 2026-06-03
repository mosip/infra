#!/bin/bash
# =============================================================================
# eSignet 1.7.1 - Mock Relying Party Service Pre-install
# =============================================================================
# Prepares for mock relying party service deployment.
# =============================================================================
set -euo pipefail

echo "================================================"
echo "eSignet 1.7.1 - Mock Relying Party Service Pre-install"
echo "================================================"

# Ensure esignet namespace exists
kubectl create namespace esignet --dry-run=client -o yaml | kubectl apply -f -

# Verify eSignet service is available
if kubectl -n esignet get svc esignet &>/dev/null; then
  echo "eSignet service found."
else
  echo "WARNING: eSignet service not found. Mock relying party service needs eSignet to be running."
fi

echo "Mock relying party service pre-install completed."
