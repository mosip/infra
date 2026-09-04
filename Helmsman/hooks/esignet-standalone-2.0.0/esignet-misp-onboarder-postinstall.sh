#!/bin/bash
# =============================================================================
# eSignet 1.7.1 - eSignet MISP Partner Onboarder Post-install
# =============================================================================
# Validates onboarding job completion and restarts the esignet deployment
# so it picks up the new MISP license key.
# Only used with mosip-identity-plugin (plugin 2).
# =============================================================================
set -euo pipefail

ESIGNET_NS="${ESIGNET_NS:-esignet-mock}"

echo "================================================"
echo "eSignet 1.7.1 - MISP Onboarder Post-install"
echo "================================================"

JOB_STATUS=$(kubectl -n "$ESIGNET_NS" get jobs \
  -l app.kubernetes.io/instance=esignet-misp-onboarder \
  -o jsonpath='{.items[0].status.succeeded}' 2>/dev/null || echo "")

# Always restore namespace injection before returning from this hook.
kubectl label namespace "$ESIGNET_NS" istio-injection=enabled --overwrite
echo "Istio injection re-enabled on namespace $ESIGNET_NS."

if ! [[ "$JOB_STATUS" =~ ^[1-9][0-9]*$ ]]; then
  echo "WARNING: onboarding job may not have completed. Check logs:"
  kubectl -n "$ESIGNET_NS" logs -l app.kubernetes.io/instance=esignet-misp-onboarder --tail=30 2>/dev/null || true
  exit 1
fi
echo "eSignet MISP partner onboarding completed successfully."

# Restart config-server first so it reloads the MISP key from the secret,
# then restart esignet so it fetches the updated config from config-server.
if kubectl -n "$ESIGNET_NS" get deployment esignet-config-server &>/dev/null; then
  kubectl -n "$ESIGNET_NS" rollout restart deployment esignet-config-server
  kubectl -n "$ESIGNET_NS" rollout status deployment esignet-config-server --timeout=300s
  echo "esignet-config-server restarted."
else
  echo "esignet-config-server deployment not found — skipping restart."
fi

if kubectl -n "$ESIGNET_NS" get deployment esignet-mock &>/dev/null; then
  kubectl -n "$ESIGNET_NS" rollout restart deployment esignet-mock
  kubectl -n "$ESIGNET_NS" rollout status deployment esignet-mock --timeout=300s
  echo "esignet deployment restarted."
else
  echo "esignet deployment not found — skipping restart."
fi

echo "MISP onboarder post-install completed."
