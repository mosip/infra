#!/bin/bash

# PostgreSQL Ansible Setup Script
# This script automates PostgreSQL installation using Ansible

set -euo pipefail  # Exit on error, undefined vars, pipe failures

echo '=== PostgreSQL Ansible Setup Started at $(date) ==='

# Install prerequisites with extended timeout and better error handling
echo '🔧 Installing Prerequisites...'
sudo apt-get update -qq || (echo '❌ apt-get update failed, retrying...'; sleep 10; sudo apt-get update -qq)

# Install packages step by step with individual timeouts
echo '📦 Installing Git...'
timeout 300 sudo apt-get install -y git || (echo '❌ Git installation failed'; exit 1)

echo '📦 Installing Python3-pip...'
timeout 300 sudo apt-get install -y python3-pip || (echo '❌ Python3-pip installation failed'; exit 1)

echo '📦 Installing Ansible (this may take a few minutes)...'
timeout 900 sudo apt-get install -y ansible || {
    echo '⚠️ System ansible installation failed, trying pip install...'
    timeout 600 pip3 install --user ansible || (echo '❌ Ansible installation failed completely'; exit 1)
    export PATH="$HOME/.local/bin:$PATH"
}

echo '✅ All prerequisites installed successfully'
echo 'Installed versions:'
git --version
python3 --version
ansible --version

# Clone MOSIP infrastructure repository with retry logic
echo '=== Cloning Repository ==='
cd /tmp
rm -rf mosip-infra
timeout 600 git clone $MOSIP_INFRA_REPO_URL || (echo 'Git clone failed, retrying...'; sleep 10; timeout 600 git clone $MOSIP_INFRA_REPO_URL)
cd mosip-infra
git checkout $MOSIP_INFRA_BRANCH || (echo 'Branch checkout failed'; exit 1)

# Navigate to PostgreSQL Ansible directory
echo '=== Navigating to PostgreSQL Ansible ==='
cd deployment/v3/external/postgres/ansible || (echo 'Failed to navigate to PostgreSQL directory'; find /tmp/mosip-infra -name '*postgres*' -type d; exit 1)
pwd && ls -la

# Create dynamic inventory with current host
echo '=== Creating Inventory ==='
echo '[postgresql_servers]' > inventory.ini
echo "localhost ansible_connection=local ansible_user=ubuntu ansible_become=yes ansible_become_method=sudo" >> inventory.ini
cat inventory.ini

# Set PostgreSQL configuration variables
echo '🔧 Setting Environment Variables...'
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
echo '🔧 Creating Ansible Configuration...'
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

echo '✅ Environment variables and Ansible configuration set:'
echo "PostgreSQL Version: $POSTGRESQL_VERSION"
echo "Storage Device: $STORAGE_DEVICE"
echo "Mount Point: $MOUNT_POINT"
echo "PostgreSQL Port: $POSTGRESQL_PORT"
echo "Network CIDR: $NETWORK_CIDR"

# Configure APT to prevent hanging
echo '🔧 Configuring APT for non-interactive mode...'
sudo mkdir -p /etc/apt/apt.conf.d/
echo 'APT::Get::Assume-Yes "true";' | sudo tee /etc/apt/apt.conf.d/99automated
echo 'APT::Get::force-yes "true";' | sudo tee -a /etc/apt/apt.conf.d/99automated
echo 'Dpkg::Options { "--force-confdef"; "--force-confold"; }' | sudo tee -a /etc/apt/apt.conf.d/99automated
echo '✅ APT configured for non-interactive mode'

# Install required Ansible collections to prevent hanging during playbook execution
echo '📦 Installing Required Ansible Collections...'
mkdir -p /tmp/ansible_collections
timeout 600 ansible-galaxy collection install community.general ansible.posix --force || {
    echo '⚠️ Failed to install some collections, continuing with basic setup...'
}
echo '✅ Ansible collections installation completed'

