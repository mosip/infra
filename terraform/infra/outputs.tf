# Cloud-agnostic outputs
output "cluster_info" {
  description = "Information about the deployed cluster"
  value = {
    cloud_provider     = var.cloud_provider
    cluster_name       = var.cluster_name
    cluster_env_domain = var.cluster_env_domain
  }
}

# Pass through outputs from the selected cloud module
output "k8s_cluster_public_ips" {
  description = "Public IP addresses of K8s cluster nodes"
  value       = var.cloud_provider == "aws" ? (
    length(module.aws_infra) > 0 ? module.aws_infra[0].k8s_cluster_public_ips : {}
  ) : var.cloud_provider == "azure" ? (
    length(module.azure_infra) > 0 ? module.azure_infra[0].k8s_cluster_public_ips : {}
  ) : (
    length(module.gcp_infra) > 0 ? module.gcp_infra[0].k8s_cluster_public_ips : {}
  )
}

output "k8s_cluster_private_ips" {
  description = "Private IP addresses of K8s cluster nodes"
  value       = var.cloud_provider == "aws" ? (
    length(module.aws_infra) > 0 ? module.aws_infra[0].k8s_cluster_private_ips : {}
  ) : var.cloud_provider == "azure" ? (
    length(module.azure_infra) > 0 ? module.azure_infra[0].k8s_cluster_private_ips : {}
  ) : (
    length(module.gcp_infra) > 0 ? module.gcp_infra[0].k8s_cluster_private_ips : {}
  )
}

output "nginx_public_ip" {
  description = "Public IP address of NGINX instance"
  value       = var.cloud_provider == "aws" ? (
    length(module.aws_infra) > 0 ? module.aws_infra[0].nginx_public_ip : ""
  ) : var.cloud_provider == "azure" ? (
    length(module.azure_infra) > 0 ? module.azure_infra[0].nginx_public_ip : ""
  ) : (
    length(module.gcp_infra) > 0 ? module.gcp_infra[0].nginx_public_ip : ""
  )
}

output "nginx_private_ip" {
  description = "Private IP address of NGINX instance"
  value       = var.cloud_provider == "aws" ? (
    length(module.aws_infra) > 0 ? module.aws_infra[0].nginx_private_ip : ""
  ) : var.cloud_provider == "azure" ? (
    length(module.azure_infra) > 0 ? module.azure_infra[0].nginx_private_ip : ""
  ) : (
    length(module.gcp_infra) > 0 ? module.gcp_infra[0].nginx_private_ip : ""
  )
}

output "control_plane_node_1" {
  description = "First control plane node information"
  value       = var.cloud_provider == "aws" ? (
    length(module.aws_infra) > 0 ? module.aws_infra[0].control_plane_node_1 : ""
  ) : var.cloud_provider == "azure" ? (
    length(module.azure_infra) > 0 ? module.azure_infra[0].control_plane_node_1 : ""
  ) : (
    length(module.gcp_infra) > 0 ? module.gcp_infra[0].control_plane_node_1 : ""
  )
}

output "k8s_token" {
  description = "Kubernetes cluster token"
  value       = var.cloud_provider == "aws" ? (
    length(module.aws_infra) > 0 ? module.aws_infra[0].k8s_token : ""
  ) : var.cloud_provider == "azure" ? (
    length(module.azure_infra) > 0 ? module.azure_infra[0].k8s_token : ""
  ) : (
    length(module.gcp_infra) > 0 ? module.gcp_infra[0].k8s_token : ""
  )
  sensitive   = true
}

output "vpc_id" {
  description = "VPC/Network ID"
  value       = var.cloud_provider == "aws" ? (
    length(module.aws_infra) > 0 ? module.aws_infra[0].vpc_id : ""
  ) : var.cloud_provider == "azure" ? (
    length(module.azure_infra) > 0 ? module.azure_infra[0].vpc_id : ""
  ) : (
    length(module.gcp_infra) > 0 ? module.gcp_infra[0].vpc_id : ""
  )
}
