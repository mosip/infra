#!/bin/bash
# =============================================================================
# eSignet MISP Partner Onboarder - MOSIPID Pre-install
# =============================================================================
# Wrapper: sets ESIGNET_NS=esignet-mosipid, then runs the base MISP onboarder
# pre-install (copies keycloak resources, cleans up stale artifacts).
# =============================================================================
set -euo pipefail

export ESIGNET_NS="esignet-mosipid"

"$WORKDIR/hooks/esignet-standalone-2.0.0/esignet-misp-onboarder-preinstall.sh"
