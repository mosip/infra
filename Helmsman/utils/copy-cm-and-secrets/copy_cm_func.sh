#!/bin/bash
# Copy configmap and secret from one namespace to another.
# ./copy_cm_func.sh <resource> <configmap_name> <source_namespace> <destination_namespace> [name]
# Parameters:
#   resource: configmap|secret
#   name: Optional new name of the configmap or secret in destination namespace.  This may be needed if there is
#         clash of names

if [ $1 = "configmap" ]
then
  RESOURCE=configmap
elif [ $1 = "secret" ]
then
  RESOURCE=secret
else
  echo "Incorrect resource $1. Exiting.."
  exit 1
fi

# Function to strip Helm ownership annotations and other metadata that causes conflicts
# Uses yq for YAML-aware metadata removal to avoid accidentally removing legitimate data
strip_metadata() {
  local src_ns="$1"
  local dst_ns="$2"
  
  # Check if yq is available, fall back to anchored grep patterns if not
  if command -v yq &> /dev/null; then
    # YAML-aware metadata removal using yq
    yq eval "
      .metadata.namespace = \"$dst_ns\" |
      del(.metadata.uid) |
      del(.metadata.resourceVersion) |
      del(.metadata.creationTimestamp) |
      del(.metadata.generation) |
      del(.metadata.selfLink) |
      del(.metadata.annotations.\"meta.helm.sh/release-name\") |
      del(.metadata.annotations.\"meta.helm.sh/release-namespace\") |
      del(.metadata.annotations.\"helm.sh/chart\") |
      del(.metadata.labels.\"app.kubernetes.io/managed-by\")
    " -
  else
    # Fallback: Use anchored patterns to match only metadata keys (not content)
    sed 's/namespace: '$src_ns'/namespace: '$dst_ns'/g' | \
    grep -v "^  meta.helm.sh/release-name:" | \
    grep -v "^  meta.helm.sh/release-namespace:" | \
    grep -v "^  app.kubernetes.io/managed-by: Helm" | \
    grep -v "^  helm.sh/chart:" | \
    grep -v "^  creationTimestamp:" | \
    grep -v "^  resourceVersion:" | \
    grep -v "^  uid:"
  fi
}

if [ $# -ge 5 ]
then
   kubectl -n $4 delete --ignore-not-found=true $RESOURCE $5
   kubectl -n $3 get $RESOURCE $2 -o yaml | strip_metadata $3 $4 | sed "s/name: $2/name: $5/g" | kubectl -n $4 create -f -  
else
   kubectl -n $4 delete --ignore-not-found=true $RESOURCE $2
   kubectl -n $3 get $RESOURCE $2 -o yaml | strip_metadata $3 $4 | kubectl -n $4 create -f -  
fi 
