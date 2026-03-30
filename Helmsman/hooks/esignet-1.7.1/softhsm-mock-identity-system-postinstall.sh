#!/bin/bash
# =============================================================================
# eSignet 1.7.1 - SoftHSM Mock Identity System Post-install
# =============================================================================
# Shares SoftHSM mock identity system configmap with esignet namespace.
# =============================================================================
set -euo pipefail

echo "================================================"
echo "eSignet 1.7.1 - SoftHSM Mock Identity System Post-install"
echo "================================================"

# Wait for SoftHSM mock identity pod to be ready
kubectl -n softhsm wait --for=condition=ready pod -l app.kubernetes.io/instance=softhsm-mock-identity-system --timeout=300s 2>/dev/null || \
  echo "WARNING: SoftHSM mock identity system pod not yet ready."

# Share SoftHSM mock identity configmap with esignet namespace
MOCK_HSM_PIN=$(kubectl -n softhsm get secret softhsm-mock-identity-system -o jsonpath='{.data.security-pin}' 2>/dev/null || echo "")

if [ -n "$MOCK_HSM_PIN" ]; then
  kubectl -n esignet create configmap softhsm-mock-identity-system-share \
    --from-literal=softhsm-pin="$(echo -n "$MOCK_HSM_PIN" | base64 -d)" \
    --dry-run=client -o yaml | kubectl apply -f -
  echo "SoftHSM mock identity system credentials shared with esignet namespace."
else
  echo "WARNING: SoftHSM mock identity system secret not found."
fi

echo "SoftHSM mock identity system post-install completed."
