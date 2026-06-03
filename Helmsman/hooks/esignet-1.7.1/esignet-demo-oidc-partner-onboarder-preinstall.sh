#!/bin/bash
# =============================================================================
# eSignet 1.7.1 - Demo OIDC Partner Onboarder Pre-install
# =============================================================================
# Prepares for demo OIDC partner onboarding.
# =============================================================================
set -euo pipefail

echo "================================================"
echo "eSignet 1.7.1 - Demo OIDC Partner Onboarder Pre-install"
echo "================================================"

# Ensure esignet namespace exists
kubectl create namespace esignet --dry-run=client -o yaml | kubectl apply -f -

# Verify eSignet service is running
kubectl -n esignet wait --for=condition=ready pod -l app.kubernetes.io/name=esignet --timeout=300s 2>/dev/null || \
  echo "WARNING: eSignet pods not ready. Demo OIDC partner onboarding may fail."

echo "Demo OIDC partner onboarder pre-install completed."
