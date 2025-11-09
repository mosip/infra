#!/bin/bash

# Log file path
echo "[ Set Log File ] : "
LOG_FILE="/tmp/nginx-setup-$( date +"%d-%h-%Y-%H-%M" ).log"
ENV_FILE_PATH="/etc/environment"
. $ENV_FILE_PATH

# Determine which type of nginx setup based on available variables
if [ ! -z "$cluster_env_domain" ]; then
  NGINX_TYPE="mosip"
  echo "[ Detected NGINX Type: MOSIP ] : "
  env | grep cluster
elif [ ! -z "$observation_nginx_certs" ]; then
  NGINX_TYPE="observability"
  echo "[ Detected NGINX Type: Observability ] : "
  env | grep observation
else
  echo "[ ERROR: Could not determine NGINX type ] : "
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
sudo ./install.sh
