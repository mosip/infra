#!/bin/bash
# =============================================================================
# eSignet 1.7.1 - Partner Onboarder Pre-install
# =============================================================================
# Prepares for eSignet + Resident OIDC partner onboarding.
# =============================================================================
set -euo pipefail

echo "================================================"
echo "eSignet 1.7.1 - Partner Onboarder Pre-install"
echo "================================================"

# Ensure esignet namespace exists
kubectl create namespace esignet --dry-run=client -o yaml | kubectl apply -f -

# Verify eSignet service is running
kubectl -n esignet wait --for=condition=ready pod -l app.kubernetes.io/name=esignet --timeout=300s 2>/dev/null || \
  echo "WARNING: eSignet pods not ready. Partner onboarding may fail."

# Verify Keycloak is accessible
if kubectl -n keycloak get svc keycloak &>/dev/null; then
  echo "Keycloak service found."
else
  echo "WARNING: Keycloak service not found. Partner onboarding requires Keycloak."
fi

echo "Partner onboarder pre-install completed."
