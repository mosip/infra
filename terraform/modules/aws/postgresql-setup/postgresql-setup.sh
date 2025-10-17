#!/bin/bash

# PostgreSQL Ansible Setup Script - Bulletproof & Idempotent
# This script uses the bulletproof approach for timezone and package installation

set -euo pipefail

echo "=== PostgreSQL Ansible Setup Started at $(date) ==="

# Set complete non-interactive environment (bulletproof approach)
export DEBIAN_FRONTEND=noninteractive
export APT_LISTCHANGES_FRONTEND=none
export UCF_FORCE_CONFFOLD=1
export DEBCONF_NONINTERACTIVE_SEEN=true
export NEEDRESTART_MODE=a
export NEEDRESTART_SUSPEND=1

# Configure debconf to never ask questions
echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections 2>/dev/null || true
echo 'debconf debconf/priority select critical' | debconf-set-selections 2>/dev/null || true

# BULLETPROOF timezone configuration - multiple preseeding methods
echo "tzdata tzdata/Areas select Etc" | debconf-set-selections 2>/dev/null || true
echo "tzdata tzdata/Zones/Etc select UTC" | debconf-set-selections 2>/dev/null || true

# Set timezone files directly
sudo mkdir -p /etc
echo 'Etc/UTC' | sudo tee /etc/timezone > /dev/null 2>&1 || true
sudo ln -sf /usr/share/zoneinfo/Etc/UTC /etc/localtime 2>/dev/null || true

# Simple function to check if package is already installed (idempotent)
is_installed() {
    dpkg -l "$1" 2>/dev/null | grep -q "^ii" || return 1
}

# Bulletproof package installation function
install_package_bulletproof() {
    local package="$1"
    
    if is_installed "$package"; then
        echo "✅ $package is already installed, skipping"
        return 0
    fi
    
    echo "Installing $package with bulletproof method..."
    
    if [ "$package" = "tzdata" ]; then
        # BULLETPROOF timezone handling - auto-answer prompts
        echo "Installing tzdata with automatic timezone answers..."
        echo -e "12\n1\n" | sudo apt-get install -y tzdata 2>/dev/null || {
            # Fallback method 1
            echo "Method 1 failed, trying method 2..."
            sudo DEBIAN_FRONTEND=noninteractive apt-get install -y tzdata -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" || {
                # Fallback method 2
                echo "Method 2 failed, trying method 3..."
                yes '' | sudo apt-get install -y tzdata || sudo apt-get install -y tzdata < /dev/null || true
            }
        }
        
        # Ensure timezone is set correctly after installation
        echo 'Etc/UTC' | sudo tee /etc/timezone > /dev/null
        sudo ln -sf /usr/share/zoneinfo/Etc/UTC /etc/localtime
        sudo dpkg-reconfigure -f noninteractive tzdata 2>/dev/null || true
        
        echo "✅ tzdata installed successfully"
        return 0
    else
        # Normal package installation with bulletproof options
        if sudo apt-get install -y "$package" -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"; then
            echo "✅ $package installed successfully"
            return 0
        else
            echo "❌ $package installation failed"
            return 1
        fi
    fi
}

# Configure APT for bulletproof operation
sudo mkdir -p /etc/apt/apt.conf.d/
sudo tee /etc/apt/apt.conf.d/99-bulletproof > /dev/null << 'EOF'
APT::Get::Assume-Yes "true";
APT::Install-Recommends "false";
APT::Install-Suggests "false";
Dpkg::Options {
    "--force-confdef";
    "--force-confold";
    "--force-confnew";
};
Dpkg::Use-Pty "0";
EOF

# Disable problematic hooks that can cause hanging
if [ -d /etc/ca-certificates/update.d/ ]; then
    sudo find /etc/ca-certificates/update.d/ -type f -exec chmod -x {} \; 2>/dev/null || true
fi

# Disable man-db updates
echo 'path-exclude /usr/share/man/*' | sudo tee /etc/dpkg/dpkg.cfg.d/01_nodoc > /dev/null 2>&1 || true

# Update package lists (bulletproof)
echo "Updating package lists..."
sudo apt-get update -qq || {
    echo "Initial update failed, trying again..."
    sleep 5
    sudo apt-get update -qq
}

# Install essential packages with bulletproof method
essential_packages=("sudo" "curl" "git" "apt-utils" "net-tools" "tzdata")

echo "Installing essential packages with bulletproof method..."
for package in "${essential_packages[@]}"; do
    install_package_bulletproof "$package" || {
        echo "WARNING: Failed to install $package, continuing..."
    }
done

# Validate required environment variables
echo 'Validating Environment Variables...'
REQUIRED_VARS=(
    "POSTGRESQL_VERSION"
    "STORAGE_DEVICE" 
    "MOUNT_POINT"
    "POSTGRESQL_PORT"
    "NETWORK_CIDR"
    "MOSIP_INFRA_REPO_URL"
    "MOSIP_INFRA_BRANCH"
)

OPTIONAL_VARS=(
    "NGINX_NODE_IP_OVERRIDE"
)

