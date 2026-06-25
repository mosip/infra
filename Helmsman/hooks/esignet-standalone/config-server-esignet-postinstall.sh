#!/bin/bash
# =============================================================================
# eSignet 1.7.1 - Config-Server eSignet Post-install
# =============================================================================
# Copies esignet-config-server-share CM from esignet ns to mosipid1/mosipid2/sunbird,
# then patches active_profile_env and spring_config_label_env per namespace
# so each instance points to the correct config server profile and Git label.
#
# Environment variables (set in GitHub Actions workflow):
#   ESIGNET_MOSIPID1_SPRING_CONFIG_LABEL  - Git label for esignet-mosipid1 (default: develop)
#   ESIGNET_MOSIPID2_SPRING_CONFIG_LABEL  - Git label for esignet-mosipid2 (default: develop)
# =============================================================================
set -euo pipefail

SOURCE_NS="esignet"
COPY_UTIL="$WORKDIR/utils/copy-cm-and-secrets/copy_cm_func.sh"
CM_NAME="esignet-config-server-share"

MOSIPID1_SPRING_LABEL="${ESIGNET_MOSIPID1_SPRING_CONFIG_LABEL:-develop}"
MOSIPID2_SPRING_LABEL="${ESIGNET_MOSIPID2_SPRING_CONFIG_LABEL:-develop}"

echo "================================================"
echo "eSignet 1.7.1 - Config-Server eSignet Post-install"
echo "================================================"

for TARGET_NS in esignet-mosipid1 esignet-mosipid2 esignet-sunbird; do
  echo "Copying $CM_NAME from $SOURCE_NS to $TARGET_NS"
  $COPY_UTIL configmap "$CM_NAME" "$SOURCE_NS" "$TARGET_NS"
done

echo "Patching $CM_NAME in esignet-mosipid1 (active_profile_env=mosipid1, spring_config_label_env=$MOSIPID1_SPRING_LABEL)"
kubectl -n esignet-mosipid1 patch configmap "$CM_NAME" --type merge \
  -p "{\"data\":{\"active_profile_env\":\"mosipid1\",\"spring_config_label_env\":\"$MOSIPID1_SPRING_LABEL\"}}"

echo "Patching $CM_NAME in esignet-mosipid2 (active_profile_env=mosipid2, spring_config_label_env=$MOSIPID2_SPRING_LABEL)"
kubectl -n esignet-mosipid2 patch configmap "$CM_NAME" --type merge \
  -p "{\"data\":{\"active_profile_env\":\"mosipid2\",\"spring_config_label_env\":\"$MOSIPID2_SPRING_LABEL\"}}"

echo "Config-server share configmap propagation and patching completed."
