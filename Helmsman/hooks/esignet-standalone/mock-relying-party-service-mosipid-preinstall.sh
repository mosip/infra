#!/bin/bash
# =============================================================================
# eSignet 1.7.1 - Mock Relying Party Service MOSIPID Pre-install
# =============================================================================
# Wrapper: sets ESIGNET_NS=esignet-mosipid and delegates to base mock-rp-service
# preinstall (creates private key secrets in the target namespace).
# =============================================================================
set -euo pipefail
export ESIGNET_NS="esignet-mosipid"
exec "$WORKDIR/hooks/esignet-standalone/mock-relying-party-service-preinstall.sh"
