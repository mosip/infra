#!/bin/bash
# =============================================================================
# eSignet 1.7.1 - Kernel Services Pre-install
# =============================================================================
# Based on: esignet-signup/deploy/kernel/install.sh
# Creates kernel namespace, domain-config configmap, and optionally copies
# artifactory-share and config-server-share configmaps if available.
#
# This script is idempotent — safe to run multiple times (used as preInstall
# for authmanager, auditmanager, and otpmanager which run in parallel).
#
# Environment Variables:
#   MOSIP_API_HOST           - External API host (e.g. api.sandbox.xyz.net)
#   MOSIP_API_INTERNAL_HOST  - Internal API host (e.g. api-internal.sandbox.xyz.net)
# =============================================================================
set -euo pipefail

KERNEL_NS="kernel"
API_HOST="${MOSIP_API_HOST:-}"
API_INTERNAL_HOST="${MOSIP_API_INTERNAL_HOST:-}"

echo "================================================"
echo "eSignet 1.7.1 - Kernel Pre-install"
echo "================================================"

# --- Step 1: Ensure kernel namespace exists with istio ---
kubectl create namespace "$KERNEL_NS" --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace "$KERNEL_NS" istio-injection=enabled --overwrite

# --- Step 2: Create domain-config configmap ---
# Source: deploy/kernel/install.sh - creates domain-config for authmanager etc.
echo "Creating domain-config configmap in $KERNEL_NS"
kubectl -n "$KERNEL_NS" create configmap domain-config \
  --from-literal=mosip-api-host="$API_HOST" \
  --from-literal=mosip-api-internal-host="$API_INTERNAL_HOST" \
  --dry-run=client -o yaml | kubectl apply -f -

# --- Step 3: Copy optional configmaps from artifactory and config-server ---
# Source: deploy/kernel/install.sh - copy_cm_func.sh calls
# These may not exist in a minimal standalone setup — failures are non-fatal.
for CM in artifactory-share config-server-share; do
  for SRC_NS in artifactory config-server; do
    if kubectl -n "$SRC_NS" get configmap "$CM" &>/dev/null 2>&1; then
      echo "Copying $CM from $SRC_NS to $KERNEL_NS"
      kubectl -n "$SRC_NS" get configmap "$CM" -o yaml | \
        sed "s|^\(\s*namespace:\) $SRC_NS$|\1 $KERNEL_NS|" | \
        kubectl apply -f -
      break
    fi
  done
done

echo "Kernel pre-install completed."
