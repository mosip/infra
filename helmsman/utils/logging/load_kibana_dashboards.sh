#!/bin/sh

# Exit on any error
set -e

# Check required input
if [ $# -lt 1 ]; then
  echo "Usage: ./load_kibana_dashboards.sh <dashboards folder> [kubeconfig file]"
  exit 1
fi

# Optional kubeconfig
if [ $# -ge 2 ]; then
  export KUBECONFIG=$2
fi

# Fetch default values from config map
KIBANA_URL=$(kubectl get cm global -o jsonpath={.data.mosip-kibana-host})
INSTALL_NAME=$(kubectl get cm global -o jsonpath={.data.installation-name})

# Optional: override using environment variables if provided
KIBANA_URL="${KIBANA_HOST_OVERRIDE:-$KIBANA_URL}"
INSTALL_NAME="${INSTALL_NAME_OVERRIDE:-$INSTALL_NAME}"

# Temporary file
TEMP_OBJ_FILE="/tmp/temp_kib_obj.ndjson"

# Process each .ndjson file
for file in ${1%/}/*.ndjson; do
  cp "$file" "$TEMP_OBJ_FILE"
  sed -i.bak "s/___DB_PREFIX_INDEX___/$INSTALL_NAME/g" "$TEMP_OBJ_FILE"

  echo
  echo "Loading: $file"
  curl -XPOST "https://${KIBANA_URL%/}/api/saved_objects/_import" \
    -H "kbn-xsrf: true" --form file=@"$TEMP_OBJ_FILE"

  rm "$TEMP_OBJ_FILE" "$TEMP_OBJ_FILE.bak"
done
