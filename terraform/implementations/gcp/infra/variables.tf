# GCP Implementation Variables (placeholder)
variable "cluster_name" { type = string }
variable "cluster_env_domain" { type = string }
variable "k8s_control_plane_node_count" { type = number }
variable "k8s_etcd_node_count" { type = number }
variable "k8s_worker_node_count" { type = number }
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

# GCP-specific variables
variable "gcp_project" {
  type    = string
  default = "your-gcp-project"
}
variable "gcp_region" {
  type    = string
  default = "us-central1"
}

# ActiveMQ Configuration Variables
variable "enable_activemq_setup" {
  description = "Enable ActiveMQ EBS volume setup on the NGINX node"
  type        = bool
  default     = false
}

variable "nginx_node_ebs_volume_size_3" {
  description = "EBS volume size (GB) for ActiveMQ data on the NGINX node — set to 0 to disable"
  type        = number
  default     = 0
}

variable "activemq_storage_device" {
  description = "Block device path of the 3rd EBS volume for ActiveMQ"
  type        = string
  default     = "/dev/nvme3n1"
}

variable "activemq_mount_point" {
  description = "Mount point for ActiveMQ persistent storage"
  type        = string
  default     = "/srv/activemq"
}