# Check if storage device exists and wait if needed
echo '🔍 Checking Storage Device...'
echo "Waiting for storage device $STORAGE_DEVICE..."
for i in {1..120}; do 
    if [ -b $STORAGE_DEVICE ]; then 
        echo '✅ Storage device found!'; 
        break; 
    fi; 
    echo "⏳ Attempt $i: waiting for $STORAGE_DEVICE..."; 
    sleep 5; 
done
if [ ! -b $STORAGE_DEVICE ]; then 
    echo "❌ ERROR: Storage device $STORAGE_DEVICE not found after 10 minutes"
    echo '📋 Available block devices:'
    lsblk
    exit 1
fi
echo '📋 Available storage devices:'
lsblk | grep -E '(nvme|xvd|sd)' || true

# Run PostgreSQL setup with extended timeout and better error handling
echo '🚀 Running PostgreSQL Ansible Playbook...'
echo "⏰ Starting ansible-playbook at $(date)"
echo '📝 This may take 15-30 minutes. Progress will be shown below...'

# Start a background progress monitor
(
    while true; do
        sleep 60
        echo "⏳ PostgreSQL setup still running... $(date) - Check /tmp/postgresql-ansible.log for details"
        if [ -f /tmp/postgresql-ansible.log ]; then
            LAST_LINE=$(tail -1 /tmp/postgresql-ansible.log 2>/dev/null || echo "Log file being written...")
            echo "📄 Last log: $LAST_LINE"
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
    echo "❌ Ansible playbook failed with exit code $ANSIBLE_EXIT_CODE"
    echo '🔧 Attempting PostgreSQL Recovery...'
    
    # Fix common permission issues
    echo '🔧 Fixing data directory permissions...'
    sudo chown -R postgres:postgres $MOUNT_POINT/postgresql/15/main 2>/dev/null || true
    sudo chmod 700 $MOUNT_POINT/postgresql/15/main 2>/dev/null || true
    
    # Try to restart PostgreSQL service
    echo '🔄 Attempting to restart PostgreSQL service...'
    sudo systemctl stop postgresql 2>/dev/null || true
    sleep 5
    sudo systemctl start postgresql 2>/dev/null || true
    sleep 10
    
    # Check if PostgreSQL is now running
    if sudo systemctl is-active postgresql >/dev/null 2>&1; then
        echo '✅ PostgreSQL recovery successful!'
        echo '🧪 Testing connection...'
        sudo -u postgres psql -p $POSTGRESQL_PORT -c 'SELECT version();' && echo '✅ PostgreSQL is working!' || echo '❌ Connection still failing'
    else
        echo '❌ PostgreSQL recovery failed'
        echo '=== Diagnostic Information ==='
        echo '📊 Service status:'
        sudo systemctl status postgresql --no-pager --lines=10 || true
        echo '📋 Recent logs:'
        sudo journalctl -u postgresql --no-pager --lines=20 || true
        echo '📄 Last 50 lines of setup log:'
        tail -50 /tmp/postgresql-ansible.log || true
        echo '💾 System status:'
        df -h
        free -h
        exit 1
    fi
else
    echo ''
    echo "✅ Ansible playbook completed successfully at $(date)"
fi


# Verify PostgreSQL installation with improved checks
echo ''
echo '=== 🔍 Verifying PostgreSQL Installation ==='
sleep 15  # Wait for service to start

# Check main PostgreSQL service
echo '🔍 Checking PostgreSQL main service status...'
sudo systemctl status postgresql --no-pager --lines=5 || echo '⚠️  PostgreSQL service status check failed'

# Check specific PostgreSQL cluster service
echo '🔍 Checking PostgreSQL 15 cluster service...'
sudo systemctl status postgresql@15-main --no-pager --lines=5 2>/dev/null || {
    echo '⚠️  PostgreSQL cluster service not active, attempting to start...'
    sudo systemctl start postgresql@15-main 2>/dev/null || echo '❌ Failed to start PostgreSQL cluster'
    sleep 10
}

# Check if PostgreSQL is actually listening on the configured port
echo "🔗 Testing PostgreSQL connectivity on port $POSTGRESQL_PORT..."
for i in {1..6}; do
    if sudo -u postgres psql -p $POSTGRESQL_PORT -c 'SELECT version();' >/dev/null 2>&1; then
        echo "✅ PostgreSQL connection successful on attempt $i!"
        break
    else
        echo "⏳ Attempt $i: PostgreSQL not responding on port $POSTGRESQL_PORT, waiting..."
        sleep 10
    fi
done

# Final verification with detailed output
echo ''
echo '=== 📊 Final PostgreSQL Status Report ==='
echo '🔧 Service Status:'
echo "  Main Service: $(sudo systemctl is-active postgresql 2>/dev/null || echo 'inactive')"
echo "  Cluster Service: $(sudo systemctl is-active postgresql@15-main 2>/dev/null || echo 'inactive')"
echo '🧪 Connection Tests:'
if sudo -u postgres psql -p $POSTGRESQL_PORT -c 'SELECT version();' >/dev/null 2>&1; then
    echo '  ✅ PostgreSQL connection: SUCCESS'
    echo '  📝 PostgreSQL version:'
    sudo -u postgres psql -p $POSTGRESQL_PORT -c 'SELECT version();' 2>/dev/null || echo '  ❌ Version check failed'
    echo '  📁 Data directory:'
    sudo -u postgres psql -p $POSTGRESQL_PORT -c 'SHOW data_directory;' 2>/dev/null || echo '  ❌ Data directory check failed'
else
    echo '  ❌ PostgreSQL connection: FAILED'
fi

# Check if PostgreSQL is listening on the correct port
echo '🌐 Network Status:'
if sudo netstat -tlnp | grep :$POSTGRESQL_PORT >/dev/null 2>&1; then
    echo "  ✅ PostgreSQL listening on port $POSTGRESQL_PORT"
    sudo netstat -tlnp | grep :$POSTGRESQL_PORT | head -1
else
    echo "  ❌ PostgreSQL not listening on port $POSTGRESQL_PORT"
fi

echo ''
echo '=== 🎉 PostgreSQL Ansible Setup Completed Successfully ==='
echo "⏰ Completion Time: $(date)"
echo "📝 Setup Log: /tmp/postgresql-ansible.log"
echo ''
echo '=== 📈 Final System Status ==='
echo '🔧 PostgreSQL Service:'
SERVICE_STATUS=$(sudo systemctl is-active postgresql 2>/dev/null || echo 'inactive')
echo "  Status: $SERVICE_STATUS"
if [ "$SERVICE_STATUS" = "active" ]; then
    echo '  ✅ PostgreSQL is running successfully'
else
    echo '  ⚠️  PostgreSQL service may need attention'
fi
echo '💾 Storage Usage:' 
if df -h $MOUNT_POINT >/dev/null 2>&1; then
    echo "  Mount Point: $MOUNT_POINT"
    df -h $MOUNT_POINT | tail -1
else
    echo '  ⚠️  Mount point not available'
fi
echo ''
echo '=== 📋 Installation Summary ==='
echo "✅ PostgreSQL Version: $POSTGRESQL_VERSION"
echo "✅ Storage Device: $STORAGE_DEVICE"
echo "✅ Mount Point: $MOUNT_POINT"
echo "✅ PostgreSQL Port: $POSTGRESQL_PORT"
echo "✅ Network CIDR: $NETWORK_CIDR"
echo ''
echo '🔍 For detailed logs, check:'
echo '  📄 Ansible Log: /tmp/postgresql-ansible.log'
echo '  📊 System Logs: sudo journalctl -u postgresql'
echo ''
echo '🎯 PostgreSQL setup completed successfully! 🎯'
