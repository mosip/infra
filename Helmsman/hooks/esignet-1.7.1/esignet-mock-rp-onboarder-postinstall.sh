#!/bin/bash
# =============================================================================
# eSignet 1.7.1 - Mock RP OIDC Partner Onboarder Post-install
# =============================================================================
# Validates onboarding job completion and restarts mock-relying-party-service
# so it picks up the newly registered OIDC client.
# =============================================================================
set -euo pipefail

ESIGNET_NS="${ESIGNET_NS:-esignet}"

echo "================================================"
echo "eSignet 1.7.1 - Mock RP Onboarder Post-install"
echo "================================================"

JOB_STATUS=$(kubectl -n "$ESIGNET_NS" get jobs \
  -l app.kubernetes.io/instance=esignet-mock-rp-onboarder \
  -o jsonpath='{.items[0].status.succeeded}' 2>/dev/null || echo "")

if [ "$JOB_STATUS" = "1" ]; then
  echo "Mock RP OIDC partner onboarding completed successfully."
else
  echo "WARNING: onboarding job may not have completed. Check logs:"
  kubectl -n "$ESIGNET_NS" logs -l app.kubernetes.io/instance=esignet-mock-rp-onboarder --tail=30 2>/dev/null || true
fi

# Restart mock-relying-party-service so it picks up the newly onboarded OIDC client
if kubectl -n "$ESIGNET_NS" get deployment mock-relying-party-service &>/dev/null; then
  kubectl -n "$ESIGNET_NS" rollout restart deployment mock-relying-party-service
  echo "mock-relying-party-service restarted."
else
  echo "mock-relying-party-service deployment not found — skipping restart."
fi

echo "Mock RP onboarder post-install completed."
