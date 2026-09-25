#!/bin/bash
# =============================================================================
# eSignet 1.7.1 - SoftHSM eSignet Pre-install Setup
# =============================================================================
# Based on: deploy/softhsm/install.sh
# softhsm-esignet deploys in the esignet namespace (v1.7.1 pattern) so
# esignet-softhsm-share configmap is created there directly — no cross-ns copy.
#
# Environment Variables:
#   ESIGNET_NS   - eSignet namespace (default: esignet)
# =============================================================================
set -euo pipefail

ESIGNET_NS="${ESIGNET_NS:-esignet-mock}"

echo "================================================"
echo "eSignet 1.7.1 - SoftHSM eSignet Pre-install"
echo "================================================"

# Ensure esignet namespace exists with Istio injection enabled
echo "Ensuring $ESIGNET_NS namespace exists"
kubectl create namespace "$ESIGNET_NS" --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace "$ESIGNET_NS" istio-injection=enabled --overwrite

# Update helm repos
echo "Updating helm repos"
helm repo update

echo "SoftHSM eSignet pre-install setup completed."
