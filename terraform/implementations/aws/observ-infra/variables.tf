# AWS Implementation Variables

# Cloud provider selection
variable "cloud_provider" {
  description = "Cloud provider to use (aws, azure, gcp)"
  type        = string
  validation {
    condition     = contains(["aws", "azure", "gcp"], var.cloud_provider)
    error_message = "Cloud provider must be one of: aws, azure, gcp"
  }
}

variable "aws_provider_region" {
  description = "AWS region for resource creation"
  type        = string
}

variable "specific_availability_zones" {
  description = "Specific availability zones to use for VM deployment (e.g., ['us-east-1a', 'us-east-1b']). If empty, uses all available AZs in the region."
  type        = list(string)
  default     = []
  validation {
    condition     = length(var.specific_availability_zones) == 0 || length(var.specific_availability_zones) >= 1
    error_message = "specific_availability_zones must be empty (use all AZs) or contain at least 1 availability zone."
  }
}

variable "cluster_name" {
  description = "Name of the cluster"
  type        = string
}

variable "cluster_env_domain" {
  description = "MOSIP DOMAIN : (ex: sandbox.xyz.net)"
  type        = string
  validation {
    condition     = can(regex("^(([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9-]*[a-zA-Z0-9])\\.)+[a-zA-Z]{2,}$", var.cluster_env_domain))
    error_message = "The domain name must be a valid domain name, e.g., sandbox.xyz.net."
  }
}

variable "k8s_control_plane_node_count" {
  description = "Number of K8s control plane nodes"
  type        = number
}

variable "k8s_etcd_node_count" {
  description = "Number of K8s ETCD nodes"
  type        = number
}

variable "k8s_worker_node_count" {
  description = "Number of K8s worker nodes"
  type        = number
}

variable "subdomain_public" {
  description = "List of public subdomains to create CNAME records for"
  type        = list(string)
}

variable "subdomain_internal" {
  description = "List of internal subdomains to create CNAME records for"
  type        = list(string)
}

variable "mosip_email_id" {
  description = "Email ID used by certbot to generate SSL certs for Nginx node"
  type        = string
  validation {
    condition     = can(regex("^\\S+@\\S+\\.\\S+$", var.mosip_email_id))
    error_message = "The email address must be a valid email format (e.g., user@example.com)."
  }
}

variable "ssh_private_key" {
  description = "SSH private key for instance access"
  type        = string
  sensitive   = true
}

variable "enable_rancher_import" {
  description = "Set to true to enable Rancher import"
  type        = bool
  default     = false
}

variable "rancher_import_url" {
  description = "Rancher import URL for kubectl apply"
  type        = string
  validation {
    condition     = can(regex("^\"kubectl apply -f https://rancher\\.mosip\\.net/v3/import/[a-zA-Z0-9_\\-]+\\.yaml\"$", var.rancher_import_url))
    error_message = "The RANCHER_IMPORT_URL must be in the format: '\"kubectl apply -f https://rancher.mosip.net/v3/import/<ID>.yaml\"'"
  }
}

variable "k8s_infra_repo_url" {
  description = "The URL of the Kubernetes infrastructure GitHub repository"
  type        = string
  default     = "https://github.com/mosip/k8s-infra.git"
}

variable "k8s_infra_branch" {
  description = "Branch of the K8s infrastructure repository"
  type        = string
  default     = "develop"
}

variable "k8s_instance_type" {
  description = "Instance type for K8s nodes"
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9]+\\..*", var.k8s_instance_type))
    error_message = "Invalid instance type format. Must be in the form 'series.type'."
  }
}

variable "nginx_instance_type" {
  description = "Instance type for NGINX server"
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9]+\\..*", var.nginx_instance_type))
    error_message = "Invalid instance type format. Must be in the form 'series.type'."
  }
}

variable "ami" {
  description = "AMI ID for AWS instances"
  type        = string
  validation {
    condition     = can(regex("^ami-[a-f0-9]{17}$", var.ami))
    error_message = "Invalid AMI format. It should be in the format 'ami-xxxxxxxxxxxxxxxxx'"
  }
}

variable "ssh_key_name" {
  description = "Name of the SSH key pair in AWS"
  type        = string
}

variable "zone_id" {
  description = "Route53 hosted zone ID"
  type        = string
}

variable "vpc_name" {
  description = "Name of the existing VPC (will be discovered by tag:Name)"
  type        = string
}

variable "nginx_node_root_volume_size" {
  description = "Root volume size for NGINX node"
  type        = number
}

variable "nginx_node_ebs_volume_size" {
  description = "EBS volume size for NGINX node (first volume)"
  type        = number
}

variable "nginx_node_ebs_volume_size_2" {
  description = "EBS volume size for NGINX node (second volume) - set to 0 to disable"
  type        = number
  default     = 0
}

variable "k8s_instance_root_volume_size" {
  description = "Root volume size for K8s instances"
  type        = number
}

variable "network_cidr" {
  description = "VPC CIDR block for internal communication and DNS rules"
  type        = string
}

variable "WIREGUARD_CIDR" {
  description = "CIDR block for WireGuard VPN server(s)"
  type        = string
}

# Rancher-Keycloak Integration Variables
variable "enable_rancher_keycloak_integration" {
  description = "Enable Rancher and Keycloak installation on the observability cluster"
  type        = bool
  default     = true
}

variable "rancher_hostname" {
  description = "Hostname for Rancher UI (will be constructed from cluster_env_domain)"
  type        = string
  default     = ""
}

variable "keycloak_hostname" {
  description = "Hostname for Keycloak (will be constructed from cluster_env_domain)"
  type        = string
  default     = ""
}

variable "rancher_bootstrap_password" {
  description = "Bootstrap password for Rancher UI"
  type        = string
  default     = "admin"
  sensitive   = true
}

# RKE2 Configuration
variable "rke2_version" {
  description = "RKE2 version to install"
  type        = string
  default     = "v1.32.8+rke2r1"
  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+\\+rke2r[0-9]+$", var.rke2_version))
    error_message = "RKE2 version must be in format 'vX.Y.Z+rke2rN' (e.g., 'v1.28.9+rke2r1')"
  }
}

# PostgreSQL Configuration (for consistency with infra, though disabled in observ-infra)
variable "postgresql_version" {
  description = "PostgreSQL version to install (not used in observ-infra, but maintained for module consistency)"
  type        = string
  default     = "15"
}

variable "storage_device" {
  description = "Storage device path for PostgreSQL data (not used in observ-infra, but maintained for module consistency)"
  type        = string
  default     = "/dev/nvme2n1"
}

variable "mount_point" {
  description = "Mount point for PostgreSQL data directory (not used in observ-infra, but maintained for module consistency)"
  type        = string
  default     = "/srv/postgres"
}

variable "postgresql_port" {
  description = "PostgreSQL port configuration (not used in observ-infra, but maintained for module consistency)"
  type        = string
  default     = "5433"
}

# MOSIP Infrastructure Repository Configuration
variable "mosip_infra_repo_url" {
  description = "URL of the MOSIP infrastructure repository"
  type        = string
  default     = "https://github.com/bhumi46/mosip-infra.git"
}

variable "mosip_infra_branch" {
  description = "Branch of the MOSIP infrastructure repository"
  type        = string
  default     = "develop"
}
