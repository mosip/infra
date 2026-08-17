#!/bin/bash
# =============================================================================
# eSignet 1.7.1 - Config-Server eSignet Post-install
# =============================================================================
# Copies esignet-config-server-share CM from esignet-mock ns to mosipid/sunbird,
# then patches active_profile_env and spring_config_label_env per namespace
# so each instance points to the correct config server profile and Git label.
#
# Environment variables (set in GitHub Actions workflow):
#   ESIGNET_MOSIPID_SPRING_CONFIG_LABEL  - Git label for esignet-mosipid (default: develop)
# =============================================================================
set -euo pipefail

SOURCE_NS="esignet-mock"
COPY_UTIL="$WORKDIR/utils/copy-cm-and-secrets/copy_cm_func.sh"
CM_NAME="esignet-config-server-share"

MOSIPID_SPRING_LABEL="${ESIGNET_MOSIPID_SPRING_CONFIG_LABEL:-develop}"

echo "================================================"
echo "eSignet 1.7.1 - Config-Server eSignet Post-install"
echo "================================================"

for TARGET_NS in esignet-mosipid esignet-sunbird; do
  echo "Copying $CM_NAME from $SOURCE_NS to $TARGET_NS"
  $COPY_UTIL configmap "$CM_NAME" "$SOURCE_NS" "$TARGET_NS"
done

echo "Patching $CM_NAME in esignet-mosipid (active_profile_env=mosipid, spring_config_label_env=$MOSIPID_SPRING_LABEL)"
kubectl -n esignet-mosipid patch configmap "$CM_NAME" --type merge \
  -p "{\"data\":{\"active_profile_env\":\"mosipid\",\"spring_config_label_env\":\"$MOSIPID_SPRING_LABEL\"}}"

echo "Config-server share configmap propagation and patching completed."
