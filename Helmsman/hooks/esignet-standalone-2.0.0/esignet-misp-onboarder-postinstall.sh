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
DEPLOYMENT_NAME="${DEPLOYMENT_NAME:-esignet-mock}"

echo "================================================"
echo "eSignet 1.7.1 - MISP Onboarder Post-install"
echo "================================================"

# Jobs/pods from previous runs aren't cleaned up automatically, so multiple can match
# this label at once - always sort by creation time and take the newest, not the
# API-returned .items[0] (order isn't guaranteed) or a bare -l selector (which would
# match every stale pod too, producing confusing concatenated logs). Using
# range+tail -1 rather than a jsonpath slice index (e.g. items[-1:].field): applying a
# field accessor directly after a slice doesn't reliably drill into the single
# resulting element in kubectl's jsonpath engine - confirmed empirically, it silently
# returned nothing. Trailing `|| true`: under set -euo pipefail, a genuine kubectl API
# failure (not just "no jobs found") would otherwise abort the script here, skipping the
# istio-injection restore below - an empty JOB_STATUS already routes into the same
# WARNING/diagnostic path as "job not done", which is the right outcome either way.
JOB_STATUS=$(kubectl -n "$ESIGNET_NS" get jobs \
  -l app.kubernetes.io/instance=esignet-misp-onboarder \
  --sort-by=.metadata.creationTimestamp \
  -o jsonpath='{range .items[*]}{.status.succeeded}{"\n"}{end}' 2>/dev/null | tail -1) || true

# Always restore namespace injection before returning from this hook.
kubectl label namespace "$ESIGNET_NS" istio-injection=enabled --overwrite
echo "Istio injection re-enabled on namespace $ESIGNET_NS."

if ! [[ "$JOB_STATUS" =~ ^[1-9][0-9]*$ ]]; then
  echo "WARNING: onboarding job may not have completed. Check logs from the latest pod only:"
  LATEST_POD=$(kubectl -n "$ESIGNET_NS" get pods \
    -l app.kubernetes.io/instance=esignet-misp-onboarder \
    --sort-by=.metadata.creationTimestamp \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null | tail -1) || true
  if [ -n "$LATEST_POD" ]; then
    echo "--- pod/container status (state, restarts, last termination reason/exit code) ---"
    kubectl -n "$ESIGNET_NS" get pod "$LATEST_POD" \
      -o jsonpath='phase={.status.phase}{"\n"}{range .status.containerStatuses[*]}container={.name} restartCount={.restartCount}{"\n"}state={.state}{"\n"}lastState={.lastState}{"\n"}{end}' 2>/dev/null || true
    echo "--- pod logs (last 200 lines) ---"
    kubectl -n "$ESIGNET_NS" logs "$LATEST_POD" --tail=200 2>/dev/null || true
  fi
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

if kubectl -n "$ESIGNET_NS" get deployment "$DEPLOYMENT_NAME" &>/dev/null; then
  kubectl -n "$ESIGNET_NS" rollout restart deployment "$DEPLOYMENT_NAME"
  kubectl -n "$ESIGNET_NS" rollout status deployment "$DEPLOYMENT_NAME" --timeout=300s
  echo "esignet deployment restarted."
else
  echo "esignet deployment ($DEPLOYMENT_NAME) not found — skipping restart."
fi

echo "MISP onboarder post-install completed."
