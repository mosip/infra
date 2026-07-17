# AWS-specific variables for observ-infra (same as infra variables)
variable "cluster_name" { type = string }
variable "cluster_env_domain" { type = string }
variable "k8s_control_plane_node_count" { type = number }
variable "k8s_etcd_node_count" { type = number }
variable "k8s_worker_node_count" { type = number }

variable "network_cidr" {
  description = "VPC CIDR block for internal communication and DNS rules"
  type        = string
}

variable "WIREGUARD_CIDR" {
  description = "CIDR block for WireGuard VPN server(s)"
  type        = string
}

variable "subdomain_public" { type = list(string) }
variable "subdomain_internal" { type = list(string) }
variable "mosip_email_id" { type = string }
variable "ssh_private_key" {
  type      = string
  sensitive = true
}
variable "rancher_import_url" { type = string }
variable "k8s_infra_repo_url" { type = string }
variable "k8s_infra_branch" { type = string }

# AWS-specific variables
variable "aws_provider_region" {
  type        = string
  description = "AWS region for resource creation"
}

variable "specific_availability_zones" {
  description = "Specific availability zones to use for VM deployment"
  type        = list(string)
  default     = []
}
variable "k8s_instance_type" {
  type        = string
  description = "Instance type for K8s nodes"
}
variable "nginx_instance_type" {
  type        = string
  description = "Instance type for NGINX server"
}
variable "ami" {
  type        = string
  description = "AMI ID for AWS instances"
}
variable "ssh_key_name" {
  type        = string
  description = "Name of the SSH key pair in AWS"
}
variable "zone_id" {
  type        = string
  description = "Route53 hosted zone ID"
}
variable "vpc_name" {
  type        = string
  description = "Name of the existing VPC (will be discovered by tag:Name)"
}
variable "nginx_node_root_volume_size" {
  type        = number
  description = "Root volume size for NGINX node"
}
variable "nginx_node_ebs_volume_size" {
  type        = number
  description = "EBS volume size for NGINX node (first volume)"
}

variable "nginx_node_ebs_volume_size_2" {
  type        = number
  description = "EBS volume size for NGINX node (second volume) - set to 0 to disable"
}
variable "k8s_instance_root_volume_size" {
  type        = number
  description = "Root volume size for K8s instances"
}

variable "rke2_version" {
  description = "RKE2 version to install"
  type        = string
  default     = "v1.28.9+rke2r1"
  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+\\+rke2r[0-9]+$", var.rke2_version))
    error_message = "The rke2_version must be in the format: v<major>.<minor>.<patch>+rke2r<build> (e.g., v1.28.9+rke2r1)"
  }
}

variable "enable_rancher_import" {
  type        = bool
  description = "Set to true to enable Rancher import"
}

# Rancher and Keycloak Configuration Variables
variable "enable_rancher_keycloak_integration" {
  description = "Enable Rancher and Keycloak installation"
  type        = bool
  default     = true
}

variable "rancher_hostname" {
  description = "Hostname for Rancher UI (defaults to rancher.<cluster_env_domain>)"
  type        = string
  default     = ""
}

variable "keycloak_hostname" {
  description = "Hostname for Keycloak (defaults to iam.<cluster_env_domain>)"
  type        = string
  default     = ""
}

variable "rancher_bootstrap_password" {
  description = "Bootstrap password for Rancher UI"
  type        = string
  default     = "admin"
  sensitive   = true
}

variable "rancher_ui_version" {
  description = "Rancher Helm chart version"
  type        = string
  default     = "2.8.3"
}

variable "enable_postgresql_setup" {
  description = "Enable PostgreSQL setup (disabled by default for observ-infra)"
  type        = bool
  default     = false
}

variable "postgresql_version" {
  description = "PostgreSQL version to install"
  type        = string
  default     = "15"
}

variable "storage_device" {
  description = "Storage device path for PostgreSQL data"
  type        = string
  default     = "/dev/nvme2n1"
}

variable "mount_point" {
  description = "Mount point for PostgreSQL data directory"
  type        = string
  default     = "/srv/postgres"
}

variable "postgresql_port" {
  description = "PostgreSQL port configuration"
  type        = string
  default     = "5433"
}

variable "mosip_infra_repo_url" {
  description = "URL of the MOSIP infrastructure repository"
  type        = string
  default     = "https://github.com/mosip/infra.git"
}

variable "mosip_infra_branch" {
  description = "Branch of the MOSIP infrastructure repository"
  type        = string
  default     = "develop"
}
