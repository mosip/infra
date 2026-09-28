#!/bin/bash
# =============================================================================
# eSignet 1.7.1 - eSignet MISP Partner Onboarder Pre-install
# =============================================================================
# Prepares the esignet namespace for the MISP onboarder Job:
#   - Disables Istio sidecar injection so the Job pod can reach Completed state
#   - Deletes stale MISP onboarder artifacts from previous runs (idempotency)
#   - Copies keycloak resources needed by the onboarder Job
#   - Deletes onboarder-namespace ConfigMap so this release owns it cleanly
# Does NOT wait for the esignet pod to be ready: MISP onboarding writes a
# license key that esignet then consumes on startup - it doesn't call
# esignet's own API, so it doesn't need esignet up first. Waiting here would
# deadlock when the pod can't become ready without the key this job provides
# (empty MOSIP_ESIGNET_MISP_KEY makes esignet Fatal before /health ever
# serves).
# Only used with mosip-identity-plugin (plugin 2).
# =============================================================================
set -euo pipefail

ESIGNET_NS="${ESIGNET_NS:-esignet-mock}"
KEYCLOAK_NS="keycloak"
COPY_UTIL="$WORKDIR/utils/copy-cm-and-secrets/copy_cm_func.sh"

echo "================================================"
echo "eSignet 1.7.1 - MISP Onboarder Pre-install"
echo "================================================"

kubectl create namespace "$ESIGNET_NS" --dry-run=client -o yaml | kubectl apply -f -

# Disable Istio sidecar injection — Job pods with sidecars never reach Completed state
kubectl label namespace "$ESIGNET_NS" istio-injection=disabled --overwrite
echo "Istio injection disabled on namespace $ESIGNET_NS."

restore_istio_injection_on_failure() {
  local status=$?
  if [ "$status" -ne 0 ]; then
    kubectl label namespace "$ESIGNET_NS" istio-injection=enabled --overwrite || true
  fi
}
trap restore_istio_injection_on_failure EXIT

# Delete stale MISP onboarder artifacts from any previous run
kubectl -n "$ESIGNET_NS" delete configmap esignet-onboarder-config --ignore-not-found=true
kubectl -n "$ESIGNET_NS" delete secret esignet-onboarder-secrets --ignore-not-found=true
echo "Stale MISP onboarder artifacts cleaned up."

# Copy keycloak resources needed by the onboarder Job. keycloak-env-vars is generic/
# realm-agnostic (no per-instance equivalent exists anywhere in this DSF) so it always
# comes from the shared keycloak namespace. The admin secret and client secrets are
# skippable via SKIP_SHARED_KEYCLOAK_SECRETS for instances (like mosipid) that
# authenticate against their own dedicated Keycloak instead.
$COPY_UTIL configmap keycloak-env-vars "$KEYCLOAK_NS" "$ESIGNET_NS"
if [ "${SKIP_SHARED_KEYCLOAK_SECRETS:-false}" != "true" ]; then
  $COPY_UTIL secret keycloak "$KEYCLOAK_NS" "$ESIGNET_NS"
  $COPY_UTIL secret keycloak-client-secrets "$KEYCLOAK_NS" "$ESIGNET_NS"
fi

# Delete onboarder-namespace ConfigMap so this release owns it with the correct annotation
kubectl -n "$ESIGNET_NS" delete configmap onboarder-namespace --ignore-not-found=true

echo "MISP onboarder pre-install completed."
