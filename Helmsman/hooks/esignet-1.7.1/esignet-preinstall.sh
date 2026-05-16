#!/bin/bash
# =============================================================================
# eSignet 1.7.1 - eSignet Service Pre-install
# =============================================================================
# Based on: deploy/esignet/install.sh
# Prepares esignet namespace with all required configmaps and secrets
# (softhsm, postgres, redis) before eSignet helm chart deployment.
#
# Environment Variables:
#   ESIGNET_NS            - eSignet namespace (default: esignet)
#   ENABLE_INSECURE       - Set to "true" if no valid SSL (default: false)
#   SERVICE_MONITOR_FLAG  - Enable prometheus service monitor (default: false)
# =============================================================================
set -euo pipefail

ESIGNET_NS="${ESIGNET_NS:-esignet}"
SOFTHSM_NS="${SOFTHSM_NS:-softhsm}"
POSTGRES_NS="postgres"
REDIS_NS="redis"
COPY_UTIL="$WORKDIR/utils/copy-cm-and-secrets/copy_cm_func.sh"

echo "================================================"
echo "eSignet 1.7.1 - eSignet Service Pre-install"
echo "================================================"

# --- Step 1: Ensure esignet namespace exists with istio ---
echo "Setting up $ESIGNET_NS namespace"
kubectl create namespace "$ESIGNET_NS" --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace "$ESIGNET_NS" istio-injection=enabled --overwrite

# --- Step 2: Update helm repos ---
helm repo add mosip https://mosip.github.io/mosip-helm || true
helm repo update

# --- Step 3: Copy configmaps from other namespaces ---
echo "Copying esignet-softhsm-share configmap from $SOFTHSM_NS"
$COPY_UTIL configmap esignet-softhsm-share "$SOFTHSM_NS" "$ESIGNET_NS" 2>/dev/null || \
  echo "WARNING: esignet-softhsm-share configmap not found in $SOFTHSM_NS"

echo "Copying postgres-config configmap from $POSTGRES_NS"
$COPY_UTIL configmap postgres-config "$POSTGRES_NS" "$ESIGNET_NS" 2>/dev/null || \
  echo "WARNING: postgres-config configmap not found in $POSTGRES_NS"

echo "Copying redis-config configmap from $REDIS_NS"
$COPY_UTIL configmap redis-config "$REDIS_NS" "$ESIGNET_NS" 2>/dev/null || \
  echo "WARNING: redis-config configmap not found in $REDIS_NS"

# --- Step 4: Copy secrets from other namespaces ---
echo "Copying esignet-softhsm secret from $SOFTHSM_NS"
$COPY_UTIL secret esignet-softhsm "$SOFTHSM_NS" "$ESIGNET_NS" 2>/dev/null || \
  echo "WARNING: esignet-softhsm secret not found in $SOFTHSM_NS"

echo "Copying redis secret from $REDIS_NS"
$COPY_UTIL secret redis "$REDIS_NS" "$ESIGNET_NS" 2>/dev/null || \
  echo "WARNING: redis secret not found in $REDIS_NS"

echo "eSignet pre-install completed. All configmaps and secrets copied."
