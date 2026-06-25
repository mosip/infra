#!/bin/bash
# =============================================================================
# eSignet 1.7.1 - Mock Relying Party Service MOSIPID1 Pre-install
# =============================================================================
# Wrapper: sets ESIGNET_NS=esignet-mosipid1 and delegates to base mock-rp-service
# preinstall (creates private key secrets in the target namespace).
# =============================================================================
set -euo pipefail
export ESIGNET_NS="esignet-mosipid1"
exec "$WORKDIR/hooks/esignet-standalone/mock-relying-party-service-preinstall.sh"
