# Cloud-agnostic outputs for observation infrastructure
output "cluster_info" {
  description = "Information about the deployed observation cluster"
  value = {
    cloud_provider     = var.cloud_provider
    cluster_name       = var.cluster_name
    cluster_env_domain = var.cluster_env_domain
    purpose           = "observation-tools"
  }
}

# Pass through outputs from the selected cloud module
output "k8s_cluster_public_ips" {
  description = "Public IP addresses of K8s observation cluster nodes"
  value       = var.cloud_provider == "aws" ? (
    length(module.aws_observ_infra) > 0 ? module.aws_observ_infra[0].K8S_CLUSTER_PUBLIC_IPS : {}
  ) : var.cloud_provider == "azure" ? (
    length(module.azure_observ_infra) > 0 ? module.azure_observ_infra[0].k8s_cluster_public_ips : {}
  ) : (
    length(module.gcp_observ_infra) > 0 ? module.gcp_observ_infra[0].k8s_cluster_public_ips : {}
  )
}

output "k8s_cluster_private_ips" {
  description = "Private IP addresses of K8s observation cluster nodes"
  value       = var.cloud_provider == "aws" ? (
    length(module.aws_observ_infra) > 0 ? module.aws_observ_infra[0].K8S_CLUSTER_PRIVATE_IPS : {}
  ) : var.cloud_provider == "azure" ? (
    length(module.azure_observ_infra) > 0 ? module.azure_observ_infra[0].k8s_cluster_private_ips : {}
  ) : (
    length(module.gcp_observ_infra) > 0 ? module.gcp_observ_infra[0].k8s_cluster_private_ips : {}
  )
}

output "nginx_public_ip" {
  description = "Public IP address of NGINX instance for observation tools"
  value       = var.cloud_provider == "aws" ? (
    length(module.aws_observ_infra) > 0 ? module.aws_observ_infra[0].NGINX_PUBLIC_IP : ""
  ) : var.cloud_provider == "azure" ? (
    length(module.azure_observ_infra) > 0 ? module.azure_observ_infra[0].nginx_public_ip : ""
  ) : (
    length(module.gcp_observ_infra) > 0 ? module.gcp_observ_infra[0].nginx_public_ip : ""
  )
}

output "nginx_private_ip" {
  description = "Private IP address of NGINX instance for observation tools"
  value       = var.cloud_provider == "aws" ? (
    length(module.aws_observ_infra) > 0 ? module.aws_observ_infra[0].NGINX_PRIVATE_IP : ""
  ) : var.cloud_provider == "azure" ? (
    length(module.azure_observ_infra) > 0 ? module.azure_observ_infra[0].nginx_private_ip : ""
  ) : (
    length(module.gcp_observ_infra) > 0 ? module.gcp_observ_infra[0].nginx_private_ip : ""
  )
}

output "control_plane_node_1" {
  description = "First control plane node information for observation cluster"
  value       = var.cloud_provider == "aws" ? (
    length(module.aws_observ_infra) > 0 ? module.aws_observ_infra[0].control_plane_node_1 : ""
  ) : var.cloud_provider == "azure" ? (
    length(module.azure_observ_infra) > 0 ? module.azure_observ_infra[0].control_plane_node_1 : ""
  ) : (
    length(module.gcp_observ_infra) > 0 ? module.gcp_observ_infra[0].control_plane_node_1 : ""
  )
}

output "k8s_token" {
  description = "Kubernetes observation cluster token"
  value       = var.cloud_provider == "aws" ? (
    length(module.aws_observ_infra) > 0 ? module.aws_observ_infra[0].k8s_token : ""
  ) : var.cloud_provider == "azure" ? (
    length(module.azure_observ_infra) > 0 ? module.azure_observ_infra[0].k8s_token : ""
  ) : (
    length(module.gcp_observ_infra) > 0 ? module.gcp_observ_infra[0].k8s_token : ""
  )
  sensitive   = true
}

output "vpc_id" {
  description = "VPC/Network ID for observation infrastructure"
  value       = var.cloud_provider == "aws" ? (
    length(module.aws_observ_infra) > 0 ? module.aws_observ_infra[0].vpc_id : ""
  ) : var.cloud_provider == "azure" ? (
    length(module.azure_observ_infra) > 0 ? module.azure_observ_infra[0].vpc_id : ""
  ) : (
    length(module.gcp_observ_infra) > 0 ? module.gcp_observ_infra[0].vpc_id : ""
  )
}

