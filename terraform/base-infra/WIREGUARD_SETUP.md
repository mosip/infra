# WireGuard VPN Setup Guide

This guide explains how to set up WireGuard VPN client access after base infrastructure deployment. WireGuard provides secure access to your MOSIP infrastructure via private IPs.

## Prerequisites

- Base infrastructure successfully deployed via Terraform
- Jump server (WireGuard server) is running and accessible
- SSH access to the jump server

## WireGuard Server Setup (Automated via Terraform)

The WireGuard server is automatically configured during base infrastructure deployment. The server:
- Runs as a Docker container on the jump server
- Generates peer configuration files automatically
- Provides secure VPN access to private subnets

## Client Setup Process

### Step 1: Access the Jump Server

```bash
# SSH into the jump server using your configured SSH key
ssh -i your-ssh-key.pem ubuntu@<jump-server-public-ip>
```

### Step 2: Navigate to WireGuard Configuration Directory

```bash
# Change to the WireGuard config directory
# This directory is mounted to the WireGuard Docker container
cd /home/ubuntu/wireguard/config

# List available peer configurations
ls
```

**Expected output:**
```
peer1/ peer2/ peer3/ peer4/ peer5/ ...
```

### Step 3: Assign and Configure a Peer

#### 3.1 Create Assignment Tracking File

```bash
# Create or update the assigned.txt file to track peer allocations
nano assigned.txt
```

**Example assigned.txt content:**
```
peer1 : john.doe
peer2 : jane.smith 
peer3 : admin.user
peer4 : available
peer5 : available
```

#### 3.2 Select and Configure Your Peer

```bash
# Choose an available peer (e.g., peer4)
cd peer4

# Edit the peer configuration
nano peer4.conf
```

#### 3.3 Update Peer Configuration

**Original peer.conf example:**
```ini
[Interface]
PrivateKey = <generated-private-key>
Address = 10.0.1.4/24
DNS = 1.1.1.1

[Peer]
PublicKey = <server-public-key>
Endpoint = <jump-server-public-ip>:51820
AllowedIPs = 0.0.0.0/0
```

**Updated peer.conf (make these changes):**
```ini
[Interface]
PrivateKey = <generated-private-key>
Address = 10.0.1.4/24
# DNS = 1.1.1.1 <-- DELETE THIS LINE

[Peer]
PublicKey = <server-public-key>
Endpoint = <jump-server-public-ip>:51820
AllowedIPs = 10.10.20.0/23 # <-- UPDATE TO YOUR SUBNET CIDR
```

**Required Changes:**
1. **Delete DNS IP**: Remove the `DNS = 1.1.1.1` line
2. **Update AllowedIPs**: Change from `0.0.0.0/0` to your subnet CIDR (e.g., `10.10.20.0/23`)

### Step 4: Install WireGuard Client on Your PC

#### 4.1 Install WireGuard

**Linux (Ubuntu/Debian):**
```bash
sudo apt update
sudo apt install wireguard
```

**macOS:**
```bash
brew install wireguard-tools
# Or download WireGuard app from Mac App Store
```

