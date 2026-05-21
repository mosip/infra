#!/bin/bash
# =============================================================================
# eSignet 1.7.1 - eSignet Sunbird Service Pre-install
# =============================================================================
# Wrapper: sets ESIGNET_NS=esignet-sunbird, runs base esignet preinstall (copies
# postgres + redis config/secrets), then copies esignet-captcha secret from
# the esignet namespace (created by captcha-postinstall.sh for esignet ns).
# =============================================================================
set -euo pipefail

export ESIGNET_NS="esignet-sunbird"
COPY_UTIL="$WORKDIR/utils/copy-cm-and-secrets/copy_cm_func.sh"

"$WORKDIR/hooks/esignet-1.7.1/esignet-preinstall.sh"

echo "Copying esignet-captcha secret from esignet to $ESIGNET_NS"
$COPY_UTIL secret esignet-captcha "esignet" "$ESIGNET_NS"

echo "eSignet Sunbird pre-install completed."
