#!/bin/bash
# =============================================================================
# eSignet 1.7.1 - SoftHSM eSignet Post-install
# =============================================================================
# Based on: deploy/esignet/install.sh (copy_cm_func.sh calls for softhsm)
# Shares SoftHSM configmap and secrets from softhsm namespace to esignet
# namespace after SoftHSM deployment.
#
# Environment Variables:
#   SOFTHSM_NS   - SoftHSM namespace (default: softhsm)
#   ESIGNET_NS   - eSignet namespace (default: esignet)
# =============================================================================
set -euo pipefail

SOFTHSM_NS="${SOFTHSM_NS:-softhsm}"
ESIGNET_NS="${ESIGNET_NS:-esignet}"
COPY_UTIL="$WORKDIR/utils/copy-cm-and-secrets/copy_cm_func.sh"

echo "================================================"
echo "eSignet 1.7.1 - SoftHSM eSignet Post-install"
echo "================================================"

# --- Step 1: Wait for SoftHSM pod to be ready ---
echo "Waiting for SoftHSM pod to be ready..."
kubectl -n "$SOFTHSM_NS" wait --for=condition=ready pod -l app.kubernetes.io/instance=esignet-softhsm --timeout=300s || \
  echo "WARNING: SoftHSM pod not ready yet. Continuing with configmap/secret copy."

# --- Step 2: Copy esignet-softhsm-share configmap to esignet namespace ---
echo "Copying esignet-softhsm-share configmap to $ESIGNET_NS namespace"
$COPY_UTIL configmap esignet-softhsm-share "$SOFTHSM_NS" "$ESIGNET_NS" 2>/dev/null || \
  echo "WARNING: esignet-softhsm-share configmap not found in $SOFTHSM_NS"

# --- Step 3: Copy esignet-softhsm secret to esignet namespace ---
echo "Copying esignet-softhsm secret to $ESIGNET_NS namespace"
$COPY_UTIL secret esignet-softhsm "$SOFTHSM_NS" "$ESIGNET_NS" 2>/dev/null || \
  echo "WARNING: esignet-softhsm secret not found in $SOFTHSM_NS"

echo "SoftHSM eSignet post-install completed."
