# Cloud-agnostic base infrastructure module
locals {
  # Normalize provider-specific inputs
  network_name       = var.network_name != "" ? var.network_name : var.vpc_name
  network_cidr       = var.network_cidr != "" ? var.network_cidr : var.vpc_cidr
  public_subnets     = var.public_subnets != [] ? var.public_subnets : var.public_subnet_cidrs
  private_subnets    = var.private_subnets != [] ? var.private_subnets : var.private_subnet_cidrs
  availability_zones = var.availability_zones != [] ? var.availability_zones : var.azs
}

# AWS Network Module
module "aws_network" {
  count  = var.cloud_provider == "aws" ? 1 : 0
  source = "./aws"

  # Common parameters
  network_name       = local.network_name
  network_cidr       = local.network_cidr
  public_subnets     = local.public_subnets
  private_subnets    = local.private_subnets
  availability_zones = local.availability_zones
  environment        = var.environment
  project_name       = var.project_name
  
  # MOSIP-specific variables
  jumpserver_name    = var.jumpserver_name
  mosip_email_id     = var.mosip_email_id

  # Jump server variables
  ssh_key_name             = var.ssh_key_name
  jumpserver_instance_type = var.jumpserver_instance_type
  jumpserver_ami_id        = var.jumpserver_ami_id
  create_jumpserver_eip    = var.create_jumpserver_eip

  # WireGuard automation variables
  k8s_infra_repo_url     = var.k8s_infra_repo_url
  k8s_infra_branch       = var.k8s_infra_branch
  wireguard_peers        = var.wireguard_peers
  enable_wireguard_setup = var.enable_wireguard_setup

  # AWS-specific
  enable_dns_hostnames = var.enable_dns_hostnames
  enable_dns_support   = var.enable_dns_support
  enable_nat_gateway   = var.enable_nat_gateway
  single_nat_gateway   = var.single_nat_gateway
}

# TODO: Implement Azure and GCP modules when needed
# For now, only AWS is supported

# Azure Network Module (placeholder - not implemented)
# module "azure_network" {
#   source = "./azure"
#   count  = var.cloud_provider == "azure" ? 1 : 0
#   
#   # ... Azure specific configuration ...
# }

# GCP Network Module (placeholder - not implemented)  
# module "gcp_network" {
#   source = "./gcp"
#   count  = var.cloud_provider == "gcp" ? 1 : 0
#   
#   # ... GCP specific configuration ...
# }
