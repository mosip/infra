# Azure environment configuration values
# Created: 2025-07-25

# Cloud provider
cloud_provider = "azure"

# Environment name
jumpserver_name = "testvnet"

# Email-ID for SSL certificate notifications
mosip_email_id = "admin@example.com"

# SSH key name for Azure VMs
ssh_key_name = "mosip-azure"

# Azure region
azure_provider_region = "East US"

# Jump server instance type (Azure VM size)
jumpserver_instance_type = "Standard_D4s_v3"

# Jump server VM image ID (required)
jumpserver_ami_id = "/subscriptions/your-subscription-id/resourceGroups/your-rg/providers/Microsoft.Compute/images/your-image"

# Whether to create a public IP for the jump server
create_jumpserver_eip = false

# Network configuration
network_name = "testvnet-network"
network_cidr = "10.1.0.0/16"

# Public subnet configuration
public_subnets = ["10.1.1.0/24", "10.1.2.0/24"]

# Private subnet configuration  
private_subnets = ["10.1.10.0/24", "10.1.11.0/24"]

# Availability zones (Azure regions)
availability_zones = ["1", "2"]

# Environment metadata
environment = "dev"
project_name = "mosip"

# Azure-specific options
enable_nat_gateway = false
single_nat_gateway = true
enable_dns_hostnames = true
enable_dns_support = true
