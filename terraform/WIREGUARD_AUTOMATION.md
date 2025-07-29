# WireGuard Setup Automation

This document describes the automated WireGuard setup process integrated into the Terraform base-infra provisioning.

## Overview

The jumpserver EC2 instance is now automatically provisioned with:
- Docker and Ansible installation
- k8s-infra repository cloning
- WireGuard container setup with configurable peer count
- Useful management scripts and aliases

## Directory Structure

```
terraform/
├── base-infra/                           # Cloud-agnostic base infrastructure
│   ├── main.tf                          # Main configuration
│   ├── variables.tf                     # Cloud-agnostic variables
│   ├── outputs.tf                       # Base outputs
│   └── aws/                             # AWS-specific implementation
│       ├── main.tf                      # AWS resources (VPC, subnets, jumpserver)
│       ├── variables.tf                 # AWS-specific variables
│       ├── outputs.tf                   # AWS outputs including WireGuard info
│       └── jumpserver-setup.sh.tpl     # User data script for automation
├── implementations/                      # Environment-specific configurations
│   └── aws/
│       └── base-infra/
│           └── aws.tfvars               # AWS configuration values
└── modules/                             # Reusable Terraform modules
    └── aws/
        └── ...
```

## Configuration Variables

### WireGuard Automation Variables

Add these variables to your `terraform/implementations/aws/base-infra/aws.tfvars`:

```hcl
# WireGuard automation configuration
k8s_infra_repo_url     = "https://github.com/mosip/k8s-infra.git"
k8s_infra_branch       = "develop"
wireguard_peers        = 30
enable_wireguard_setup = true
```

### Variable Descriptions

- `k8s_infra_repo_url`: Git repository URL for k8s-infra (default: MOSIP official repo)
- `k8s_infra_branch`: Branch to checkout (default: develop)
- `wireguard_peers`: Number of WireGuard peer configurations to generate (default: 30)
- `enable_wireguard_setup`: Enable/disable WireGuard automation (default: true)

## Automated Setup Process

When the jumpserver EC2 instance boots, the following automated steps occur:

1. **System Setup**
   - Update system packages
   - Install Docker, Ansible, Git, and other utilities
   - Add ubuntu user to docker group

2. **Repository Setup**
   - Clone the k8s-infra repository to `/home/ubuntu/k8s-infra`
   - Checkout the specified branch
   - Set proper ownership for ubuntu user

3. **WireGuard Container Setup** (if enabled)
   - Create WireGuard config directory at `/home/ubuntu/wireguard/config`
   - Start WireGuard container with LinuxServer.io image
   - Configure container with specified peer count
   - Expose WireGuard on port 51820/udp

4. **Management Tools**
   - Create useful bash aliases for WireGuard management
   - Generate helper script for viewing client configurations
   - Create status files for monitoring setup completion

## Post-Deployment Usage

### Connecting to the Jumpserver

```bash
ssh -i /path/to/your/private-key ubuntu@<jumpserver-public-ip>
```

### WireGuard Management Commands

Once connected to the jumpserver, you can use these commands:

```bash
# Check WireGuard container status
wg-status

# Restart WireGuard container
wg-restart

# List WireGuard configuration files
wg-config

# View available client configurations
./get-wireguard-configs.sh

# Navigate to k8s-infra directory
k8s-infra

# Navigate to WireGuard directory in k8s-infra
wg-dir
```

### Accessing Client Configurations

WireGuard client configurations are automatically generated and stored at:
```
/home/ubuntu/wireguard/config/
├── peer1/
│   ├── peer1.conf    # Client configuration file
│   └── peer1.png     # QR code for mobile clients
├── peer2/
│   ├── peer2.conf
│   └── peer2.png
└── ...
```

To view a client configuration:
```bash
cat /home/ubuntu/wireguard/config/peer1/peer1.conf
```

## Terraform Outputs

After successful deployment, Terraform provides these outputs:

### General Outputs
- `jumpserver_public_ip`: Public IP address of the jumpserver
- `jumpserver_private_ip`: Private IP address of the jumpserver
- `jumpserver_id`: EC2 instance ID

### WireGuard Specific Outputs
- `wireguard_info`: Complete WireGuard configuration details including:
  - Status (enabled/disabled)
  - Number of peers configured
  - WireGuard port (51820)
  - Config file locations
  - Helpful SSH commands for management

## Logs and Troubleshooting

### Setup Logs
The automated setup process logs all activities to:
```
/var/log/jumpserver-setup.log
```

### Status File
Setup completion is indicated by:
```
/home/ubuntu/jumpserver-setup-complete.txt
```

### WireGuard Container Logs
```bash
sudo docker logs wireguard
```

### Common Issues

1. **WireGuard container not starting**
   - Check Docker service status: `sudo systemctl status docker`
   - Review setup logs: `sudo tail -f /var/log/jumpserver-setup.log`

2. **Permission issues with config files**
   - Configs should be owned by ubuntu:ubuntu
   - Check with: `ls -la /home/ubuntu/wireguard/config/`

3. **Network connectivity issues**
   - Ensure port 51820/udp is open in security group
   - Check AWS security group rules in EC2 console

## Security Considerations

1. **EC2 Security Group**: Automatically configured with:
   - SSH (22/tcp) from your IP
   - WireGuard (51820/udp) from anywhere
   - HTTP/HTTPS (80,443/tcp) from anywhere

2. **WireGuard Network**: Uses default 10.13.13.0/24 subnet
3. **Docker Security**: Container runs with required network capabilities
4. **File Permissions**: Config files are properly secured for ubuntu user

## Customization

### Changing WireGuard Settings

To modify WireGuard configuration:

1. Update variables in `aws.tfvars`
2. Run `terraform apply`
3. The instance will be recreated with new configuration

### Using Different Repository

To use a different k8s-infra repository:

1. Update `k8s_infra_repo_url` in `aws.tfvars`
2. Optionally change `k8s_infra_branch`
3. Apply Terraform changes

### Disabling WireGuard

To create jumpserver without WireGuard:
```hcl
enable_wireguard_setup = false
```

## Integration with k8s-infra

The automated setup ensures compatibility with the existing k8s-infra WireGuard configuration:

1. Repository is cloned to the expected location
2. Docker and Ansible are pre-installed
3. WireGuard container uses standard LinuxServer.io image
4. Configuration directory structure matches k8s-infra expectations

This allows you to continue using existing k8s-infra documentation and procedures for advanced WireGuard management while benefiting from the automated initial setup.
