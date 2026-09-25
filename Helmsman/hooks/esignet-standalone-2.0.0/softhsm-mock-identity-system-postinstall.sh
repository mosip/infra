#!/bin/bash
# =============================================================================
# eSignet 1.7.1 - SoftHSM Mock Identity System Post-install
# =============================================================================
# Copies chart-generated softhsm-mock-identity-system-share configmap
# (PKCS11 slot/token config) from softhsm namespace to esignet-mock namespace.
# The security PIN is handled separately via secret copy in preinstall.
# =============================================================================
set -euo pipefail

SOFTHSM_NS="${SOFTHSM_NS:-softhsm}"
ESIGNET_NS="${ESIGNET_NS:-esignet-mock}"
COPY_UTIL="$WORKDIR/utils/copy-cm-and-secrets/copy_cm_func.sh"

echo "================================================"
echo "eSignet 1.7.1 - SoftHSM Mock Identity System Post-install"
echo "================================================"

# Wait for SoftHSM mock identity pod to be ready
kubectl -n "$SOFTHSM_NS" wait --for=condition=ready pod -l app.kubernetes.io/instance=softhsm-mock-identity-system --timeout=480s || \
  { echo "ERROR: SoftHSM mock identity system pod not ready after timeout" >&2; exit 1; }

# Copy chart-generated PKCS11 configmap to esignet-mock namespace
echo "Copying softhsm-mock-identity-system-share configmap to $ESIGNET_NS"
$COPY_UTIL configmap softhsm-mock-identity-system-share "$SOFTHSM_NS" "$ESIGNET_NS"

echo "SoftHSM mock identity system post-install completed."
