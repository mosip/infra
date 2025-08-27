# AWS environment configuration values
# Created: 2025-07-24 13:05:18
# Created by: bhumi46

# Cloud provider
cloud_provider = "aws"

# Environment name
jumpserver_name = "mosip-wg-testvpc"

# Email-ID for SSL certificate notifications
mosip_email_id = "chandra.mishra@technoforte.co.in"

# SSH key name for AWS instances
ssh_key_name = "mosip-aws"

# AWS region
aws_provider_region = "ap-south-1"

# Jump server instance type
jumpserver_instance_type = "t3.medium"

# Jump server AMI ID (required)
jumpserver_ami_id = "ami-0ad21ae1d0696ad58"

# Whether to create an Elastic IP for the jump server
create_jumpserver_eip = false

# Network configuration
network_name       = "mosip-boxes"
network_cidr       = "10.0.0.0/16"
public_subnets     = ["10.0.1.0/24", "10.0.2.0/24"]
private_subnets    = ["10.0.3.0/24", "10.0.4.0/24"]
availability_zones = ["ap-south-1a", "ap-south-1b"]

# Environment and project tags
environment  = "dev"
project_name = "mosip"

# Network options
enable_nat_gateway   = true
single_nat_gateway   = true
enable_dns_hostnames = true
enable_dns_support   = true

# WireGuard automation configuration
k8s_infra_repo_url     = "https://github.com/mosip/k8s-infra.git"
k8s_infra_branch       = "develop"
wireguard_peers        = 30
enable_wireguard_setup = true