MISSING_VARS=()
for var in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!var:-}" ]; then
        MISSING_VARS+=("$var")
    fi
done

if [ ${#MISSING_VARS[@]} -ne 0 ]; then
    echo "ERROR: Missing required environment variables:"
    printf '  - %s\n' "${MISSING_VARS[@]}"
    echo ""
    echo "Please ensure these variables are set before running the script."
    exit 1
fi

echo 'All required environment variables are set:'
for var in "${REQUIRED_VARS[@]}"; do
    echo "  $var=${!var}"
done

# Display optional variables if set
echo ''
echo 'Optional environment variables:'
for var in "${OPTIONAL_VARS[@]}"; do
    if [ -n "${!var:-}" ]; then
        echo "  $var=${!var}"
    else
        echo "  $var=<not set>"
    fi
done

# Display control plane configuration variables
CONTROL_PLANE_VARS=(
    "CONTROL_PLANE_HOST"
    "CONTROL_PLANE_USER"
)

echo ''
echo 'Kubernetes control plane configuration:'
CONTROL_PLANE_SET=false
for var in "${CONTROL_PLANE_VARS[@]}"; do
    if [ -n "${!var:-}" ]; then
        echo "  $var=${!var}"
        CONTROL_PLANE_SET=true
    fi
done

if [ "$CONTROL_PLANE_SET" = false ]; then
    echo '  No control plane variables set - deployment will fail'
    echo '  Required variables for Terraform deployment:'
    echo '    - CONTROL_PLANE_HOST=<control-plane-ip>'
    echo '    - CONTROL_PLANE_USER=<control-plane-username> (default: ubuntu)'
    echo ''
    echo '  These should be set automatically by Terraform from your K8s cluster module'
fi

echo ""

# Install prerequisites with bulletproof method
echo 'Installing Prerequisites with Bulletproof Method...'

# Install python3 first (usually already installed)
if ! is_installed "python3"; then
    install_package_bulletproof "python3" || {
        echo "ERROR: Failed to install python3"
        exit 1
    }
fi

# Install python3-pip with bulletproof method
echo 'Installing Python3-pip...'
if ! install_package_bulletproof "python3-pip"; then
    echo "Package installation failed, trying pip bootstrap method..."
    # Alternative: Use the official pip installer
    if command -v curl >/dev/null; then
        curl -sS https://bootstrap.pypa.io/get-pip.py | python3 -W ignore || {
            echo "ERROR: Failed to install pip via bootstrap"
            exit 1
        }
    else
        echo "ERROR: Cannot install pip - curl not available"
        exit 1
    fi
fi

# Verify pip is working
if ! command -v pip3 >/dev/null && ! python3 -m pip --version >/dev/null 2>&1; then
    echo "ERROR: pip installation verification failed"
    exit 1
fi

# Install ansible with bulletproof method
echo 'Installing Ansible...'
if ! install_package_bulletproof "ansible"; then
    echo 'Package installation failed, installing via pip...'
    
    # Install ansible via pip (user install to avoid conflicts)
    if python3 -m pip install --user --quiet ansible; then
        echo 'Ansible installed via pip (user) successfully'
        # Add user bin to PATH
        export PATH="$HOME/.local/bin:$PATH"
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc || true
    else
        echo 'User pip install failed, trying system pip...'
        if python3 -m pip install --quiet ansible; then
            echo 'Ansible installed via pip (system) successfully'
        else
            echo 'ERROR: All ansible installation methods failed'
            exit 1
        fi
    fi
fi

echo 'All prerequisites installation completed with bulletproof method'
echo 'Checking installed versions:'
git --version || echo "Git: Not available"
python3 --version || echo "Python3: Not available"
ansible --version || echo "Ansible: Not available"

# Clone MOSIP infrastructure repository with retry logic
echo 'Cloning Repository...'
cd /tmp
rm -rf infra

echo "Cloning from: $MOSIP_INFRA_REPO_URL"
echo "Branch: $MOSIP_INFRA_BRANCH"

git clone "$MOSIP_INFRA_REPO_URL" || {
    echo 'Initial git clone failed, retrying with verbose output...'
    sleep 10
    git clone --verbose "$MOSIP_INFRA_REPO_URL" || {
        echo 'Git clone failed completely'
        echo 'Checking network connectivity...'
        ping -c 3 8.8.8.8 || echo 'Network connectivity issue detected'
        exit 1
    }
}

cd infra
git checkout "$MOSIP_INFRA_BRANCH" || {
    echo "Branch checkout failed for branch: $MOSIP_INFRA_BRANCH"
    echo 'Available branches:'
    git branch -a
    exit 1
}

echo "Successfully cloned and checked out branch: $MOSIP_INFRA_BRANCH"

# Navigate to PostgreSQL Ansible directory
echo 'Navigating to PostgreSQL Ansible Directory...'
echo 'Current directory structure:'
find /tmp/infra -name '*postgres*' -type d 2>/dev/null || echo 'No postgres directories found'

POSTGRES_ANSIBLE_DIR="/tmp/infra/utils/ansible"
if [ ! -d "$POSTGRES_ANSIBLE_DIR" ]; then
    echo "PostgreSQL Ansible directory not found at: $POSTGRES_ANSIBLE_DIR"
    echo 'Available directories under deployment:'
    find /tmp/infra -name 'utils' -type d -exec find {} -type d \; 2>/dev/null | head -20
    exit 1
fi

cd "$POSTGRES_ANSIBLE_DIR"
echo "Successfully navigated to: $(pwd)"
echo 'Directory contents:'
ls -la

# Check if required playbook exists
PLAYBOOK_FILE="postgresql-setup.yml"
if [ ! -f "$PLAYBOOK_FILE" ]; then
    echo "[ERROR] Playbook file not found: $PLAYBOOK_FILE"
    echo 'Available files in current directory:'
    ls -la *.yml *.yaml 2>/dev/null || echo 'No YAML files found'
    exit 1
fi
echo "[SUCCESS] Playbook file found: $PLAYBOOK_FILE"

# Set PostgreSQL configuration variables
echo '[CONFIG] Setting Environment Variables...'

# Get the actual IP address of this nginx node for external access
echo '[DETECT] Detecting nginx node IP address with preference for stable interfaces...'

# Check if IP is manually provided via environment variable
if [ -n "${NGINX_NODE_IP_OVERRIDE:-}" ]; then
    NGINX_NODE_IP="$NGINX_NODE_IP_OVERRIDE"
    echo "[OVERRIDE] Using manually provided nginx IP: $NGINX_NODE_IP"
else
    NGINX_NODE_IP=""
fi

# Method 1: Try AWS EC2 metadata first (most reliable for AWS deployments)
if [ -z "$NGINX_NODE_IP" ]; then
    echo "[DETECT] Trying AWS EC2 metadata service..."
    NGINX_NODE_IP=$(timeout 5 curl -s http://169.254.169.254/latest/meta-data/local-ipv4 2>/dev/null || echo "")
    if [ -n "$NGINX_NODE_IP" ]; then
        echo "[SUCCESS] Found IP via AWS metadata: $NGINX_NODE_IP"
    fi
fi

# Method 2: Try Azure metadata service
if [ -z "$NGINX_NODE_IP" ]; then
    echo "[DETECT] Trying Azure metadata service..."
    NGINX_NODE_IP=$(timeout 5 curl -s -H Metadata:true "http://169.254.169.254/metadata/instance/network/interface/0/ipv4/ipAddress/0/privateIpAddress?api-version=2017-08-01&format=text" 2>/dev/null || echo "")
    if [ -n "$NGINX_NODE_IP" ]; then
        echo "[SUCCESS] Found IP via Azure metadata: $NGINX_NODE_IP"
    fi
fi

# Method 3: Try GCP metadata service  
if [ -z "$NGINX_NODE_IP" ]; then
    echo "[DETECT] Trying GCP metadata service..."
    NGINX_NODE_IP=$(timeout 5 curl -s -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/ip" 2>/dev/null || echo "")
    if [ -n "$NGINX_NODE_IP" ]; then
        echo "[SUCCESS] Found IP via GCP metadata: $NGINX_NODE_IP"
    fi
fi

# Method 4: Prefer stable wired interfaces over wireless
if [ -z "$NGINX_NODE_IP" ]; then
    echo "[DETECT] Scanning for stable wired network interfaces..."
    
    # Define preferred interface patterns (most stable first)
    PREFERRED_INTERFACES=("eth" "ens" "enp" "eno" "em" "bond" "br")
    
    for pattern in "${PREFERRED_INTERFACES[@]}"; do
        # Find interfaces matching the pattern
        for interface in $(ip link show | grep -oP "${pattern}[0-9]+(?=:)"); do
            # Check if interface is up and has an IP
            if ip link show "$interface" | grep -q "state UP" 2>/dev/null; then
                CANDIDATE_IP=$(ip addr show "$interface" | grep -oP 'inet \K[\d.]+' | head -1 2>/dev/null)
                if [ -n "$CANDIDATE_IP" ] && [ "$CANDIDATE_IP" != "127.0.0.1" ]; then
                    NGINX_NODE_IP="$CANDIDATE_IP"
                    echo "[SUCCESS] Found IP via stable interface ($interface): $NGINX_NODE_IP"
                    break 2
                fi
            fi
        done
    done
fi

# Method 5: Use default route interface (but warn if it's wireless)
if [ -z "$NGINX_NODE_IP" ]; then
    echo "[DETECT] Trying default route interface..."
    DEFAULT_INTERFACE=$(ip route | grep '^default' | awk '{print $5}' | head -1 2>/dev/null)
    if [ -n "$DEFAULT_INTERFACE" ]; then
        # Check if it's a wireless interface and warn
        if echo "$DEFAULT_INTERFACE" | grep -qE '^(wl|wlp|wlan)'; then
            echo "[WARNING] Default interface ($DEFAULT_INTERFACE) appears to be wireless - IP may be dynamic!"
            echo "[WARNING] Consider using a wired interface for production deployments"
        fi
        
        NGINX_NODE_IP=$(ip addr show "$DEFAULT_INTERFACE" | grep -oP 'inet \K[\d.]+' | head -1 2>/dev/null)
        if [ -n "$NGINX_NODE_IP" ]; then
            echo "[SUCCESS] Found IP via default interface ($DEFAULT_INTERFACE): $NGINX_NODE_IP"
        fi
    fi
fi

# Method 6: Try hostname resolution (fallback)
if [ -z "$NGINX_NODE_IP" ]; then
    echo "[DETECT] Trying hostname resolution..."
    NGINX_NODE_IP=$(hostname -I | awk '{print $1}' 2>/dev/null)
    if [ -n "$NGINX_NODE_IP" ]; then
        echo "[SUCCESS] Found IP via hostname -I: $NGINX_NODE_IP"
    fi
fi

# Method 4: Try getting private IP from network interfaces (fallback)
if [ -z "$NGINX_NODE_IP" ]; then
    echo "[DETECT] Trying network interface detection..."
    NGINX_NODE_IP=$(ip addr show | grep -oP 'inet \K10\.\d+\.\d+\.\d+' | head -1 2>/dev/null)
    if [ -z "$NGINX_NODE_IP" ]; then
        NGINX_NODE_IP=$(ip addr show | grep -oP 'inet \K172\.(1[6-9]|2[0-9]|3[01])\.\d+\.\d+' | head -1 2>/dev/null)
    fi
    if [ -z "$NGINX_NODE_IP" ]; then
        NGINX_NODE_IP=$(ip addr show | grep -oP 'inet \K192\.168\.\d+\.\d+' | head -1 2>/dev/null)
    fi
    if [ -n "$NGINX_NODE_IP" ]; then
        echo "[SUCCESS] Found private IP via interface scan: $NGINX_NODE_IP"
    fi
fi

# Validate the IP address
if [ -n "$NGINX_NODE_IP" ]; then
    # Basic IP validation
    if echo "$NGINX_NODE_IP" | grep -qE '^([0-9]{1,3}\.){3}[0-9]{1,3}$'; then
        echo "[SUCCESS] Nginx node IP address detected: $NGINX_NODE_IP"
        echo "[INFO] This IP will be used as postgres-host in the ConfigMap and Ansible target"
    else
        echo "[ERROR] Invalid IP address detected: $NGINX_NODE_IP"
        exit 1
    fi
else
    echo "[ERROR] Could not detect nginx node IP address"
    echo "[INFO] Available network interfaces:"
    ip addr show | grep -E '^[0-9]+:' | awk '{print $2}' | tr -d ':'
    echo "[INFO] Please manually set the IP address or check network configuration"
    exit 1
fi

# Create dynamic inventory with detected nginx node IP using local connection
echo '[CREATE] Creating Inventory File with nginx node IP (local connection)...'
cat > inventory.ini << EOF
[postgresql_servers]
$NGINX_NODE_IP ansible_connection=local ansible_user=ubuntu ansible_become=yes ansible_become_method=sudo
EOF

echo "[SUCCESS] Inventory file created with nginx IP target (local): $NGINX_NODE_IP"

export DEBIAN_FRONTEND=noninteractive  # Prevent interactive prompts
export ANSIBLE_HOST_KEY_CHECKING=False  # Skip host key checking
export ANSIBLE_STDOUT_CALLBACK=debug   # Verbose output
export ANSIBLE_TIMEOUT=30              # Set ansible timeout
export ANSIBLE_CONNECT_TIMEOUT=30      # Set connection timeout
export ANSIBLE_COLLECTIONS_PATH=/tmp/ansible_collections  # Custom collections path
export ANSIBLE_GALAXY_DISABLE_GPG_VERIFY=true  # Disable GPG verification
export ANSIBLE_PIPELINING=true         # Enable pipelining for speed
export ANSIBLE_SSH_RETRIES=3           # Set SSH retries

# Create ansible configuration to prevent hanging
echo '[CONFIG] Creating Ansible Configuration...'
mkdir -p ~/.ansible
cat > ~/.ansible/ansible.cfg << 'EOF'
[defaults]
host_key_checking = False
gathering = explicit
fact_caching = memory
fact_caching_timeout = 86400
stdout_callback = debug
stderr_callback = debug
timeout = 30
command_timeout = 30
connect_timeout = 30
gathering_timeout = 30

[ssh_connection]
pipelining = True
ssh_args = -o ControlMaster=auto -o ControlPersist=60s -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no
retries = 3
EOF

echo '[SUCCESS] Environment variables and Ansible configuration set:'
echo "PostgreSQL Version: $POSTGRESQL_VERSION"
echo "Storage Device: $STORAGE_DEVICE"
echo "Mount Point: $MOUNT_POINT"
echo "PostgreSQL Port: $POSTGRESQL_PORT"
echo "Network CIDR: $NETWORK_CIDR"

# Configure APT to prevent hanging
echo '[CONFIG] Configuring APT for non-interactive mode...'
sudo mkdir -p /etc/apt/apt.conf.d/
echo 'APT::Get::Assume-Yes "true";' | sudo tee /etc/apt/apt.conf.d/99automated
echo 'APT::Get::force-yes "true";' | sudo tee -a /etc/apt/apt.conf.d/99automated
echo 'Dpkg::Options { "--force-confdef"; "--force-confold"; }' | sudo tee -a /etc/apt/apt.conf.d/99automated
echo '[SUCCESS] APT configured for non-interactive mode'

# Install required Ansible collections to prevent hanging during playbook execution
echo '[INSTALL] Installing Required Ansible Collections...'
mkdir -p /tmp/ansible_collections
ansible-galaxy collection install community.general ansible.posix --force || {
    echo '[WARNING] Failed to install some collections, continuing with basic setup...'
}
echo '[SUCCESS] Ansible collections installation completed'

# Check if storage device exists and wait if needed
echo '[CHECK] Checking Storage Device...'
echo "Looking for storage device: $STORAGE_DEVICE"

# First, show all available block devices
echo '[INFO] All available block devices:'
lsblk -f 2>/dev/null || lsblk 2>/dev/null || echo 'Unable to list block devices'

# Wait for the specific storage device
echo "[WAIT] Waiting for storage device $STORAGE_DEVICE..."
DEVICE_FOUND=false
for i in {1..24}; do 
    if [ -b "$STORAGE_DEVICE" ]; then 
        echo "[SUCCESS] Storage device found: $STORAGE_DEVICE"; 
        DEVICE_FOUND=true
        break; 
    fi; 
    
    # Show progress every 6 attempts
    if [ $((i % 6)) -eq 0 ]; then
        echo "[WAIT] Attempt $i/24: waiting for $STORAGE_DEVICE..."
        echo 'Current block devices:'
        lsblk | grep -E '(nvme|xvd|sd)' || echo 'No common block devices found'
    fi
    sleep 5; 
done

if [ "$DEVICE_FOUND" = false ]; then 
    echo "[WARNING] WARNING: Storage device $STORAGE_DEVICE not found after 2 minutes"
    echo 'This might be okay if PostgreSQL will use existing storage.'
    echo '[INFO] Available block devices:'
    lsblk 2>/dev/null || echo 'Unable to list block devices'
    
    # Don't exit here, let the playbook handle storage configuration
    echo 'Continuing with PostgreSQL setup...'
else
    echo "[SUCCESS] Storage device $STORAGE_DEVICE is available"
    echo 'Device information:'
    lsblk "$STORAGE_DEVICE" 2>/dev/null || echo "Unable to get device info for $STORAGE_DEVICE"
fi

# Run PostgreSQL setup with extended timeout and better error handling
echo '[RUN] Running PostgreSQL Ansible Playbook...'
echo "[TIME] Starting ansible-playbook at $(date)"
echo '[CREATE] This should take 10-15 minutes. Progress will be shown below...'

# Test ansible connection first
echo '[TEST] Testing Ansible connectivity...'
if ! ansible $NGINX_NODE_IP -i inventory.ini -m ping; then
    echo '[ERROR] Ansible connectivity test failed'
    echo 'Checking nginx node connection...'
    ansible $NGINX_NODE_IP -i inventory.ini -m setup --limit $NGINX_NODE_IP -v || true
    echo '[WARNING] Continuing anyway, playbook might still work...'
fi

# Show the command that will be executed
echo '[INFO] Ansible command to be executed:'
echo "ansible-playbook -vv -i inventory.ini -e postgresql_version=$POSTGRESQL_VERSION -e storage_device=$STORAGE_DEVICE -e mount_point=$MOUNT_POINT -e postgresql_port=$POSTGRESQL_PORT -e network_cidr=$NETWORK_CIDR -e postgres_external_host=$NGINX_NODE_IP postgresql-setup.yml"

# Start a background progress monitor
(
    while true; do
        sleep 60
        echo "[WAIT] PostgreSQL setup still running... $(date) - Check /tmp/postgresql-ansible.log for details"
        if [ -f /tmp/postgresql-ansible.log ]; then
            LAST_LINE=$(tail -1 /tmp/postgresql-ansible.log 2>/dev/null || echo "Log file being written...")
            echo "[LOG] Last log: $LAST_LINE"
        fi
    done
) &
PROGRESS_PID=$!

# Run the actual playbook
timeout 900 ansible-playbook -vv -i inventory.ini \
    -e postgresql_version=$POSTGRESQL_VERSION \
    -e storage_device=$STORAGE_DEVICE \
    -e mount_point=$MOUNT_POINT \
    -e postgresql_port=$POSTGRESQL_PORT \
    -e network_cidr=$NETWORK_CIDR \
    -e postgres_external_host=$NGINX_NODE_IP \
    postgresql-setup.yml 2>&1 | tee /tmp/postgresql-ansible.log
ANSIBLE_EXIT_CODE=$?

# Stop the progress monitor
kill $PROGRESS_PID 2>/dev/null || true

if [ $ANSIBLE_EXIT_CODE -ne 0 ]; then
    echo ''
    echo "[ERROR] Ansible playbook failed with exit code $ANSIBLE_EXIT_CODE"
    echo '[CONFIG] Attempting PostgreSQL Recovery...'
    
    # Fix common permission issues
    echo '[CONFIG] Fixing data directory permissions...'
    sudo chown -R postgres:postgres $MOUNT_POINT/postgresql/15/main 2>/dev/null || true
    sudo chmod 700 $MOUNT_POINT/postgresql/15/main 2>/dev/null || true
    
    # Try to restart PostgreSQL service
    echo '[PROGRESS] Attempting to restart PostgreSQL service...'
    sudo systemctl stop postgresql 2>/dev/null || true
    sleep 3
    sudo systemctl start postgresql 2>/dev/null || true
    sleep 5
    
    # Check if PostgreSQL is now running
    if sudo systemctl is-active postgresql >/dev/null 2>&1; then
        echo '[SUCCESS] PostgreSQL recovery successful!'
        echo '[TEST] Testing connection...'
        if sudo -u postgres psql -p "$POSTGRESQL_PORT" -c "SELECT version();" --no-psqlrc --pset pager=off; then
            echo '[SUCCESS] PostgreSQL is working!'
        else
            echo '[ERROR] Connection still failing'
        fi
    else
        echo '[ERROR] PostgreSQL recovery failed'
        echo '=== Diagnostic Information ==='
        echo '[STATUS] Service status:'
        sudo systemctl status postgresql --no-pager --lines=10 || true
        echo '[INFO] Recent logs:'
        sudo journalctl -u postgresql --no-pager --lines=20 || true
        echo '[LOG] Last 50 lines of setup log:'
        tail -50 /tmp/postgresql-ansible.log || true
        echo '[STORAGE] System status:'
        df -h
        free -h
        exit 1
    fi
else
    echo ''
    echo "[SUCCESS] Ansible playbook completed successfully at $(date)"
fi

# Verify PostgreSQL installation with improved checks
echo ''
echo '=== [CHECK] Verifying PostgreSQL Installation ==='
sleep 5  # Quick wait for service to start

# Check main PostgreSQL service
echo '[CHECK] Checking PostgreSQL main service status...'
sudo systemctl status postgresql --no-pager --lines=5 || echo '[WARNING]  PostgreSQL service status check failed'

# Check specific PostgreSQL cluster service
echo '[CHECK] Checking PostgreSQL 15 cluster service...'
sudo systemctl status postgresql@15-main --no-pager --lines=5 2>/dev/null || {
    echo '[WARNING]  PostgreSQL cluster service not active, attempting to start...'
    sudo systemctl start postgresql@15-main 2>/dev/null || echo '[ERROR] Failed to start PostgreSQL cluster'
    sleep 5
}

# Check if PostgreSQL is actually listening on the configured port
echo "[CONNECT] Testing PostgreSQL connectivity on port $POSTGRESQL_PORT..."
for i in {1..3}; do
    if timeout 15 sudo -u postgres psql -p "$POSTGRESQL_PORT" -c "SELECT version();" --no-psqlrc --pset pager=off >/dev/null 2>&1; then
        echo "[SUCCESS] PostgreSQL connection successful on attempt $i!"
        break
    else
        echo "[WAIT] Attempt $i/3: PostgreSQL not responding on port $POSTGRESQL_PORT, waiting..."
        sleep 5
    fi
done

# Final verification with detailed output
echo ''
echo '=== [STATUS] Final PostgreSQL Status Report ==='
echo '[CONFIG] Service Status:'
echo "  Main Service: $(sudo systemctl is-active postgresql 2>/dev/null || echo 'inactive')"
echo "  Cluster Service: $(sudo systemctl is-active postgresql@15-main 2>/dev/null || echo 'inactive')"
echo '[TEST] Connection Tests:'
if timeout 15 sudo -u postgres psql -p "$POSTGRESQL_PORT" -c "SELECT version();" --no-psqlrc --pset pager=off >/dev/null 2>&1; then
    echo '  [SUCCESS] PostgreSQL connection: SUCCESS'
    echo '  [CREATE] PostgreSQL version:'
    timeout 10 sudo -u postgres psql -p "$POSTGRESQL_PORT" -c "SELECT version();" --no-psqlrc --pset pager=off 2>/dev/null || echo '  [ERROR] Version check failed'
    echo '  [DIR] Data directory:'
    timeout 10 sudo -u postgres psql -p "$POSTGRESQL_PORT" -c "SHOW data_directory;" --no-psqlrc --pset pager=off 2>/dev/null || echo '  [ERROR] Data directory check failed'
else
    echo '  ERROR: PostgreSQL connection: FAILED'
fi

# Check if PostgreSQL is listening on the correct port
echo 'Network Status:'
if timeout 10 sudo netstat -tlnp | grep ":$POSTGRESQL_PORT" >/dev/null 2>&1; then
    echo "  SUCCESS: PostgreSQL listening on port $POSTGRESQL_PORT"
    timeout 5 sudo netstat -tlnp | grep ":$POSTGRESQL_PORT" | head -1 || echo "  (Port details unavailable)"
else
    echo "  ERROR: PostgreSQL not listening on port $POSTGRESQL_PORT"
fi

echo ''
echo '=== PostgreSQL Ansible Setup Completed Successfully ==='
echo "Completion Time: $(date)"
echo "Setup Log: /tmp/postgresql-ansible.log"
echo ''
echo '=== Final System Status ==='
echo 'PostgreSQL Service:'
SERVICE_STATUS=$(sudo systemctl is-active postgresql 2>/dev/null || echo 'inactive')
echo "  Status: $SERVICE_STATUS"
if [ "$SERVICE_STATUS" = "active" ]; then
    echo '  SUCCESS: PostgreSQL is running successfully'
else
    echo '  WARNING: PostgreSQL service may need attention'
fi
echo 'Storage Usage:'
if df -h "$MOUNT_POINT" >/dev/null 2>&1; then
    echo "  Mount Point: $MOUNT_POINT"
    df -h "$MOUNT_POINT" | tail -1
else
    echo '  WARNING: Mount point not available'
fi
echo "Installation Summary:"
echo "PostgreSQL Version: $POSTGRESQL_VERSION"
echo "Storage Device: $STORAGE_DEVICE"
echo "Mount Point: $MOUNT_POINT"
echo "PostgreSQL Port: $POSTGRESQL_PORT"
echo "Network CIDR: $NETWORK_CIDR"

# Check if Kubernetes deployment should be skipped (handled by Terraform)
if [ "${SKIP_K8S_DEPLOYMENT:-false}" = "true" ]; then
    echo ""
    echo "=== [SKIP] Kubernetes Deployment Skipped ==="
    echo "[INFO] SKIP_K8S_DEPLOYMENT flag is set - Terraform will handle Kubernetes deployment"
    echo "[INFO] PostgreSQL installation and YAML generation completed successfully"
    echo "[INFO] Generated files are available in /tmp/postgresql-secrets/"
    echo "  - postgres-postgresql.yml"
    echo "  - postgres-setup-config.yml"
    echo ""
    echo "[SUCCESS] PostgreSQL setup completed (without Kubernetes deployment)"
    exit 0
fi

# Copy kubeconfig to nginx node
echo '[CONFIG] Setting up Kubernetes resource deployment...'

# Validate control plane configuration
if [ -z "${CONTROL_PLANE_HOST:-}" ] || [ -z "${CONTROL_PLANE_USER:-}" ]; then
    echo '[ERROR] Control plane configuration missing!'
    echo '[ERROR] CONTROL_PLANE_HOST and CONTROL_PLANE_USER must be set'
    echo '[INFO] Required variables:'
    echo "  CONTROL_PLANE_HOST: Kubernetes control plane IP address"
    echo "  CONTROL_PLANE_USER: SSH username for control plane access"
    exit 1
fi

echo "[INFO] Using control plane deployment method"
echo "[INFO] Control plane: ${CONTROL_PLANE_USER}@${CONTROL_PLANE_HOST}"
echo "[INFO] YAML files will be copied to control plane for kubectl apply"

echo ''
echo '=== [K8S] Kubernetes Setup Phase ==='
echo 'Setting up Kubernetes resources for PostgreSQL...'

# Check if Kubernetes YAML files were generated
echo '[CHECK] Checking for generated Kubernetes YAML files...'
POSTGRES_SECRET_FILE="/tmp/postgresql-secrets/postgres-postgresql.yml"
POSTGRES_CONFIG_FILE="/tmp/postgresql-secrets/postgres-setup-config.yml"

if [ -f "$POSTGRES_SECRET_FILE" ] && [ -f "$POSTGRES_CONFIG_FILE" ]; then
    echo '[SUCCESS] Kubernetes YAML files found:'
    echo "  Secret: $POSTGRES_SECRET_FILE"
    echo "  ConfigMap: $POSTGRES_CONFIG_FILE"
    
    echo ''
    echo '[K8S] Deploying via Control Plane...'
    
    # Create a deployment script for the control plane
    DEPLOY_SCRIPT="/tmp/deploy-postgres-k8s.sh"
    cat > "$DEPLOY_SCRIPT" << 'EOF'
#!/bin/bash
set -e

echo "=== PostgreSQL Kubernetes Deployment ==="
echo "Timestamp: $(date)"

# Create postgres namespace if it doesn't exist
echo "[CREATE] Creating postgres namespace..."
if kubectl get namespace postgres >/dev/null 2>&1; then
    echo "[SUCCESS] postgres namespace already exists"
else
    if kubectl create namespace postgres; then
        echo "[SUCCESS] postgres namespace created successfully"
    else
        echo "[ERROR] Failed to create postgres namespace"
        exit 1
    fi
fi

# Apply the Secret
echo "[APPLY] Applying PostgreSQL secret..."
if kubectl apply -f /tmp/postgresql-secrets/postgres-postgresql.yml; then
    echo "[SUCCESS] PostgreSQL secret applied successfully"
else
    echo "[ERROR] Failed to apply PostgreSQL secret"
    exit 1
fi

# Apply the ConfigMap
echo "[APPLY] Applying PostgreSQL ConfigMap..."
if kubectl apply -f /tmp/postgresql-secrets/postgres-setup-config.yml; then
    echo "[SUCCESS] PostgreSQL ConfigMap applied successfully"
else
    echo "[ERROR] Failed to apply PostgreSQL ConfigMap"
    exit 1
fi

# Verify the resources were created
echo ""
echo "[VERIFY] Verifying Kubernetes resources..."
echo "[CHECK] postgres namespace:"
kubectl get namespace postgres >/dev/null 2>&1 && echo "[SUCCESS] postgres namespace exists" || echo "[ERROR] postgres namespace not found"

echo "[CHECK] PostgreSQL secret:"
kubectl get secret -n postgres postgres-postgresql >/dev/null 2>&1 && echo "[SUCCESS] PostgreSQL secret exists" || echo "[ERROR] PostgreSQL secret not found"

echo "[CHECK] PostgreSQL ConfigMap:"
kubectl get configmap -n postgres postgres-setup-config >/dev/null 2>&1 && echo "[SUCCESS] PostgreSQL ConfigMap exists" || echo "[ERROR] PostgreSQL ConfigMap not found"

echo ""
echo "[SUCCESS] PostgreSQL Kubernetes deployment completed!"

# Clean up the YAML files for security
echo "[CLEANUP] Removing sensitive YAML files..."
rm -f /tmp/postgresql-secrets/*.yml
rmdir /tmp/postgresql-secrets 2>/dev/null || true
echo "[SUCCESS] Cleanup completed"
EOF
    
    chmod +x "$DEPLOY_SCRIPT"
    
    # Copy files to control plane
    echo "[COPY] Copying YAML files and deployment script to control plane..."
    
    # Create temporary SSH key file for nginx->control plane communication
    SSH_KEY_FILE="/tmp/nginx-to-control-plane-key"
    echo "$SSH_PRIVATE_KEY" > "$SSH_KEY_FILE"
    chmod 600 "$SSH_KEY_FILE"
    
    # Use SSH with proper error handling and private key
    if timeout 60 scp -i "$SSH_KEY_FILE" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 \
       -r /tmp/postgresql-secrets "$DEPLOY_SCRIPT" "${CONTROL_PLANE_USER}@${CONTROL_PLANE_HOST}:/tmp/" 2>/dev/null; then
        echo "[SUCCESS] Files copied to control plane"
        
        # Execute the deployment script on control plane
        echo "[EXECUTE] Running deployment script on control plane..."
        if timeout 120 ssh -i "$SSH_KEY_FILE" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 \
           "${CONTROL_PLANE_USER}@${CONTROL_PLANE_HOST}" "bash /tmp/deploy-postgres-k8s.sh" 2>/dev/null; then
            echo "[SUCCESS] Kubernetes resources deployed successfully via control plane!"
        else
            echo "[ERROR] Failed to execute deployment script on control plane"
            echo "[INFO] Manual deployment fallback:"
            echo "  1. SSH to control plane: ssh ${CONTROL_PLANE_USER}@${CONTROL_PLANE_HOST}"
            echo "  2. Run: bash /tmp/deploy-postgres-k8s.sh"
            # Clean up SSH key file before exiting
            rm -f "$SSH_KEY_FILE"
            exit 1
        fi
        
        # Cleanup the deployment script on control plane
        timeout 30 ssh -i "$SSH_KEY_FILE" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
           "${CONTROL_PLANE_USER}@${CONTROL_PLANE_HOST}" "rm -f /tmp/deploy-postgres-k8s.sh" 2>/dev/null || true
        
        # Clean up SSH key file
        rm -f "$SSH_KEY_FILE"
            
    else
        echo "[ERROR] Failed to copy files to control plane"
        echo "[ERROR] Please verify:"
        echo "  1. Control plane host is reachable: ${CONTROL_PLANE_HOST}"
        echo "  2. SSH access is configured for user: ${CONTROL_PLANE_USER}"
        echo "  3. Network connectivity between nginx node and control plane"
        # Clean up SSH key file before exiting
        rm -f "$SSH_KEY_FILE"
        exit 1
    fi
    
    # Clean up local deployment script
    rm -f "$DEPLOY_SCRIPT"
    
else
    echo '[ERROR] Kubernetes YAML files not found'
    echo '[ERROR] Expected files:'
    echo "  $POSTGRES_SECRET_FILE"
    echo "  $POSTGRES_CONFIG_FILE"
    echo '[ERROR] The Ansible playbook may have failed to generate these files'
    exit 1
fi

echo ''
echo '=== [CLEANUP] Cleaning up temporary files ==='
# Clean up sensitive information 
echo '[CLEAN] Cleaning up temporary files...'
rm -rf /tmp/infra 2>/dev/null || true
rm -f /tmp/postgresql-ansible.log 2>/dev/null || true

# Keep the generated YAML files for reference (they will be cleaned up by control plane script)
echo '[INFO] Generated Kubernetes files location:'
echo '  /tmp/postgresql-secrets/ (cleaned up automatically on control plane after deployment)'
echo ''

echo "PostgreSQL setup completed successfully"
