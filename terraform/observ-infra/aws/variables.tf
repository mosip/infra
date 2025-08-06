# AWS-specific variables for observ-infra (same as infra variables)
variable "cluster_name" { type = string }
variable "cluster_env_domain" { type = string }
variable "k8s_control_plane_node_count" { type = number }
variable "k8s_etcd_node_count" { type = number }
variable "k8s_worker_node_count" { type = number }
variable "subdomain_public" { type = list(string) }
variable "subdomain_internal" { type = list(string) }
variable "mosip_email_id" { type = string }
variable "ssh_private_key" { 
  type = string
  sensitive = true 
}
variable "rancher_import_url" { type = string }
variable "k8s_infra_repo_url" { type = string }
variable "k8s_infra_branch" { type = string }

# AWS-specific variables
variable "aws_provider_region" { 
  type = string
  description = "AWS region for resource creation"
}
variable "k8s_instance_type" {
  type = string
  description = "Instance type for K8s nodes"
}
variable "nginx_instance_type" { 
  type = string
  description = "Instance type for NGINX server"
}
variable "ami" { 
  type = string
  description = "AMI ID for AWS instances"
}
variable "ssh_key_name" { 
  type = string
  description = "Name of the SSH key pair in AWS"
}
variable "zone_id" { 
  type = string
  description = "Route53 hosted zone ID"
}
variable "vpc_name" { 
  type = string
  description = "Name of the existing VPC (will be discovered by tag:Name)"
}
variable "nginx_node_root_volume_size" { 
  type = number
  description = "Root volume size for NGINX node"
}
variable "nginx_node_ebs_volume_size" { 
  type = number
  description = "EBS volume size for NGINX node"
}
variable "k8s_instance_root_volume_size" { 
  type = number
  description = "Root volume size for K8s instances"
}
variable "enable_rancher_import" {
  type = bool
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
