#!/bin/bash
# =============================================================================
# eSignet 1.7.1 - Mock Identity System Pre-install
# =============================================================================
# Prepares esignet namespace for mock identity system deployment.
# =============================================================================
set -euo pipefail

echo "================================================"
echo "eSignet 1.7.1 - Mock Identity System Pre-install"
echo "================================================"

# Ensure esignet namespace exists
kubectl create namespace esignet --dry-run=client -o yaml | kubectl apply -f -

# Verify SoftHSM mock identity configmap exists in esignet namespace
if kubectl -n esignet get configmap softhsm-mock-identity-system-share &>/dev/null; then
  echo "SoftHSM mock identity system configmap found."
else
  echo "ERROR: softhsm-mock-identity-system-share configmap not found in esignet namespace."
  echo "Deploy/copy this shared ConfigMap before running mock identity system install."
  exit 1
fi

echo "Mock identity system pre-install completed."
