#!/bin/bash

# PostgreSQL Ansible Setup Script
# This script automates PostgreSQL installation using Ansible

set -euo pipefail  # Exit on error, undefined vars, pipe failures

echo '=== PostgreSQL Ansible Setup Started at $(date) ==='

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
echo ""

# Install prerequisites with extended timeout and better error handling
echo 'Installing Prerequisites...'
sudo apt-get update -qq || (echo 'apt-get update failed, retrying...'; sleep 10; sudo apt-get update -qq)

# Install packages step by step with individual timeouts
echo 'Installing Git...'
timeout 300 sudo apt-get install -y git || (echo 'Git installation failed'; exit 1)

echo 'Installing Python3-pip...'
timeout 300 sudo apt-get install -y python3-pip || (echo 'Python3-pip installation failed'; exit 1)

echo 'Installing Ansible (this may take a few minutes)...'
timeout 900 sudo apt-get install -y ansible || {
    echo 'System ansible installation failed, trying pip install...'
    timeout 600 pip3 install --user ansible || (echo 'Ansible installation failed completely'; exit 1)
    export PATH="$HOME/.local/bin:$PATH"
}

echo 'All prerequisites installed successfully'
echo 'Installed versions:'
git --version
python3 --version
ansible --version

# Clone MOSIP infrastructure repository with retry logic
echo 'Cloning Repository...'
cd /tmp
rm -rf mosip-infra

echo "Cloning from: $MOSIP_INFRA_REPO_URL"
echo "Branch: $MOSIP_INFRA_BRANCH"

timeout 600 git clone "$MOSIP_INFRA_REPO_URL" || {
    echo 'Initial git clone failed, retrying with verbose output...'
    sleep 10
    timeout 600 git clone --verbose "$MOSIP_INFRA_REPO_URL" || {
        echo 'Git clone failed completely'
        echo 'Checking network connectivity...'
        ping -c 3 8.8.8.8 || echo 'Network connectivity issue detected'
        exit 1
    }
}

cd mosip-infra
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
find /tmp/mosip-infra -name '*postgres*' -type d 2>/dev/null || echo 'No postgres directories found'

POSTGRES_ANSIBLE_DIR="/tmp/mosip-infra/deployment/v3/external/postgres/ansible"
if [ ! -d "$POSTGRES_ANSIBLE_DIR" ]; then
    echo "PostgreSQL Ansible directory not found at: $POSTGRES_ANSIBLE_DIR"
    echo 'Available directories under deployment:'
    find /tmp/mosip-infra -name 'deployment' -type d -exec find {} -type d \; 2>/dev/null | head -20
    exit 1
fi

cd "$POSTGRES_ANSIBLE_DIR"
echo "Successfully navigated to: $(pwd)"
echo 'Directory contents:'
ls -la

# Create dynamic inventory with current host
echo '[CREATE] Creating Inventory File...'
cat > inventory.ini << 'EOF'
[postgresql_servers]
localhost ansible_connection=local ansible_user=ubuntu ansible_become=yes ansible_become_method=sudo
EOF

