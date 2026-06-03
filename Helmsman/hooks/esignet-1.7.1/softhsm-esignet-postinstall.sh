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

echo "================================================"
echo "eSignet 1.7.1 - SoftHSM eSignet Post-install"
echo "================================================"

# --- Step 1: Wait for SoftHSM pod to be ready ---
echo "Waiting for SoftHSM pod to be ready..."
kubectl -n "$SOFTHSM_NS" wait --for=condition=ready pod -l app.kubernetes.io/instance=esignet-softhsm --timeout=300s || \
  echo "WARNING: SoftHSM pod not ready yet. Continuing with configmap/secret copy."

# --- Step 2: Copy esignet-softhsm-share configmap to esignet namespace ---
# Source: deploy/esignet/install.sh -> ../copy_cm_func.sh configmap esignet-softhsm-share softhsm esignet
echo "Copying esignet-softhsm-share configmap to $ESIGNET_NS namespace"
if kubectl -n "$SOFTHSM_NS" get configmap esignet-softhsm-share &>/dev/null; then
  kubectl -n "$SOFTHSM_NS" get configmap esignet-softhsm-share -o yaml | \
    sed "s/namespace: $SOFTHSM_NS/namespace: $ESIGNET_NS/g" | \
    kubectl apply -f -
  echo "esignet-softhsm-share configmap copied."
else
  echo "WARNING: esignet-softhsm-share configmap not found in $SOFTHSM_NS."
  echo "SoftHSM helm chart may create it on first use."
fi

# --- Step 3: Copy esignet-softhsm secret to esignet namespace ---
# Source: deploy/esignet/install.sh -> ../copy_cm_func.sh secret esignet-softhsm softhsm esignet
echo "Copying esignet-softhsm secret to $ESIGNET_NS namespace"
if kubectl -n "$SOFTHSM_NS" get secret esignet-softhsm &>/dev/null; then
  kubectl -n "$SOFTHSM_NS" get secret esignet-softhsm -o yaml | \
    sed "s/namespace: $SOFTHSM_NS/namespace: $ESIGNET_NS/g" | \
    kubectl apply -f -
  echo "esignet-softhsm secret copied."
else
  echo "WARNING: esignet-softhsm secret not found in $SOFTHSM_NS."
fi

echo "SoftHSM eSignet post-install completed."
