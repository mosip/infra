#!/bin/bash
# =============================================================================
# eSignet 1.7.1 - Config-Server eSignet Post-install
# =============================================================================
# Copies esignet-config-server-share CM from esignet ns to cre/qa11/sunbird,
# then patches active_profile_env and spring_config_label_env per namespace
# so each instance points to the correct config server profile and Git label.
#
# Environment variables (set in GitHub Actions workflow):
#   ESIGNET_CRE_SPRING_CONFIG_LABEL   - Git label for esignet-cre  (default: develop)
#   ESIGNET_QA11_SPRING_CONFIG_LABEL  - Git label for esignet-qa11 (default: develop)
# =============================================================================
set -euo pipefail

SOURCE_NS="esignet"
COPY_UTIL="$WORKDIR/utils/copy-cm-and-secrets/copy_cm_func.sh"
CM_NAME="esignet-config-server-share"

CRE_SPRING_LABEL="${ESIGNET_CRE_SPRING_CONFIG_LABEL:-develop}"
QA11_SPRING_LABEL="${ESIGNET_QA11_SPRING_CONFIG_LABEL:-develop}"

echo "================================================"
echo "eSignet 1.7.1 - Config-Server eSignet Post-install"
echo "================================================"

for TARGET_NS in esignet-cre esignet-qa11 esignet-sunbird; do
  echo "Copying $CM_NAME from $SOURCE_NS to $TARGET_NS"
  $COPY_UTIL configmap "$CM_NAME" "$SOURCE_NS" "$TARGET_NS"
done

echo "Patching $CM_NAME in esignet-cre (active_profile_env=cre, spring_config_label_env=$CRE_SPRING_LABEL)"
kubectl -n esignet-cre patch configmap "$CM_NAME" --type merge \
  -p "{\"data\":{\"active_profile_env\":\"cre\",\"spring_config_label_env\":\"$CRE_SPRING_LABEL\"}}"

echo "Patching $CM_NAME in esignet-qa11 (active_profile_env=qa-11, spring_config_label_env=$QA11_SPRING_LABEL)"
kubectl -n esignet-qa11 patch configmap "$CM_NAME" --type merge \
  -p "{\"data\":{\"active_profile_env\":\"qa-11\",\"spring_config_label_env\":\"$QA11_SPRING_LABEL\"}}"

echo "Config-server share configmap propagation and patching completed."