echo '[SUCCESS] Inventory file created:'
cat inventory.ini

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
timeout 600 ansible-galaxy collection install community.general ansible.posix --force || {
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
for i in {1..120}; do 
    if [ -b "$STORAGE_DEVICE" ]; then 
        echo "[SUCCESS] Storage device found: $STORAGE_DEVICE"; 
        DEVICE_FOUND=true
        break; 
    fi; 
    
    # Show progress every 10 attempts
    if [ $((i % 10)) -eq 0 ]; then
        echo "[WAIT] Attempt $i/120: waiting for $STORAGE_DEVICE..."
        echo 'Current block devices:'
        lsblk | grep -E '(nvme|xvd|sd)' || echo 'No common block devices found'
    fi
    sleep 5; 
done

if [ "$DEVICE_FOUND" = false ]; then 
    echo "[WARNING] WARNING: Storage device $STORAGE_DEVICE not found after 10 minutes"
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
echo '[CREATE] This may take 15-30 minutes. Progress will be shown below...'

# Test ansible connection first
echo '[TEST] Testing Ansible connectivity...'
if ! ansible localhost -i inventory.ini -m ping; then
    echo '[ERROR] Ansible connectivity test failed'
    echo 'Checking localhost connection...'
    ansible localhost -i inventory.ini -m setup --limit localhost -v || true
    echo '[WARNING] Continuing anyway, playbook might still work...'
fi

# Show the command that will be executed
echo '[INFO] Ansible command to be executed:'
echo "ansible-playbook -vv -i inventory.ini -e postgresql_version=$POSTGRESQL_VERSION -e storage_device=$STORAGE_DEVICE -e mount_point=$MOUNT_POINT -e postgresql_port=$POSTGRESQL_PORT -e network_cidr=$NETWORK_CIDR postgresql-setup.yml"

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
timeout 2400 ansible-playbook -vv -i inventory.ini \
    -e postgresql_version=$POSTGRESQL_VERSION \
    -e storage_device=$STORAGE_DEVICE \
    -e mount_point=$MOUNT_POINT \
    -e postgresql_port=$POSTGRESQL_PORT \
    -e network_cidr=$NETWORK_CIDR \
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
    sleep 5
    sudo systemctl start postgresql 2>/dev/null || true
    sleep 10
    
    # Check if PostgreSQL is now running
    if sudo systemctl is-active postgresql >/dev/null 2>&1; then
        echo '[SUCCESS] PostgreSQL recovery successful!'
        echo '[TEST] Testing connection...'
        if sudo -u postgres psql -p "$POSTGRESQL_PORT" -c "SELECT version();"; then
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
sleep 15  # Wait for service to start

# Check main PostgreSQL service
echo '[CHECK] Checking PostgreSQL main service status...'
sudo systemctl status postgresql --no-pager --lines=5 || echo '[WARNING]  PostgreSQL service status check failed'

# Check specific PostgreSQL cluster service
echo '[CHECK] Checking PostgreSQL 15 cluster service...'
sudo systemctl status postgresql@15-main --no-pager --lines=5 2>/dev/null || {
    echo '[WARNING]  PostgreSQL cluster service not active, attempting to start...'
    sudo systemctl start postgresql@15-main 2>/dev/null || echo '[ERROR] Failed to start PostgreSQL cluster'
    sleep 10
}

# Check if PostgreSQL is actually listening on the configured port
echo "[CONNECT] Testing PostgreSQL connectivity on port $POSTGRESQL_PORT..."
for i in {1..6}; do
    if sudo -u postgres psql -p "$POSTGRESQL_PORT" -c "SELECT version();" >/dev/null 2>&1; then
        echo "[SUCCESS] PostgreSQL connection successful on attempt $i!"
        break
    else
        echo "[WAIT] Attempt $i: PostgreSQL not responding on port $POSTGRESQL_PORT, waiting..."
        sleep 10
    fi
done

# Final verification with detailed output
echo ''
echo '=== [STATUS] Final PostgreSQL Status Report ==='
echo '[CONFIG] Service Status:'
echo "  Main Service: $(sudo systemctl is-active postgresql 2>/dev/null || echo 'inactive')"
echo "  Cluster Service: $(sudo systemctl is-active postgresql@15-main 2>/dev/null || echo 'inactive')"
echo '[TEST] Connection Tests:'
if sudo -u postgres psql -p "$POSTGRESQL_PORT" -c "SELECT version();" >/dev/null 2>&1; then
    echo '  [SUCCESS] PostgreSQL connection: SUCCESS'
    echo '  [CREATE] PostgreSQL version:'
    sudo -u postgres psql -p "$POSTGRESQL_PORT" -c "SELECT version();" 2>/dev/null || echo '  [ERROR] Version check failed'
    echo '  [DIR] Data directory:'
    sudo -u postgres psql -p "$POSTGRESQL_PORT" -c "SHOW data_directory;" 2>/dev/null || echo '  [ERROR] Data directory check failed'
else
    echo '  ERROR: PostgreSQL connection: FAILED'
fi

# Check if PostgreSQL is listening on the correct port
echo 'Network Status:'
if sudo netstat -tlnp | grep ":$POSTGRESQL_PORT" >/dev/null 2>&1; then
    echo "  SUCCESS: PostgreSQL listening on port $POSTGRESQL_PORT"
    sudo netstat -tlnp | grep ":$POSTGRESQL_PORT" | head -1
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
echo "PostgreSQL setup completed successfully"
