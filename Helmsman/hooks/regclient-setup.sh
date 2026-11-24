#!/bin/bash
# pre-install / pre-upgrade hook of regclient (mosip-platform-1.2.1.x mosip-dsf).
# Copies artifactory-1202-share (Artifactory 1.2.0.2, read by regclient's envFrom)
# into the regclient namespace. Checks the source first: copy_cm_func.sh deletes
# the destination before copying, so a missing source would otherwise leave
# regclient without the ConfigMap.
set -euo pipefail

SRC_NS=artifactory-1202
CM=artifactory-1202-share
NS=regclient
COPY_UTIL="$WORKDIR/utils/copy-cm-and-secrets/copy_cm_func.sh"

if ! kubectl -n "$SRC_NS" get configmap "$CM" >/dev/null 2>&1; then
  echo "ERROR: configmap $CM not found in namespace $SRC_NS — is the artifactory-1202 release deployed?" >&2
  echo "       Leaving $NS unchanged." >&2
  exit 1
fi

"$COPY_UTIL" configmap "$CM" "$SRC_NS" "$NS"
echo "Copied $CM from $SRC_NS to $NS"
