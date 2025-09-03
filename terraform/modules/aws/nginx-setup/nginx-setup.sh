#!/bin/bash

# Log file path
echo "[ Set Log File ] : "
LOG_FILE="/tmp/nginx-setup-$( date +"%d-%h-%Y-%H-%M" ).log"
ENV_FILE_PATH="/etc/environment"
source $ENV_FILE_PATH
env | grep cluster

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
sudo apt install -y software-properties-common expect
sudo add-apt-repository universe -y
sudo apt update
sudo apt-get install letsencrypt certbot python3-certbot-nginx python3-certbot-dns-route53 -y

## Get ssl certificate automatically
echo "[ Generate SSL certificates from letsencrypt  ] : "
sudo certbot certonly --dns-route53 -d "*.${cluster_env_domain}" -d "${cluster_env_domain}" --non-interactive --agree-tos --email "$certbot_email"

## start and enable Nginx
#echo "[ Start & Enable nginx ] : "
#sudo systemctl enable nginx
#sudo systemctl start nginx

cd $working_dir
git clone $k8s_infra_repo_url -b $k8s_infra_branch || true # read it from variables
cd $nginx_location

# The k8s-infra install.sh script expects interactive input for internal IP
# We'll provide it automatically using the environment variable
echo "[ Starting nginx installation with automated internal IP configuration ] : "
echo "Internal IP: $cluster_nginx_internal_ip"
echo "Public IP: $cluster_nginx_public_ip"

# Check if install script exists and handle it appropriately
if [ -f "./install.sh" ]; then
    echo "Found install.sh script, checking if it requires interactive input..."
    
    # Check if the script contains interactive prompts
    if grep -q "interface ip\|Give the.*ip\|read.*ip" ./install.sh 2>/dev/null; then
        echo "Interactive script detected, using automated input..."
        echo "Internal IP: $cluster_nginx_internal_ip"
        
        # Use expect to handle interactive prompt, or use echo to pipe the answer
        if command -v expect >/dev/null 2>&1; then
            expect << EOD
spawn sudo ./install.sh
expect "Give the internal interface ip*"
send "$cluster_nginx_internal_ip\r"
expect eof
EOD
        else
            # Fallback: use echo to pipe the internal IP
            echo "$cluster_nginx_internal_ip" | sudo ./install.sh || {
                echo "Interactive install failed, trying non-interactive approach..."
                export NGINX_INTERNAL_IP="$cluster_nginx_internal_ip"
                sudo -E ./install.sh || echo "Warning: nginx install script may have failed"
            }
        fi
    else
        echo "Non-interactive script detected, running normally..."
        sudo ./install.sh
    fi
else
    echo "Warning: install.sh not found in $nginx_location"
    ls -la .
fi

