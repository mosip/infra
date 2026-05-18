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
MINIO_NS="minio"
COPY_UTIL="$WORKDIR/utils/copy-cm-and-secrets/copy_cm_func.sh"

echo "================================================"
echo "eSignet 1.7.1 - Mock RP Onboarder Pre-install"
echo "================================================"

kubectl create namespace "$ESIGNET_NS" --dry-run=client -o yaml | kubectl apply -f -

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

# Both partner-onboarder charts create a ConfigMap named "onboarder-namespace".
# Delete it before install so this release owns it with the correct annotation.
kubectl -n "$ESIGNET_NS" delete configmap onboarder-namespace --ignore-not-found=true

# Verify eSignet service is running
kubectl -n "$ESIGNET_NS" wait --for=condition=ready pod -l app.kubernetes.io/name=esignet --timeout=480s || \
  { echo "ERROR: eSignet pods not ready after timeout" >&2; exit 1; }

echo "Mock RP onboarder pre-install completed."
