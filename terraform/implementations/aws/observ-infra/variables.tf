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
  validation {
    condition     = can(regex("^https://github\\.com/.+/.+\\.git$", var.k8s_infra_repo_url))
    error_message = "The K8S_INFRA_REPO_URL must be a valid GitHub repository URL ending with .git"
  }
}

variable "k8s_infra_branch" {
  description = "Branch of the K8s infrastructure repository"
  type        = string
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
  description = "EBS volume size for NGINX node"
  type        = number
}

variable "k8s_instance_root_volume_size" {
  description = "Root volume size for K8s instances"
  type        = number
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
