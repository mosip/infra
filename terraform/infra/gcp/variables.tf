# GCP-specific variables
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

# GCP-specific variables
variable "gcp_project_id" { 
  type = string
  description = "GCP project ID"
}
variable "gcp_provider_region" { 
  type = string
  description = "GCP region for deployment"
}
variable "k8s_instance_type" {
  type = string
  description = "GCP machine type for Kubernetes nodes"
}
variable "nginx_instance_type" { 
  type = string
  description = "GCP machine type for NGINX instances"
}
variable "gcp_image" { 
  type = string
  description = "GCP VM image for instances"
}
variable "ssh_key_name" { 
  type = string
  description = "Name of SSH key for GCP instances"
}
variable "gcp_dns_zone" { 
  type = string
  description = "GCP DNS zone for domain management"
}
variable "vpc_name" { 
  type = string
  description = "Name of the GCP VPC network"
}
variable "nginx_node_root_volume_size" { 
  type = number
  description = "Root disk size for NGINX nodes in GB"
}
variable "nginx_node_additional_volume_size" { 
  type = number
  description = "Additional disk size for NGINX nodes in GB"
}
variable "k8s_instance_root_volume_size" { 
  type = number
  description = "Root disk size for K8s nodes in GB"
}
