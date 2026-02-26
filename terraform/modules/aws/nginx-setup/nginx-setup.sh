#!/bin/bash

# Log file path
echo "[ Set Log File ] : "
LOG_FILE="/tmp/nginx-setup-$( date +"%d-%h-%Y-%H-%M" ).log"
ENV_FILE_PATH="/etc/environment"
. $ENV_FILE_PATH

# Determine which type of nginx setup based on available variables
# Check for observability-specific variable first (more specific check)
if [ ! -z "$observation_nginx_certs" ]; then
  NGINX_TYPE="observability"
  echo "[ Detected NGINX Type: Observability ] : "
  env | grep observation
elif [ ! -z "$cluster_nginx_certs" ]; then
  NGINX_TYPE="mosip"
  echo "[ Detected NGINX Type: MOSIP ] : "
  env | grep cluster
else
  echo "[ ERROR: Could not determine NGINX type ] : "
  echo "[ Available env vars: ]"
  env | sort
  exit 1
fi

# Redirect stdout and stderr to log file
exec > >(tee -a "$LOG_FILE") 2>&1

# set commands for error handling.
set -e
set -o errexit   ## set -e : exit the script if any statement returns a non-true return value
set -o nounset   ## set -u : exit the script if you try to use an uninitialised variable
set -o errtrace  # trace ERR through 'time command' and other functions
set -o pipefail  # trace ERR through pipes

## Wait for cloud-init to finish (it holds the apt lock on fresh EC2 instances)
echo "[ Waiting for cloud-init to complete ] : "
sudo cloud-init status --wait || true

## Wait for any apt/dpkg lock to be released (unattended-upgrades may still be running)
echo "[ Waiting for apt/dpkg locks to be released ] : "
while sudo fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || \
      sudo fuser /var/lib/apt/lists/lock >/dev/null 2>&1 || \
      sudo fuser /var/cache/apt/archives/lock >/dev/null 2>&1; do
  echo "[ Apt lock held by another process, waiting 10s... ] : "
  sleep 10
done
echo "[ Apt locks are free, proceeding ] : "

## Install Nginx, ssl dependencies
echo "[ Install nginx & ssl dependencies packages ] : "
export DEBIAN_FRONTEND=noninteractive
sudo apt-get update -y
sudo apt-get install -y software-properties-common
sudo add-apt-repository universe -y
sudo apt-get update -y
sudo apt-get install -y letsencrypt certbot python3-certbot-nginx python3-certbot-dns-route53

## Get ssl certificate automatically
if [ "$NGINX_TYPE" == "mosip" ]; then
  cert_type="MOSIP"
else
  cert_type="Observability"
fi
echo "[ Generate SSL certificates from letsencrypt for $cert_type ] : "
sudo certbot certonly --dns-route53 -d "*.${cluster_env_domain}" -d "${cluster_env_domain}" --non-interactive --agree-tos --email "$certbot_email"

## start and enable Nginx
#echo "[ Start & Enable nginx ] : "
#sudo systemctl enable nginx
#sudo systemctl start nginx

cd $working_dir
git clone $k8s_infra_repo_url -b $k8s_infra_branch || true # read it from variables
cd $nginx_location

# Check if install.sh exists before running it
if [ ! -f "./install.sh" ]; then
  echo "[ ERROR: install.sh not found in $nginx_location ] : "
  echo "[ Current directory: $(pwd) ] : "
  ls -la
  exit 1
fi

# AWS-specific fix: Override public IP with private IP BEFORE running install.sh
# In AWS, public IPs cannot be bound to network interfaces, so we need to use private IP instead
if [ "$NGINX_TYPE" == "mosip" ] && [ ! -z "${cluster_nginx_public_ip:-}" ] && [ ! -z "${cluster_nginx_internal_ip:-}" ]; then
  echo "[ AWS Fix: Public IP cannot be bound in AWS, overriding with private IP ] : "
  echo "[ Original Public IP: $cluster_nginx_public_ip ] : "
  echo "[ Using Private IP instead: $cluster_nginx_internal_ip ] : "
  
  # Override the public IP variable with private IP so install.sh uses the correct IP
  export cluster_nginx_public_ip="$cluster_nginx_internal_ip"
  echo "export cluster_nginx_public_ip=$cluster_nginx_internal_ip" | sudo tee -a /etc/environment
  
  echo "[ Public IP variable overridden with private IP ] : "
fi

# Observability fix: Escape forward slashes in cert paths for sed commands in install.sh
# The install.sh uses sed with these variables, and forward slashes need to be escaped
if [ "$NGINX_TYPE" == "observability" ] && [ ! -z "${observation_nginx_certs:-}" ]; then
  echo "[ Observability Fix: Escaping forward slashes in certificate paths for sed ] : "
  echo "[ Original cert path: $observation_nginx_certs ] : "
  echo "[ Original key path: $observation_nginx_cert_key ] : "
  
  # Escape forward slashes for sed commands
  export observation_nginx_certs=$(echo "$observation_nginx_certs" | sed 's/\//\\\//g')
  export observation_nginx_cert_key=$(echo "$observation_nginx_cert_key" | sed 's/\//\\\//g')
  
  # Update environment file
  sudo sed -i "/observation_nginx_certs/d" /etc/environment
  sudo sed -i "/observation_nginx_cert_key/d" /etc/environment
  echo "export observation_nginx_certs=$observation_nginx_certs" | sudo tee -a /etc/environment
  echo "export observation_nginx_cert_key=$observation_nginx_cert_key" | sudo tee -a /etc/environment
  
  echo "[ Escaped cert path: $observation_nginx_certs ] : "
  echo "[ Escaped key path: $observation_nginx_cert_key ] : "
fi

echo "[ Running NGINX install script from $nginx_location ] : "
sudo -E ./install.sh

# Check if nginx configuration is valid
echo "[ Testing NGINX configuration ] : "
if ! sudo nginx -t; then
  echo "[ ERROR: NGINX configuration test failed ] : "
  echo "[ Showing NGINX error log ] : "
  sudo tail -50 /var/log/nginx/error.log || echo "No error log found"
  exit 1
fi

echo "[ NGINX setup completed successfully ] : "
sudo systemctl status nginx --no-pager
