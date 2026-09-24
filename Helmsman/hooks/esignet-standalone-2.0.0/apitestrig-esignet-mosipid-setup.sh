#!/bin/bash
# =============================================================================
# eSignet Standalone 2.0.0 - eSignet-MOSIPID API Testrig Pre-install Setup
# =============================================================================
# esignet-mosipid-apitestrig now deploys the dedicated mosip/esignet-apitestrig chart
# (the Go-harness rewrite - see https://github.com/mosip/esignet/blob/v2.0.0/deploy/esignet-apitestrig/install.sh),
# which manages its own Secret/ConfigMap from set: values directly - no pre-staged
# secrets needed, unlike the old generic mosip/apitestrig chart this replaces.
#
# The only job left here: delete the unmanaged s3/db/apitestrig ConfigMaps and the
# s3-esignet-mosipid-apitestrig/apitestrig-esignet-mosipid-apitestrig Secrets the OLD
# chart's own preInstall hook used to create directly via kubectl (Helm never owned
# them, so switching charts under the same release name won't clean them up on its own).
# =============================================================================
set -euo pipefail

NS=esignet-mosipid

echo "================================================"
echo "eSignet Standalone 2.0.0 - eSignet-MOSIPID API Testrig Pre-install"
echo "================================================"

echo "Deleting stale testrig resources from the old mosip/apitestrig-based release in $NS"
kubectl -n "$NS" delete --ignore-not-found=true configmap s3 db apitestrig
kubectl -n "$NS" delete --ignore-not-found=true secret s3-esignet-mosipid-apitestrig apitestrig-esignet-mosipid-apitestrig

echo "eSignet-MOSIPID API Testrig pre-install setup completed."
