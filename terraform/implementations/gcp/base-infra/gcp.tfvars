# GCP environment configuration values
# Created: 2025-07-25

# Cloud provider
cloud_provider = "gcp"

# GCP project configuration
gcp_project_id = "your-gcp-project-id"
gcp_provider_region = "us-central1"

# Environment name
jumpserver_name = "testvpc"

# Email-ID for SSL certificate notifications
mosip_email_id = "admin@example.com"

# SSH key name for GCP VMs
ssh_key_name = "mosip-gcp"

# Jump server instance type (GCP machine type)
jumpserver_instance_type = "e2-standard-4"

# Jump server VM image ID (required)
jumpserver_ami_id = "projects/ubuntu-os-cloud/global/images/family/ubuntu-2004-lts"

# Whether to create a static IP for the jump server
create_jumpserver_eip = false

# Network configuration
network_name = "testvpc-network"
network_cidr = "10.2.0.0/16"

# Public subnet configuration
public_subnets = ["10.2.1.0/24", "10.2.2.0/24"]

# Private subnet configuration  
private_subnets = ["10.2.10.0/24", "10.2.11.0/24"]

# Availability zones (GCP zones)
availability_zones = ["us-central1-a", "us-central1-b"]

# Environment metadata
environment = "dev"
project_name = "mosip"

# GCP-specific options
enable_nat_gateway = false
single_nat_gateway = true
enable_dns_hostnames = true
enable_dns_support = true
