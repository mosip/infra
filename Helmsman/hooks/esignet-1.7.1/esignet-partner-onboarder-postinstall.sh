#!/bin/bash
# =============================================================================
# eSignet 1.7.1 - Partner Onboarder Post-install
# =============================================================================
# Post-install cleanup and validation after partner onboarding.
# =============================================================================
set -euo pipefail

echo "================================================"
echo "eSignet 1.7.1 - Partner Onboarder Post-install"
echo "================================================"

# Check onboarding job status
JOB_STATUS=$(kubectl -n esignet get jobs -l app.kubernetes.io/instance=esignet-resident-oidc-partner-onboarder -o jsonpath='{.items[0].status.succeeded}' 2>/dev/null || echo "")

if [ "$JOB_STATUS" = "1" ]; then
  echo "Partner onboarding completed successfully."
else
  echo "WARNING: Partner onboarding job may not have completed. Check logs."
  kubectl -n esignet logs -l app.kubernetes.io/instance=esignet-resident-oidc-partner-onboarder --tail=20 2>/dev/null || true
fi

echo "Partner onboarder post-install completed."
