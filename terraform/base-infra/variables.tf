# Cloud provider selection
variable "cloud_provider" {
  description = "Cloud provider to deploy infrastructure (aws, azure, gcp)"
  type        = string
  default     = "aws"
  
  validation {
    condition     = contains(["aws", "azure", "gcp"], var.cloud_provider)
    error_message = "Valid values for cloud_provider are: aws, azure, gcp"
  }
}

# Common variables
variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "demo"
}

# MOSIP-specific variables
variable "jumpserver_name" {
  description = "Name of the jump server"
  type        = string
}

variable "mosip_email_id" {
  description = "Email-ID for SSL certificate notifications"
  type        = string
}

# Jump server variables
variable "ssh_key_name" {
  description = "SSH key name for AWS node instances"
  type        = string
}

variable "jumpserver_instance_type" {
  description = "The instance type for jump server"
  type        = string
  default     = "t3a.2xlarge"
}

# AWS/Common network variables
variable "vpc_name" {
  description = "Name of the VPC (AWS)"
  type        = string
  default     = ""
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC (AWS)"
  type        = string
  default     = "10.0.0.0/16"
}

variable "network_name" {
  description = "Name of the network (cloud-agnostic)"
  type        = string
  default     = ""
}

variable "network_cidr" {
  description = "CIDR block for the network (cloud-agnostic)"
  type        = string
  default     = ""
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (AWS specific naming)"
  type        = list(string)
  default     = []
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (AWS specific naming)"
  type        = list(string)
  default     = []
}

variable "public_subnets" {
  description = "CIDR blocks for public subnets (cloud-agnostic naming)"
  type        = list(string)
  default     = []
}

variable "private_subnets" {
  description = "CIDR blocks for private subnets (cloud-agnostic naming)"
  type        = list(string)
  default     = []
}

variable "availability_zones" {
  description = "Availability zones to deploy subnets"
  type        = list(string)
  default     = []
}

variable "azs" {
  description = "Availability zones (AWS specific naming)"
  type        = list(string)
  default     = []
}

# AWS Region - specific to AWS but needed for interface
variable "aws_provider_region" {
  description = "The AWS region for resource creation"
  type        = string
  default     = "us-east-1"
}

# AWS-specific variables
variable "enable_dns_hostnames" {
  description = "Enable DNS hostnames in VPC"
  type        = bool
  default     = true
}

variable "enable_dns_support" {
  description = "Enable DNS support in VPC"
  type        = bool
  default     = true
}

variable "enable_nat_gateway" {
  description = "Enable NAT gateway(s) for private subnets"
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "Use a single NAT gateway for all private subnets"
  type        = bool
  default     = false
}

# Azure-specific variables
variable "location" {
  description = "Azure region to deploy resources"
  type        = string
  default     = "eastus"
}

variable "resource_group_name" {
  description = "Resource group name"
  type        = string
  default     = ""
}

# GCP-specific variables
variable "project_id" {
  description = "GCP project ID"
  type        = string
  default     = ""
}

variable "region" {
  description = "GCP region to deploy resources"
  type        = string
  default     = "us-central1"
}


# Jump server AMI ID (required)
variable "jumpserver_ami_id" {
  description = "The AMI ID to use for the jump server (required)"
  type        = string
  
  validation {
    condition     = length(var.jumpserver_ami_id) > 0
    error_message = "The jumpserver_ami_id value is required and cannot be empty."
  }
}

# Jump server EIP option
variable "create_jumpserver_eip" {
  description = "Whether to create an Elastic IP for the jump server (true) or use auto-assigned public IP (false)"
  type        = bool
  default     = false
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

variable "ssh_private_key" {
  description = "SSH private key content for jumpserver access (used for automation)"
  type        = string
  sensitive   = true
  default     = ""
}