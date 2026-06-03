#!/bin/bash
# =============================================================================
# eSignet 1.7.1 - OIDC UI Pre-install
# =============================================================================
# Based on: deploy/oidc-ui/install.sh
# Waits for eSignet service readiness before deploying OIDC UI.
# Theme, language, and provider name are configured via DSF helm set values.
#
# Environment Variables:
#   ESIGNET_NS   - eSignet namespace (default: esignet)
# =============================================================================
set -euo pipefail

ESIGNET_NS="${ESIGNET_NS:-esignet}"

echo "================================================"
echo "eSignet 1.7.1 - OIDC UI Pre-install"
echo "================================================"

# --- Step 1: Ensure esignet namespace exists ---
kubectl create namespace "$ESIGNET_NS" --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace "$ESIGNET_NS" istio-injection=enabled --overwrite

# --- Step 2: Update helm repos ---
helm repo add mosip https://mosip.github.io/mosip-helm || true
helm repo update

# --- Step 3: Wait for eSignet service to be available ---
# Source: deploy/oidc-ui/install.sh - eSignet must be running before OIDC UI
echo "Waiting for eSignet service to be ready..."
kubectl -n "$ESIGNET_NS" wait --for=condition=ready pod -l app.kubernetes.io/name=esignet --timeout=300s 2>/dev/null || \
  echo "WARNING: eSignet pods not yet ready. OIDC UI may need to retry connections."

echo "OIDC UI pre-install completed."
