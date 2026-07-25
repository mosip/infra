#!/bin/bash
# =============================================================================
# eSignet 1.7.1 - eSignet MISP Partner Onboarder Post-install
# =============================================================================
# Validates onboarding job completion and restarts the esignet deployment
# so it picks up the new MISP license key.
# Only used with mosip-identity-plugin (plugin 2).
# =============================================================================
set -euo pipefail

ESIGNET_NS="${ESIGNET_NS:-esignet-go-mock}"

echo "================================================"
echo "eSignet 1.7.1 - MISP Onboarder Post-install"
echo "================================================"

JOB_STATUS=$(kubectl -n "$ESIGNET_NS" get jobs \
  -l app.kubernetes.io/instance=esignet-misp-onboarder-go \
  -o jsonpath='{.items[0].status.succeeded}' 2>/dev/null || echo "")

if [ "$JOB_STATUS" = "1" ]; then
  echo "eSignet MISP partner onboarding completed successfully."
else
  echo "WARNING: onboarding job may not have completed. Check logs:"
  kubectl -n "$ESIGNET_NS" logs -l app.kubernetes.io/instance=esignet-misp-onboarder-go --tail=30 2>/dev/null || true
fi

# Re-enable Istio sidecar injection now that the Job has completed
kubectl label namespace "$ESIGNET_NS" istio-injection=enabled --overwrite
echo "Istio injection re-enabled on namespace $ESIGNET_NS."

# Restart config-server first so it reloads the MISP key from the secret,
# then restart esignet so it fetches the updated config from config-server.
if kubectl -n "$ESIGNET_NS" get deployment esignet-config-server-go &>/dev/null; then
  kubectl -n "$ESIGNET_NS" rollout restart deployment esignet-config-server-go
  kubectl -n "$ESIGNET_NS" rollout status deployment esignet-config-server-go --timeout=300s || \
    echo "WARNING: esignet-config-server-go rollout did not complete within timeout." >&2
  echo "esignet-config-server-go restarted."
else
  echo "esignet-config-server-go deployment not found — skipping restart."
fi

if kubectl -n "$ESIGNET_NS" get deployment esignet-go-mock &>/dev/null; then
  kubectl -n "$ESIGNET_NS" rollout restart deployment esignet-go-mock
  kubectl -n "$ESIGNET_NS" rollout status deployment esignet-go-mock --timeout=300s || \
    echo "WARNING: esignet rollout did not complete within timeout." >&2
  echo "esignet deployment restarted."
else
  echo "esignet deployment not found — skipping restart."
fi

echo "MISP onboarder post-install completed."
