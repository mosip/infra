#!/bin/bash
# =============================================================================
# eSignet 1.7.1 - Postgres Pre-install
# =============================================================================
# Based on: deploy/install-prereq.sh
# Creates esignet namespace, applies esignet-global configmap, and prepares
# postgres namespace before PostgreSQL helm chart deployment.
#
# Environment Variables:
#   INSTALLATION_DOMAIN  - Base domain (default: sandbox.xyz.net)
#   ESIGNET_NS           - eSignet namespace (default: esignet)
# =============================================================================
set -euo pipefail

ESIGNET_NS="${ESIGNET_NS:-esignet}"
INSTALLATION_DOMAIN="${INSTALLATION_DOMAIN:-sandbox.xyz.net}"

echo "================================================"
echo "eSignet 1.7.1 - Postgres Pre-install"
echo "================================================"

# --- Step 1: Create esignet namespace (referenced by esignet-global configmap) ---
echo "Creating $ESIGNET_NS namespace"
kubectl create namespace "$ESIGNET_NS" --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace "$ESIGNET_NS" istio-injection=enabled --overwrite

# --- Step 2: Apply esignet-global configmap ---
# Source: deploy/esignet-global-cm.yaml.sample
echo "Applying esignet-global configmap in $ESIGNET_NS namespace"
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: esignet-global
  namespace: ${ESIGNET_NS}
data:
  mosip-version: "1.7.1"
  installation-domain: "${INSTALLATION_DOMAIN}"
  mosip-api-host: "api.${INSTALLATION_DOMAIN}"
  mosip-iam-external-host: "iam.${INSTALLATION_DOMAIN}"
  mosip-api-internal-host: "api-internal.${INSTALLATION_DOMAIN}"
  mosip-kafka-host: "kafka.${INSTALLATION_DOMAIN}"
  mosip-esignet-host: "esignet.${INSTALLATION_DOMAIN}"
  mosip-postgres-host: "esignet-postgres.${INSTALLATION_DOMAIN}"
  mosip-signup-host: "signup.${INSTALLATION_DOMAIN}"
  mosip-smtp-host: "smtp.${INSTALLATION_DOMAIN}"
EOF

# --- Step 3: Prepare postgres namespace ---
echo "Creating postgres namespace"
kubectl create namespace postgres --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace postgres istio-injection=enabled --overwrite

echo "Postgres pre-install completed."
