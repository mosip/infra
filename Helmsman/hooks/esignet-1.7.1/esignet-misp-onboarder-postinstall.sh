#!/bin/bash
# =============================================================================
# eSignet 1.7.1 - eSignet MISP Partner Onboarder Post-install
# =============================================================================
# Validates onboarding job completion and restarts the esignet deployment
# so it picks up the new MISP license key.
# Only used with mosip-identity-plugin (plugin 2).
# =============================================================================
set -euo pipefail

ESIGNET_NS="${ESIGNET_NS:-esignet}"

echo "================================================"
echo "eSignet 1.7.1 - MISP Onboarder Post-install"
echo "================================================"

JOB_STATUS=$(kubectl -n "$ESIGNET_NS" get jobs \
  -l app.kubernetes.io/instance=esignet-misp-onboarder \
  -o jsonpath='{.items[0].status.succeeded}' 2>/dev/null || echo "")

if [ "$JOB_STATUS" = "1" ]; then
  echo "eSignet MISP partner onboarding completed successfully."
else
  echo "WARNING: onboarding job may not have completed. Check logs:"
  kubectl -n "$ESIGNET_NS" logs -l app.kubernetes.io/instance=esignet-misp-onboarder --tail=30 2>/dev/null || true
fi

# Restart esignet so it picks up the new MISP license key written to the secret
if kubectl -n "$ESIGNET_NS" get deployment esignet &>/dev/null; then
  kubectl -n "$ESIGNET_NS" rollout restart deployment esignet
  echo "esignet deployment restarted."
else
  echo "esignet deployment not found — skipping restart."
fi

echo "MISP onboarder post-install completed."
