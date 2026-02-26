# Common network variables with cloud-agnostic naming

variable "network_name" {
  description = "Name of the network"
  type        = string
}

variable "network_cidr" {
  description = "CIDR block for the network"
  type        = string
}

variable "public_subnets" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
}

variable "private_subnets" {
  description = "CIDR blocks for private subnets"
  type        = list(string)
}

variable "availability_zones" {
  description = "Availability zones to deploy subnets"
  type        = list(string)
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "project_name" {
  description = "Project name"
  type        = string
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

# Jump server AMI ID (required)
variable "jumpserver_ami_id" {
  description = "The AMI ID to use for the jump server (required)"
  type        = string
}

# Jump server EIP option
variable "create_jumpserver_eip" {
  description = "Whether to create an Elastic IP for the jump server"
  type        = bool
  default     = true
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