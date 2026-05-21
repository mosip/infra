#!/bin/bash
# =============================================================================
# eSignet 1.7.1 - Config-Server eSignet Post-install
# =============================================================================
# Copies the esignet-config-server-share ConfigMap (created by the
# config-server chart in the esignet namespace) to esignet-cre,
# esignet-qa11, and esignet-sunbird so those instances can locate
# the config-server.
# =============================================================================
set -euo pipefail

SOURCE_NS="esignet"
COPY_UTIL="$WORKDIR/utils/copy-cm-and-secrets/copy_cm_func.sh"
CM_NAME="esignet-config-server-share"

echo "================================================"
echo "eSignet 1.7.1 - Config-Server eSignet Post-install"
echo "================================================"

for TARGET_NS in esignet-cre esignet-qa11 esignet-sunbird; do
  echo "Copying $CM_NAME from $SOURCE_NS to $TARGET_NS"
  $COPY_UTIL configmap "$CM_NAME" "$SOURCE_NS" "$TARGET_NS"
done

echo "Config-server share configmap propagation completed."