# Outputs needed for Rancher-Keycloak integration
output "cluster_ready" {
  description = "Indicator that the cluster is ready for application installation"
  value       = var.cloud_provider == "aws" ? (
    length(module.aws_observ_infra) > 0 ? "cluster-ready-${timestamp()}" : "not-ready"
  ) : var.cloud_provider == "azure" ? (
    length(module.azure_observ_infra) > 0 ? "cluster-ready-${timestamp()}" : "not-ready"
  ) : (
    length(module.gcp_observ_infra) > 0 ? "cluster-ready-${timestamp()}" : "not-ready"
  )
}

output "kubeconfig_path" {
  description = "Path to the kubeconfig file for cluster access"
  value       = var.cloud_provider == "aws" ? (
    length(module.aws_observ_infra) > 0 ? module.aws_observ_infra[0].kubeconfig_path : ""
  ) : var.cloud_provider == "azure" ? (
    length(module.azure_observ_infra) > 0 ? module.azure_observ_infra[0].kubeconfig_path : ""
  ) : (
    length(module.gcp_observ_infra) > 0 ? module.gcp_observ_infra[0].kubeconfig_path : ""
  )
}

# Rancher and Keycloak Integration Outputs
output "rancher_url" {
  description = "URL for accessing Rancher UI"
  value       = var.cloud_provider == "aws" ? (
    length(module.aws_observ_infra) > 0 ? module.aws_observ_infra[0].rancher_url : "Not available"
  ) : var.cloud_provider == "azure" ? (
    length(module.azure_observ_infra) > 0 ? module.azure_observ_infra[0].rancher_url : "Not available"
  ) : (
    length(module.gcp_observ_infra) > 0 ? module.gcp_observ_infra[0].rancher_url : "Not available"
  )
}

output "keycloak_url" {
  description = "URL for accessing Keycloak"
  value       = var.cloud_provider == "aws" ? (
    length(module.aws_observ_infra) > 0 ? module.aws_observ_infra[0].keycloak_url : "Not available"
  ) : var.cloud_provider == "azure" ? (
    length(module.azure_observ_infra) > 0 ? module.azure_observ_infra[0].keycloak_url : "Not available"
  ) : (
    length(module.gcp_observ_infra) > 0 ? module.gcp_observ_infra[0].keycloak_url : "Not available"
  )
}

output "rancher_bootstrap_password" {
  description = "Bootstrap password for Rancher UI"
  value       = var.cloud_provider == "aws" ? (
    length(module.aws_observ_infra) > 0 ? module.aws_observ_infra[0].rancher_bootstrap_password : "N/A"
  ) : var.cloud_provider == "azure" ? (
    length(module.azure_observ_infra) > 0 ? module.azure_observ_infra[0].rancher_bootstrap_password : "N/A"
  ) : (
    length(module.gcp_observ_infra) > 0 ? module.gcp_observ_infra[0].rancher_bootstrap_password : "N/A"
  )
  sensitive = true
}

output "rancher_keycloak_status" {
  description = "Status of Rancher and Keycloak installation"
  value       = var.enable_rancher_keycloak_integration ? (
    var.cloud_provider == "aws" ? (
      length(module.aws_observ_infra) > 0 ? module.aws_observ_infra[0].rancher_keycloak_status : "Not available"
    ) : var.cloud_provider == "azure" ? (
      length(module.azure_observ_infra) > 0 ? module.azure_observ_infra[0].rancher_keycloak_status : "Not available"
    ) : (
      length(module.gcp_observ_infra) > 0 ? module.gcp_observ_infra[0].rancher_keycloak_status : "Not available"
    )
  ) : "Rancher-Keycloak integration disabled"
}

output "rancher_keycloak_next_steps" {
  description = "Next steps after Rancher and Keycloak installation"
  value       = var.enable_rancher_keycloak_integration ? (
    var.cloud_provider == "aws" ? (
      length(module.aws_observ_infra) > 0 ? module.aws_observ_infra[0].rancher_keycloak_next_steps : ["Not available"]
    ) : var.cloud_provider == "azure" ? (
      length(module.azure_observ_infra) > 0 ? module.azure_observ_infra[0].rancher_keycloak_next_steps : ["Not available"]
    ) : (
      length(module.gcp_observ_infra) > 0 ? module.gcp_observ_infra[0].rancher_keycloak_next_steps : ["Not available"]
    )
  ) : ["Rancher-Keycloak integration is disabled. Set enable_rancher_keycloak_integration=true to enable."]
}