**Windows:**
- Download WireGuard client from [wireguard.com](https://www.wireguard.com/install/)

#### 4.2 Configure Client

**Linux Setup:**
```bash
# Copy the peer configuration to your PC
scp -i your-ssh-key.pem ubuntu@<jump-server-ip>:/home/ubuntu/wireguard/config/peer4/peer4.conf ~/

# Move to WireGuard directory and rename
sudo mv ~/peer4.conf /etc/wireguard/wg0.conf

# Set proper permissions
sudo chmod 600 /etc/wireguard/wg0.conf
```

**macOS/Windows:**
- Copy the peer configuration file content
- Import it into the WireGuard application

### Step 5: Start WireGuard Connection

**Linux:**
```bash
# Start WireGuard
sudo systemctl start wg-quick@wg0

# Check status
sudo systemctl status wg-quick@wg0

# Enable auto-start on boot (optional)
sudo systemctl enable wg-quick@wg0
```

**macOS/Windows:**
- Open WireGuard application
- Import/activate your configuration
- Click "Connect"

### Step 6: Verify Connection

```bash
# Check WireGuard interface
sudo wg show

# Test connectivity to private IPs
ping <private-ip-of-kubernetes-node>

# Verify you can access private services
curl http://<private-service-ip>
```

## Environment Secret Configuration

### Configure Multiple WireGuard Secrets

After setting up WireGuard, you need to create **multiple peer configurations** and add them as GitHub repository environment secrets:

#### Required Peer Configurations

1. **Create Multiple Peers:**
 ```bash
 # Configure peer1 for Terraform access
 cd /home/ubuntu/wireguard/config/peer1
 nano peer1.conf
 
 # Configure peer2 for Helmsman access 
 cd /home/ubuntu/wireguard/config/peer2
 nano peer2.conf
 ```

2. **Apply Same Configuration Changes to Both Peers:**
 - Delete the DNS IP line
 - Update AllowedIPs to your subnet CIDR (e.g., `10.10.20.0/23`)

#### GitHub Environment Secrets Setup

**Navigate to GitHub Repository:**
- Settings → Environments → Your Branch Environment

**Add the following Environment Secrets:**

1. **TF_WG_CONFIG Secret:**
 - Name: `TF_WG_CONFIG`
 - Value: Contents of `peer1.conf`
 - Purpose: Terraform infrastructure deployments via private IPs

2. **CLUSTER_WIREGUARD_WG0 Secret:**
 - Name: `CLUSTER_WIREGUARD_WG0`
 - Value: Contents of `peer1.conf` 
 - Purpose: Helmsman cluster access (primary connection)

3. **CLUSTER_WIREGUARD_WG1 Secret:**
 - Name: `CLUSTER_WIREGUARD_WG1`
 - Value: Contents of `peer2.conf`
 - Purpose: Helmsman cluster access (secondary connection)

#### Secret Configuration Summary

```yaml
# Required Environment Secrets for WireGuard Access
TF_WG_CONFIG: "<peer1-config-content>" # Terraform workflows
CLUSTER_WIREGUARD_WG0: "<peer1-config-content>" # Helmsman primary
CLUSTER_WIREGUARD_WG1: "<peer2-config-content>" # Helmsman secondary
```

#### Purpose of Multiple Configurations

- **Load Distribution:** Distribute connections across multiple peers
- **High Availability:** Backup connection if one peer fails
- **Workflow Isolation:** Separate connections for different deployment types
- **Connection Limits:** Avoid WireGuard peer connection limits

## Troubleshooting

### Connection Issues

**Cannot connect to WireGuard:**
```bash
# Check WireGuard server status on jump server
sudo docker ps | grep wireguard
sudo docker logs <wireguard-container-id>
```

**Cannot access private IPs:**
- Verify AllowedIPs configuration matches your subnet
- Check firewall rules on target servers
- Confirm WireGuard is connected: `sudo wg show`

**DNS Resolution Issues:**
- Ensure DNS line is removed from peer configuration
- Use private IPs directly instead of hostnames

### Configuration Validation

**Validate peer configuration:**
```bash
# Check configuration syntax
sudo wg-quick strip /etc/wireguard/wg0.conf

# Test configuration without starting
sudo wg-quick up /etc/wireguard/wg0.conf --dry-run
```

## Security Best Practices

1. **Peer Assignment:** Always update `assigned.txt` when allocating peers
2. **Configuration Security:** Keep peer private keys secure and never share
3. **Access Control:** Only assign peers to authorized personnel
4. **Regular Cleanup:** Remove unused peer configurations periodically
5. **Monitoring:** Monitor WireGuard server logs for unauthorized access attempts

## Next Steps

Once WireGuard is configured and the `TF_WG_CONFIG` secret is set:

1. **Deploy Observability Infrastructure** (if needed)
2. **Deploy MOSIP Infrastructure** via private network
3. **Configure Helmsman** to use private IPs for cluster access

> **Note:** All subsequent Terraform and Helmsman deployments will use the WireGuard VPN connection for secure private network access.