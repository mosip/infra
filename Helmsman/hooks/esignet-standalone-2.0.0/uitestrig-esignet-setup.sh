#!/bin/bash
# =============================================================================
# eSignet Standalone 2.0.0 - eSignet UI Testrig Pre-install Setup
# =============================================================================
# esignet-uitestrig deploys the dedicated mosip/esignet-uitestrig chart (the
# Java-harness rewrite for eSignet 2.0.0 - see
# https://github.com/mosip/esignet/blob/v2.0.0/deploy/esignet-uitestrig/install.sh),
# into its own esignet-uitestrig namespace, separate from eSignet's own esignet-mock
# namespace (matches install.sh's own NS=esignet-uitestrig / SOURCE_NS=esignet split).
#
# The chart manages its own ConfigMap/Secret entirely from set: values - no
# pre-staged secrets needed. The only job here is namespace bootstrap, same as
# uitestrig-signup-setup.sh's existing pattern for signup-uitestrig.
# =============================================================================
set -euo pipefail

NS=esignet-uitestrig

echo "================================================"
echo "eSignet Standalone 2.0.0 - eSignet UI Testrig Pre-install"
echo "================================================"

echo "Ensuring $NS namespace exists with Istio injection disabled"
kubectl create namespace "$NS" --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace "$NS" istio-injection=disabled --overwrite

echo "eSignet UI Testrig pre-install setup completed."
