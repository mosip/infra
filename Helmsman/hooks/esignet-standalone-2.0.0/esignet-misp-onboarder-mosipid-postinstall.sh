#!/bin/bash
# =============================================================================
# eSignet MISP Partner Onboarder - MOSIPID Post-install
# =============================================================================
# Wrapper: sets ESIGNET_NS=esignet-mosipid and DEPLOYMENT_NAME=esignet-mosipid,
# then runs the base MISP onboarder post-install (validates job completion,
# restarts the esignet-mosipid deployment to pick up the new MISP license key).
# =============================================================================
set -euo pipefail

export ESIGNET_NS="esignet-mosipid"
export DEPLOYMENT_NAME="esignet-mosipid"

"$WORKDIR/hooks/esignet-standalone-2.0.0/esignet-misp-onboarder-postinstall.sh"
