#!/bin/bash
# =============================================================================
# eSignet 1.7.1 - Mock RP OIDC Partner Onboarder Pre-install
# =============================================================================
# Copies required secrets/configmaps to esignet namespace before the
# partner-onboarder Job runs.
# =============================================================================
set -euo pipefail

ESIGNET_NS="${ESIGNET_NS:-esignet}"
KEYCLOAK_NS="keycloak"
COPY_UTIL="$WORKDIR/utils/copy-cm-and-secrets/copy_cm_func.sh"

echo "================================================"
echo "eSignet 1.7.1 - Mock RP Onboarder Pre-install"
echo "================================================"

kubectl create namespace "$ESIGNET_NS" --dry-run=client -o yaml | kubectl apply -f -

# Disable Istio sidecar injection — Job pods with sidecars never reach Completed state
kubectl label namespace "$ESIGNET_NS" istio-injection=disabled --overwrite
echo "Istio injection disabled on namespace $ESIGNET_NS."

# Copy keycloak resources needed by the onboarder Job
$COPY_UTIL configmap keycloak-env-vars "$KEYCLOAK_NS" "$ESIGNET_NS"
$COPY_UTIL secret keycloak "$KEYCLOAK_NS" "$ESIGNET_NS"
$COPY_UTIL secret keycloak-client-secrets "$KEYCLOAK_NS" "$ESIGNET_NS"

# Both partner-onboarder charts create a ConfigMap named "onboarder-namespace".
# Delete it before install so this release owns it with the correct annotation.
kubectl -n "$ESIGNET_NS" delete configmap onboarder-namespace --ignore-not-found=true

# Verify eSignet service is running
kubectl -n "$ESIGNET_NS" wait --for=condition=ready pod -l app.kubernetes.io/name=esignet --timeout=480s || \
  { echo "ERROR: eSignet pods not ready after timeout" >&2; exit 1; }

echo "Mock RP onboarder pre-install completed."
