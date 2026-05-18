#!/bin/bash
# =============================================================================
# eSignet 1.7.1 - eSignet MISP Partner Onboarder Pre-install
# =============================================================================
# Prepares the esignet namespace for the MISP onboarder Job:
#   - Disables Istio sidecar injection so the Job pod can reach Completed state
#   - Deletes stale MISP onboarder artifacts from previous runs (idempotency)
#   - Copies keycloak resources and builds the s3 secret
#   - Deletes onboarder-namespace ConfigMap so this release owns it cleanly
#   - Waits for the esignet pod to be ready before the Job starts
# Only used with mosip-identity-plugin (plugin 2).
# =============================================================================
set -euo pipefail

ESIGNET_NS="${ESIGNET_NS:-esignet}"
KEYCLOAK_NS="keycloak"
MINIO_NS="minio"
COPY_UTIL="$WORKDIR/utils/copy-cm-and-secrets/copy_cm_func.sh"

echo "================================================"
echo "eSignet 1.7.1 - MISP Onboarder Pre-install"
echo "================================================"

kubectl create namespace "$ESIGNET_NS" --dry-run=client -o yaml | kubectl apply -f -

# Disable Istio sidecar injection — Job pods with sidecars never reach Completed state
kubectl label namespace "$ESIGNET_NS" istio-injection=disabled --overwrite
echo "Istio injection disabled on namespace $ESIGNET_NS."

# Delete stale MISP onboarder artifacts from any previous run
kubectl -n "$ESIGNET_NS" delete configmap esignet-onboarder-config --ignore-not-found=true
kubectl -n "$ESIGNET_NS" delete secret esignet-onboarder-secrets --ignore-not-found=true
echo "Stale MISP onboarder artifacts cleaned up."

# Copy keycloak resources needed by the onboarder Job
$COPY_UTIL configmap keycloak-env-vars "$KEYCLOAK_NS" "$ESIGNET_NS"
$COPY_UTIL secret keycloak "$KEYCLOAK_NS" "$ESIGNET_NS"
$COPY_UTIL secret keycloak-client-secrets "$KEYCLOAK_NS" "$ESIGNET_NS"

# Build s3 secret with the key the partner-onboarder chart expects (s3-user-secret)
# MinIO Bitnami chart stores the root password under the root-password key
S3_PASSWORD=$(kubectl -n "$MINIO_NS" get secret s3 -o jsonpath='{.data.root-password}' 2>/dev/null | base64 -d || echo "")
if [ -n "$S3_PASSWORD" ]; then
  kubectl -n "$ESIGNET_NS" create secret generic s3 \
    --from-literal=s3-user-secret="$S3_PASSWORD" \
    --dry-run=client -o yaml | kubectl apply -f -
  echo "s3 secret created/updated in $ESIGNET_NS."
else
  echo "WARNING: could not read root-password from minio/$MINIO_NS s3 secret — MinIO reports may fail." >&2
fi

# Delete onboarder-namespace ConfigMap so this release owns it with the correct annotation
kubectl -n "$ESIGNET_NS" delete configmap onboarder-namespace --ignore-not-found=true

# Verify eSignet service is running before the onboarder Job starts
kubectl -n "$ESIGNET_NS" wait --for=condition=ready pod -l app.kubernetes.io/name=esignet --timeout=480s || \
  { echo "ERROR: eSignet pods not ready after timeout" >&2; exit 1; }

echo "MISP onboarder pre-install completed."
