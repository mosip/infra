#!/bin/bash
# Log file path
echo "[ Set Log File ] : "
sudo mv /tmp/k8s.log /tmp/k8s.log.old || true
LOG_FILE="/tmp/k8s.log"
ENV_FILE_PATH="/etc/environment"

# Redirect stdout and stderr to log file
exec > >(tee -a "$LOG_FILE") 2>&1

# Set commands for error handling.
set -e
set -o errexit   ## set -e : exit the script if any statement returns a non-true return value
set -o nounset   ## set -u : exit the script if you try to use an uninitialized variable
set -o errtrace  # Trace ERR through 'time command' and other functions
set -o pipefail  # Trace ERR through pipes

# Set internal IP address
echo "Instance index: ${index}"

echo "nameserver 8.8.8.8 8.8.4.4" | sudo tee -a /run/systemd/resolve/stub-resolv.conf

echo "file /run/systemd/resolve/stub-resolv.conf"
cat /run/systemd/resolve/stub-resolv.conf

echo "file /etc/resolv.conf"
cat /etc/resolv.conf

export TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
echo "export TOKEN=$TOKEN" | sudo tee -a $ENV_FILE_PATH
echo "export INTERNAL_IP=\"$(curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/local-ipv4)\"" | sudo tee -a $ENV_FILE_PATH
echo "export NODE_NAME=${role}" | sudo tee -a $ENV_FILE_PATH
echo "export CLUSTER_DOMAIN=${cluster_domain}" | sudo tee -a $ENV_FILE_PATH

# Determine the role of the instance using pattern matching
if [[ "${role}" == CONTROL-PLANE-NODE-* ]]; then
  echo "export K8S_ROLE=\"K8S-CONTROL-PLANE-NODE\"" | sudo tee -a $ENV_FILE_PATH
elif [[ "${role}" == ETCD-NODE-* ]]; then
  echo "export K8S_ROLE=\"K8S-ETCD-NODE\"" | sudo tee -a $ENV_FILE_PATH
else
  echo "export K8S_ROLE=\"K8S-WORKER-NODE\"" | sudo tee -a $ENV_FILE_PATH
fi

# Source the environment variables
source $ENV_FILE_PATH
