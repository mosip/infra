#!/bin/bash
# =============================================================================
# eSignet 1.7.1 - eSignet Service Pre-install
# =============================================================================
# Based on: deploy/esignet/install.sh
# Prepares esignet namespace with postgres and redis configmaps/secrets
# before eSignet helm chart deployment.
#
# softhsm-esignet deploys in the esignet namespace (priority -14, before
# esignet at -12), so esignet-softhsm-share is already present — no copy needed.
#
# Environment Variables:
#   ESIGNET_NS   - eSignet namespace (default: esignet)
# =============================================================================
set -euo pipefail

ESIGNET_NS="${ESIGNET_NS:-esignet}"
POSTGRES_NS="postgres"
REDIS_NS="redis"
COPY_UTIL="$WORKDIR/utils/copy-cm-and-secrets/copy_cm_func.sh"

echo "================================================"
echo "eSignet 1.7.1 - eSignet Service Pre-install"
echo "================================================"

# --- Step 1: Ensure esignet namespace exists with Istio ---
echo "Setting up $ESIGNET_NS namespace"
kubectl create namespace "$ESIGNET_NS" --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace "$ESIGNET_NS" istio-injection=enabled --overwrite

# --- Step 2: Update helm repos ---
helm repo add mosip https://mosip.github.io/mosip-helm || true
helm repo update

# --- Step 3: Copy configmaps from other namespaces ---
# All external services (postgres, redis) are guaranteed deployed before
# esignet-dsf runs.
echo "Copying postgres-config configmap from $POSTGRES_NS"
$COPY_UTIL configmap postgres-config "$POSTGRES_NS" "$ESIGNET_NS"

echo "Copying redis-config configmap from $REDIS_NS"
$COPY_UTIL configmap redis-config "$REDIS_NS" "$ESIGNET_NS"

# --- Step 4: Copy secrets from other namespaces ---
echo "Copying redis secret from $REDIS_NS"
$COPY_UTIL secret redis "$REDIS_NS" "$ESIGNET_NS"

echo "eSignet pre-install completed."
