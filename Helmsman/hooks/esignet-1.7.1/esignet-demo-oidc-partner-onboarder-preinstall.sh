#!/bin/bash
# =============================================================================
# eSignet 1.7.1 - Demo OIDC Partner Onboarder Pre-install
# =============================================================================
# Prepares for demo OIDC partner onboarding.
# =============================================================================
set -euo pipefail

echo "================================================"
echo "eSignet 1.7.1 - Demo OIDC Partner Onboarder Pre-install"
echo "================================================"

ESIGNET_NS="${ESIGNET_NS:-esignet}"
MINIO_NS="minio"
COPY_UTIL="$WORKDIR/utils/copy-cm-and-secrets/copy_cm_func.sh"

# Ensure esignet namespace exists
kubectl create namespace "$ESIGNET_NS" --dry-run=client -o yaml | kubectl apply -f -

# Copy s3 secret from minio namespace (required by partner-onboarder Job)
$COPY_UTIL secret s3 "$MINIO_NS" "$ESIGNET_NS"

# Verify eSignet service is running
kubectl -n "$ESIGNET_NS" wait --for=condition=ready pod -l app.kubernetes.io/name=esignet --timeout=480s || \
  { echo "ERROR: eSignet pods not ready after timeout" >&2; exit 1; }

echo "Demo OIDC partner onboarder pre-install completed."
