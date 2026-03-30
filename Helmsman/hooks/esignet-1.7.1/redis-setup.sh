#!/bin/bash
# =============================================================================
# eSignet 1.7.1 - Redis Post-install Setup
# =============================================================================
# Based on: deploy/redis/install.sh + deploy/install-prereq.sh (redis section)
# Creates redis-config configmap and shares Redis credentials with the
# esignet namespace after Redis deployment.
#
# Environment Variables:
#   ESIGNET_NS   - eSignet namespace (default: esignet)
# =============================================================================
set -euo pipefail

ESIGNET_NS="${ESIGNET_NS:-esignet}"
REDIS_NS="redis"

echo "================================================"
echo "eSignet 1.7.1 - Redis Post-install Setup"
echo "================================================"

# --- Step 1: Wait for Redis to be ready ---
echo "Waiting for Redis pods to be ready..."
kubectl -n "$REDIS_NS" wait --for=condition=ready pod -l app.kubernetes.io/name=redis --timeout=300s || \
  echo "WARNING: Redis pods not ready after timeout, continuing"

# --- Step 2: Apply redis-config configmap in redis namespace ---
# Source: deploy/redis/redis-config.yaml
echo "Creating redis-config configmap in $REDIS_NS namespace"
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: redis-config
  namespace: ${REDIS_NS}
  labels:
    app: redis
data:
  redis-host: "redis-master-0.redis-headless.redis.svc.cluster.local"
  redis-port: "6379"
EOF

# --- Step 3: Copy redis-config configmap to esignet namespace ---
# Source: deploy/esignet/install.sh -> ../copy_cm_func.sh configmap redis-config redis esignet
echo "Copying redis-config configmap to $ESIGNET_NS namespace"
kubectl -n "$REDIS_NS" get configmap redis-config -o yaml | \
  sed "s/namespace: $REDIS_NS/namespace: $ESIGNET_NS/g" | \
  kubectl apply -f -

# --- Step 4: Copy redis secret to esignet namespace ---
# Source: deploy/esignet/install.sh -> ../copy_cm_func.sh secret redis redis esignet
echo "Copying redis secret to $ESIGNET_NS namespace"
kubectl -n "$REDIS_NS" get secret redis -o yaml | \
  sed "s/namespace: $REDIS_NS/namespace: $ESIGNET_NS/g" | \
  kubectl apply -f -

echo "Redis setup completed. Config and credentials shared with $ESIGNET_NS namespace."
