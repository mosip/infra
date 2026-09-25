#!/bin/bash
# =============================================================================
# eSignet Standalone 2.0.0 - eSignet MOCK Service Pre-install
# =============================================================================
# Wrapper: sets ESIGNET_NS=esignet-go-mock, runs base esignet preinstall (copies
# postgres, redis, kafka, keycloak and db-common-secrets config/secrets), then runs
# the captcha setup so the esignet-captcha secret exists in esignet-go-mock before
# the eSignet pod starts (the pod reads its site key via secretKeyRef). The mosipid
# and sunbird wrappers do the same for their own captcha secrets.
# =============================================================================
set -euo pipefail

export ESIGNET_NS="esignet-go-mock"

"$WORKDIR/hooks/esignet-standalone-2.0.0/esignet-preinstall.sh"
"$WORKDIR/hooks/esignet-standalone-2.0.0/captcha-postinstall.sh"

echo "eSignet MOCK pre-install completed."
