#!/bin/bash
# =============================================================================
# eSignet 1.7.1 - Mock Relying Party Service Sunbird Pre-install
# =============================================================================
# Wrapper: sets ESIGNET_NS=esignet-sunbird and delegates to base mock-rp-service
# preinstall (creates private key secrets in the target namespace).
# =============================================================================
set -euo pipefail
export ESIGNET_NS="esignet-sunbird"
exec "$WORKDIR/hooks/esignet-standalone/mock-relying-party-service-preinstall.sh"
