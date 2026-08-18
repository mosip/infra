#!/bin/bash
# =============================================================================
# eSignet 1.7.1 - SoftHSM Mock Identity System Pre-install
# =============================================================================
# Prepares SoftHSM for the mock identity system.
# =============================================================================
set -euo pipefail

echo "================================================"
echo "eSignet 1.7.1 - SoftHSM Mock Identity System Pre-install"
echo "================================================"

# Ensure softhsm namespace exists
kubectl create namespace softhsm --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace softhsm istio-injection=enabled --overwrite

echo "SoftHSM mock identity system pre-install completed."
