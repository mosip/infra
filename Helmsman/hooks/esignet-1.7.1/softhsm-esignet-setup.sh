#!/bin/bash
# =============================================================================
# eSignet 1.7.1 - SoftHSM eSignet Pre-install Setup
# =============================================================================
# Based on: deploy/softhsm/install.sh
# Creates softhsm namespace and prepares for SoftHSM deployment.
#
# Environment Variables:
#   SOFTHSM_NS   - SoftHSM namespace (default: softhsm)
# =============================================================================
set -euo pipefail

SOFTHSM_NS="${SOFTHSM_NS:-softhsm}"

echo "================================================"
echo "eSignet 1.7.1 - SoftHSM eSignet Pre-install"
echo "================================================"

# --- Create softhsm namespace ---
echo "Creating $SOFTHSM_NS namespace"
kubectl create namespace "$SOFTHSM_NS" --dry-run=client -o yaml | kubectl apply -f -

# --- Label namespace for Istio sidecar injection ---
echo "Applying Istio injection label"
kubectl label namespace "$SOFTHSM_NS" istio-injection=enabled --overwrite

# --- Update helm repos ---
echo "Updating helm repos"
helm repo update

echo "SoftHSM eSignet pre-install setup completed."
