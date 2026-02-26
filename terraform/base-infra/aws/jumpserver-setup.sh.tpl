#!/bin/bash

# Jumpserver Setup Script with WireGuard Automation
# This script runs during EC2 instance initialization

set -euo pipefail

# Logging setup
LOG_FILE="/var/log/jumpserver-setup.log"
exec 1> >(tee -a "$LOG_FILE")
exec 2>&1

echo "=== Jumpserver Setup Started at $(date) ==="

# Environment variables from Terraform
K8S_INFRA_REPO_URL="${k8s_infra_repo_url}"
K8S_INFRA_BRANCH="${k8s_infra_branch}"
WIREGUARD_PEERS="${wireguard_peers}"
ENABLE_WIREGUARD="${enable_wireguard_setup}"
JUMPSERVER_NAME="${jumpserver_name}"

# Update system packages
echo "Updating system packages..."
apt-get update -y
apt-get install -y curl wget git unzip software-properties-common python3-pip

# Install Docker
echo "Installing Docker..."
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
usermod -aG docker ubuntu
systemctl enable docker
systemctl start docker

# Install Ansible
echo "Installing Ansible..."
apt-get install -y ansible

# Clone k8s-infra repository
echo "Cloning k8s-infra repository..."
cd /home/ubuntu
sudo -u ubuntu git clone "$K8S_INFRA_REPO_URL" k8s-infra
cd k8s-infra
sudo -u ubuntu git checkout "$K8S_INFRA_BRANCH"
chown -R ubuntu:ubuntu /home/ubuntu/k8s-infra

# Setup WireGuard if enabled
if [ "$ENABLE_WIREGUARD" = "true" ]; then
    echo "Setting up WireGuard..."
    
    # Create WireGuard config directory
    sudo -u ubuntu mkdir -p /home/ubuntu/wireguard/config
    
    # Wait for Docker to be fully ready
    sleep 10
    
    # Start WireGuard container
    echo "Starting WireGuard container..."
    docker run -d \
        --name=wireguard \
        --cap-add=NET_ADMIN \
        --cap-add=SYS_MODULE \
        -e PUID=1000 \
        -e PGID=1000 \
        -e TZ=Asia/Calcutta \
        -e PEERS="$WIREGUARD_PEERS" \
        -p 51820:51820/udp \
        -v /home/ubuntu/wireguard/config:/config \
        -v /lib/modules:/lib/modules \
        --sysctl="net.ipv4.conf.all.src_valid_mark=1" \
        --restart unless-stopped \
        ghcr.io/linuxserver/wireguard
    
    # Wait for WireGuard to initialize
    echo "Waiting for WireGuard to initialize..."
    sleep 30
    
    # Set proper permissions for config directory
    chown -R ubuntu:ubuntu /home/ubuntu/wireguard
    
    echo "WireGuard setup completed!"
else
    echo "WireGuard setup skipped (disabled in configuration)"
fi

# Create a status file to indicate setup completion
echo "Setup completed at $(date)" > /home/ubuntu/jumpserver-setup-complete.txt
chown ubuntu:ubuntu /home/ubuntu/jumpserver-setup-complete.txt

# Create useful aliases and scripts for the ubuntu user
cat > /home/ubuntu/.bash_aliases << 'EOF'
# WireGuard management aliases
alias wg-status='sudo docker logs wireguard'
alias wg-restart='sudo docker restart wireguard'
alias wg-config='sudo ls -la /home/ubuntu/wireguard/config'

# k8s-infra shortcuts
alias k8s-infra='cd /home/ubuntu/k8s-infra'
alias wg-dir='cd /home/ubuntu/k8s-infra/wireguard'
EOF

chown ubuntu:ubuntu /home/ubuntu/.bash_aliases

# Create a script to get WireGuard client configs
cat > /home/ubuntu/get-wireguard-configs.sh << 'EOF'
#!/bin/bash
echo "Available WireGuard client configurations:"
echo "=========================================="
ls -la /home/ubuntu/wireguard/config/
echo ""
echo "To view a specific client config (replace peerX with actual peer name):"
echo "cat /home/ubuntu/wireguard/config/peerX/peerX.conf"
echo ""
echo "QR codes are available at:"
echo "ls /home/ubuntu/wireguard/config/peerX/peerX.png"
EOF

chmod +x /home/ubuntu/get-wireguard-configs.sh
chown ubuntu:ubuntu /home/ubuntu/get-wireguard-configs.sh

echo "=== Jumpserver Setup Completed at $(date) ==="
echo "WireGuard status: $ENABLE_WIREGUARD"
echo "Log file: $LOG_FILE"
echo "Setup status: /home/ubuntu/jumpserver-setup-complete.txt"
