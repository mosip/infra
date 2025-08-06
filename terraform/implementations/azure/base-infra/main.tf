# Azure Base Infrastructure Implementation
provider "azurerm" {
  features {}
}

variable "azure_provider_region" {
  description = "The Azure region to deploy resources in"
  type        = string
}

variable "cloud_provider" {
  description = "The cloud provider for the base infrastructure"
  type        = string
}

variable "tag_date" {
  description = "Tag for tracking resource creation date"
  type        = string
  default     = ""
}

variable "tag_user" {
  description = "Tag for tracking resource creator"
  type        = string
  default     = ""
}

variable "jumpserver_name" {
  description = "The name of the jumpserver instance"
  type        = string
}

variable "network_name" {
  description = "The name of the network (VNet) to create"
  type        = string
}

variable "network_cidr" {
  description = "The CIDR block for the VNet network"
  type        = string
}

variable "public_subnets" {
  description = "A list of public subnet CIDR blocks"
  type        = list(string)
}

variable "private_subnets" {
  description = "A list of private subnet CIDR blocks"
  type        = list(string)
}

variable "availability_zones" {
  description = "A list of availability zones to use for the subnets"
  type        = list(string)
}

variable "jumpserver_ami_id" {
  description = "The VM image ID to use for the jumpserver instance"
  type        = string
}

variable "ssh_key_name" {
  description = "The name of the SSH key pair to use for the jumpserver"
  type        = string
}

variable "jumpserver_instance_type" {
  description = "The VM instance type for the jumpserver"
  type        = string
}

variable "create_jumpserver_eip" {
  description = "Whether to create a public IP for the jumpserver"
  type        = bool
  default     = true
}

variable "environment" {
  description = "The environment for the deployment (e.g., dev, staging, prod)"
  type        = string
}

variable "mosip_email_id" {
  description = "The email ID for MOSIP notifications or tagging"
  type        = string
}

variable "project_name" {
  description = "The name of the project"
  type        = string
}

variable "enable_nat_gateway" {
  description = "Whether to enable NAT Gateway"
  type        = bool
  default     = false
}

variable "single_nat_gateway" {
  description = "Whether to use a single NAT Gateway for all private subnets"
  type        = bool
  default     = true
}

variable "enable_dns_hostnames" {
  description = "Whether to enable DNS hostnames for the VNet"
  type        = bool
  default     = true
}

variable "enable_dns_support" {
  description = "Whether to enable DNS support for the VNet"
  type        = bool
  default     = true
}

module "base_infrastructure" {
  source = "../../../base-infra"

  # Cloud provider
  cloud_provider = var.cloud_provider

  # Resource naming
  jumpserver_name = var.jumpserver_name
  
  # Network configuration
  network_name       = var.network_name
  network_cidr       = var.network_cidr
  public_subnets     = var.public_subnets
  private_subnets    = var.private_subnets
  availability_zones = var.availability_zones
  
  # Jump server configuration
  ssh_key_name             = var.ssh_key_name
  jumpserver_instance_type = var.jumpserver_instance_type
  jumpserver_ami_id        = var.jumpserver_ami_id
  create_jumpserver_eip    = var.create_jumpserver_eip
  
  # Environment metadata
  environment    = var.environment
  project_name   = var.project_name
  mosip_email_id = var.mosip_email_id

  # Azure specific options
  enable_nat_gateway   = var.enable_nat_gateway
  single_nat_gateway   = var.single_nat_gateway
  enable_dns_hostnames = var.enable_dns_hostnames
  enable_dns_support   = var.enable_dns_support
}

output "jumpserver_public_ip" {
  description = "The public IP address assigned to the jump server instance"
  value       = module.base_infrastructure.jumpserver_public_ip
  sensitive   = false
}

output "network_id" {
  description = "The ID of the VNet where resources are deployed"
  value       = module.base_infrastructure.network_id
  sensitive   = false
}

output "public_subnet_ids" {
  description = "List of IDs of the public subnets created within the VNet"
  value       = module.base_infrastructure.public_subnet_ids
  sensitive   = false
}

output "private_subnet_ids" {
  description = "List of IDs of the private subnets created within the VNet"
  value       = module.base_infrastructure.private_subnet_ids
  sensitive   = false
}

output "cloud_specific" {
  description = "Map of Azure-specific resource identifiers and configurations"
  value       = module.base_infrastructure.cloud_specific
  sensitive   = false
}
