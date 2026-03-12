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
# Source: deploy/esignet/install.sh -> copy_cm_func.sh calls

# Copy esignet-softhsm-share configmap from softhsm namespace
echo "Copying esignet-softhsm-share configmap from $SOFTHSM_NS"
if kubectl -n "$SOFTHSM_NS" get configmap esignet-softhsm-share &>/dev/null; then
  kubectl -n "$ESIGNET_NS" delete --ignore-not-found=true configmap esignet-softhsm-share
  kubectl -n "$SOFTHSM_NS" get configmap esignet-softhsm-share -o yaml | \
    sed "s/namespace: $SOFTHSM_NS/namespace: $ESIGNET_NS/g" | \
    kubectl -n "$ESIGNET_NS" create -f -
else
  echo "WARNING: esignet-softhsm-share configmap not found in $SOFTHSM_NS"
fi

# Copy postgres-config configmap from postgres namespace
echo "Copying postgres-config configmap from $POSTGRES_NS"
if kubectl -n "$POSTGRES_NS" get configmap postgres-config &>/dev/null; then
  kubectl -n "$ESIGNET_NS" delete --ignore-not-found=true configmap postgres-config
  kubectl -n "$POSTGRES_NS" get configmap postgres-config -o yaml | \
    sed "s/namespace: $POSTGRES_NS/namespace: $ESIGNET_NS/g" | \
    kubectl -n "$ESIGNET_NS" create -f -
else
  echo "WARNING: postgres-config configmap not found in $POSTGRES_NS"
fi

# Copy redis-config configmap from redis namespace
echo "Copying redis-config configmap from $REDIS_NS"
if kubectl -n "$REDIS_NS" get configmap redis-config &>/dev/null; then
  kubectl -n "$ESIGNET_NS" delete --ignore-not-found=true configmap redis-config
  kubectl -n "$REDIS_NS" get configmap redis-config -o yaml | \
    sed "s/namespace: $REDIS_NS/namespace: $ESIGNET_NS/g" | \
    kubectl -n "$ESIGNET_NS" create -f -
else
  echo "WARNING: redis-config configmap not found in $REDIS_NS"
fi

# --- Step 4: Copy secrets from other namespaces ---

# Copy esignet-softhsm secret from softhsm namespace
echo "Copying esignet-softhsm secret from $SOFTHSM_NS"
if kubectl -n "$SOFTHSM_NS" get secret esignet-softhsm &>/dev/null; then
  kubectl -n "$ESIGNET_NS" delete --ignore-not-found=true secret esignet-softhsm
  kubectl -n "$SOFTHSM_NS" get secret esignet-softhsm -o yaml | \
    sed "s/namespace: $SOFTHSM_NS/namespace: $ESIGNET_NS/g" | \
    kubectl -n "$ESIGNET_NS" create -f -
else
  echo "WARNING: esignet-softhsm secret not found in $SOFTHSM_NS"
fi

# Copy redis secret from redis namespace
echo "Copying redis secret from $REDIS_NS"
if kubectl -n "$REDIS_NS" get secret redis &>/dev/null; then
  kubectl -n "$ESIGNET_NS" delete --ignore-not-found=true secret redis
  kubectl -n "$REDIS_NS" get secret redis -o yaml | \
    sed "s/namespace: $REDIS_NS/namespace: $ESIGNET_NS/g" | \
    kubectl -n "$ESIGNET_NS" create -f -
else
  echo "WARNING: redis secret not found in $REDIS_NS"
fi

echo "eSignet pre-install completed. All configmaps and secrets copied."
