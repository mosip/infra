# AWS Base Infrastructure Implementation
# Created: 2025-07-24 12:53:18
# Created by: bhumi46

provider "aws" {
  region = var.aws_provider_region
}

variable "aws_provider_region" {
  description = "The AWS region to deploy resources in"
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

# WireGuard automation variables
variable "k8s_infra_repo_url" {
  description = "URL of the k8s-infra repository"
  type        = string
  default     = "https://github.com/mosip/k8s-infra.git"
}

variable "k8s_infra_branch" {
  description = "Branch of the k8s-infra repository"
  type        = string
  default     = "develop"
}

variable "wireguard_peers" {
  description = "Number of WireGuard peers to create"
  type        = number
  default     = 30
}

variable "enable_wireguard_setup" {
  description = "Whether to automatically setup WireGuard on the jumpserver"
  type        = bool
  default     = true
}

variable "jumpserver_name" {
  description = "The name of the jumpserver instance"
  type        = string
}

variable "network_name" {
  description = "The name of the network (VPC) to create"
  type        = string
}

variable "network_cidr" {
  description = "The CIDR block for the VPC network"
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
  description = "The AMI ID to use for the jumpserver instance"
  type        = string
}

variable "ssh_key_name" {
  description = "The name of the SSH key pair to use for the jumpserver"
  type        = string
}

variable "jumpserver_instance_type" {
  description = "The EC2 instance type for the jumpserver"
  type        = string
}

variable "create_jumpserver_eip" {
  description = "Whether to create an Elastic IP for the jumpserver"
  type        = bool
  default     = false
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
  description = "Whether to enable DNS hostnames for the VPC"
  type        = bool
  default     = true
}

variable "enable_dns_support" {
  description = "Whether to enable DNS support for the VPC"
  type        = bool
  default     = true
}


module "base_infrastructure" {
  source = "../../../base-infra" # Path to your existing module

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

  # AWS specific options
  enable_nat_gateway   = var.enable_nat_gateway
  single_nat_gateway   = var.single_nat_gateway
  enable_dns_hostnames = var.enable_dns_hostnames
  enable_dns_support   = var.enable_dns_support

}

# Add outputs as needed


output "jumpserver_public_ip" {
  description = "The public IP address assigned to the jump server instance"
  value       = module.base_infrastructure.jumpserver_public_ip
  sensitive   = false
}

output "vpc_id" {
  description = "The ID of the VPC where resources are deployed"
  value       = module.base_infrastructure.network_id
  sensitive   = false
}

output "public_subnet_ids" {
  description = "List of IDs of the public subnets created within the VPC"
  value       = module.base_infrastructure.public_subnet_ids
  sensitive   = false
}

output "private_subnet_ids" {
  description = "List of IDs of the private subnets created within the VPC"
  value       = module.base_infrastructure.private_subnet_ids
  sensitive   = false
}

output "cloud_specific" {
  description = "Map of AWS-specific resource identifiers and configurations"
  value       = module.base_infrastructure.cloud_specific
  sensitive   = false
}