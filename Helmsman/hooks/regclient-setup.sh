#!/bin/bash
# pre-install / pre-upgrade hook of regclient (mosip-platform-1.2.1.x mosip-dsf).
# Copies artifactory-1202-share (Artifactory 1.2.0.2, read by regclient's envFrom)
# into the regclient namespace.
#
# Same transformation as utils/copy-cm-and-secrets/copy_cm_func.sh (namespace set,
# server-managed fields and Helm ownership metadata stripped, other labels and
# annotations kept), but the destination is replaced in place instead of deleted
# first: if anything fails, the ConfigMap regclient already has stays untouched.
set -euo pipefail

SRC_NS=artifactory-1202
CM=artifactory-1202-share
NS=regclient

if ! SRC=$(kubectl -n "$SRC_NS" get configmap "$CM" -o json 2>/dev/null); then
  echo "ERROR: configmap $CM not found in namespace $SRC_NS — is the artifactory-1202 release deployed?" >&2
  echo "       Leaving $NS unchanged." >&2
  exit 1
fi

OBJ=$(printf '%s' "$SRC" | jq --arg ns "$NS" '
  .metadata.namespace = $ns
  | del(.metadata.uid, .metadata.resourceVersion, .metadata.creationTimestamp,
        .metadata.generation, .metadata.selfLink, .metadata.managedFields,
        .metadata.annotations["meta.helm.sh/release-name"],
        .metadata.annotations["meta.helm.sh/release-namespace"],
        .metadata.annotations["helm.sh/chart"],
        .metadata.labels["app.kubernetes.io/managed-by"])')

if kubectl -n "$NS" get configmap "$CM" >/dev/null 2>&1; then
  printf '%s' "$OBJ" | kubectl -n "$NS" replace -f - >/dev/null
else
  printf '%s' "$OBJ" | kubectl -n "$NS" create -f - >/dev/null
fi
echo "Copied $CM from $SRC_NS to $NS"
