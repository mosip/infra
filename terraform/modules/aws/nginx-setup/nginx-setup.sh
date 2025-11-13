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

## Install Nginx, ssl dependencies
echo "[ Install nginx & ssl dependencies packages ] : "
sudo apt-get update
sudo apt install -y software-properties-common
sudo add-apt-repository universe -y
sudo apt update
sudo apt-get install letsencrypt certbot python3-certbot-nginx python3-certbot-dns-route53 -y

if [ "$NGINX_TYPE" == "mosip" ]; then
  ## Get ssl certificate automatically for MOSIP
  echo "[ Generate SSL certificates from letsencrypt for MOSIP ] : "
  sudo certbot certonly --dns-route53 -d "*.${cluster_env_domain}" -d "${cluster_env_domain}" --non-interactive --agree-tos --email "$certbot_email"
else
  ## Get ssl certificate automatically for Observability
  echo "[ Generate SSL certificates from letsencrypt for Observability ] : "
  sudo certbot certonly --dns-route53 -d "*.${cluster_env_domain}" -d "${cluster_env_domain}" --non-interactive --agree-tos --email "$certbot_email"
fi

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

echo "[ Running NGINX install script from $nginx_location ] : "
sudo ./install.sh

# AWS-specific fix: In AWS, public IPs cannot be bound to network interfaces
# The install.sh may have configured NGINX to bind to public IP, we need to replace with private IP
if [ "$NGINX_TYPE" == "mosip" ] && [ ! -z "${cluster_nginx_public_ip:-}" ] && [ ! -z "${cluster_nginx_internal_ip:-}" ]; then
  echo "[ AWS Fix: Checking if public IP needs to be replaced with private IP in NGINX configs ] : "
  echo "[ Public IP (not bindable in AWS): $cluster_nginx_public_ip ] : "
  echo "[ Private IP (bindable): $cluster_nginx_internal_ip ] : "
  
  # Check if any config files contain the public IP
  if sudo grep -r "$cluster_nginx_public_ip" /etc/nginx/ >/dev/null 2>&1; then
    echo "[ Found public IP in NGINX configs, replacing with private IP ] : "
    
    # Replace in all nginx config files
    sudo find /etc/nginx/ -type f \( -name "*.conf" -o -name "nginx.conf" \) -exec sed -i "s/$cluster_nginx_public_ip/$cluster_nginx_internal_ip/g" {} \;
    
    echo "[ Successfully replaced public IP with private IP ] : "
  else
    echo "[ No public IP found in configs, no changes needed ] : "
  fi
fi

# Check if nginx configuration is valid
echo "[ Testing NGINX configuration ] : "
if ! sudo nginx -t; then
  echo "[ ERROR: NGINX configuration test failed ] : "
  echo "[ Showing NGINX error log ] : "
  sudo tail -50 /var/log/nginx/error.log || echo "No error log found"
  exit 1
fi

# The install.sh script should have already started NGINX, just verify it's running
echo "[ Verifying NGINX service status ] : "
sudo systemctl status nginx --no-pager || echo "NGINX not running, attempting to start..."

# If NGINX is not running, try to start it
if ! systemctl is-active --quiet nginx; then
  echo "[ Starting NGINX service ] : "
  sudo systemctl enable nginx
  sudo systemctl start nginx
fi

echo "[ NGINX setup completed successfully ] : "
sudo systemctl status nginx --no-pager
