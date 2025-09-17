# Cloud-agnostic outputs for observation infrastructure
output "cluster_info" {
  description = "Information about the deployed observation cluster"
  value = {
    cloud_provider     = var.cloud_provider
    cluster_name       = var.cluster_name
    cluster_env_domain = var.cluster_env_domain
    purpose            = "observation-tools"
  }
}

# Pass through outputs from the selected cloud module
output "k8s_cluster_ips" {
  description = "IP addresses of K8s observation cluster nodes (private IPs for security)"
  value = var.cloud_provider == "aws" ? (
    length(module.aws_observ_infra) > 0 ? module.aws_observ_infra[0].K8S_CLUSTER_IPS : {}
    ) : var.cloud_provider == "azure" ? (
    length(module.azure_observ_infra) > 0 ? module.azure_observ_infra[0].k8s_cluster_ips : {}
    ) : (
    length(module.gcp_observ_infra) > 0 ? module.gcp_observ_infra[0].k8s_cluster_ips : {}
  )
}

output "k8s_cluster_private_ips" {
  description = "Private IP addresses of K8s observation cluster nodes"
  value = var.cloud_provider == "aws" ? (
    length(module.aws_observ_infra) > 0 ? module.aws_observ_infra[0].K8S_CLUSTER_PRIVATE_IPS : {}
    ) : var.cloud_provider == "azure" ? (
    length(module.azure_observ_infra) > 0 ? module.azure_observ_infra[0].k8s_cluster_private_ips : {}
    ) : (
    length(module.gcp_observ_infra) > 0 ? module.gcp_observ_infra[0].k8s_cluster_private_ips : {}
  )
}

output "nginx_public_ip" {
  description = "Public IP address of NGINX instance for observation tools"
  value = var.cloud_provider == "aws" ? (
    length(module.aws_observ_infra) > 0 ? module.aws_observ_infra[0].NGINX_PUBLIC_IP : ""
    ) : var.cloud_provider == "azure" ? (
    length(module.azure_observ_infra) > 0 ? module.azure_observ_infra[0].nginx_public_ip : ""
    ) : (
    length(module.gcp_observ_infra) > 0 ? module.gcp_observ_infra[0].nginx_public_ip : ""
  )
}

output "nginx_private_ip" {
  description = "Private IP address of NGINX instance for observation tools"
  value = var.cloud_provider == "aws" ? (
    length(module.aws_observ_infra) > 0 ? module.aws_observ_infra[0].NGINX_PRIVATE_IP : ""
    ) : var.cloud_provider == "azure" ? (
    length(module.azure_observ_infra) > 0 ? module.azure_observ_infra[0].nginx_private_ip : ""
    ) : (
    length(module.gcp_observ_infra) > 0 ? module.gcp_observ_infra[0].nginx_private_ip : ""
  )
}

output "control_plane_node_1" {
  description = "First control plane node information for observation cluster - DISABLED (only AWS resource creation enabled)"
  value = "DISABLED - control_plane_node_1 not available with AWS resource creation only"
}

# Token generation handled by ansible - no terraform output needed
# k8s_token removed as ansible manages token internally

output "vpc_id" {
  description = "VPC/Network ID for observation infrastructure"
  value = var.cloud_provider == "aws" ? (
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
  value = var.cloud_provider == "aws" ? (
    length(module.aws_observ_infra) > 0 ? "cluster-ready-${timestamp()}" : "not-ready"
    ) : var.cloud_provider == "azure" ? (
    length(module.azure_observ_infra) > 0 ? "cluster-ready-${timestamp()}" : "not-ready"
    ) : (
    length(module.gcp_observ_infra) > 0 ? "cluster-ready-${timestamp()}" : "not-ready"
  )
}

output "kubeconfig_path" {
  description = "Path to the kubeconfig file for cluster access"
  value = var.cloud_provider == "aws" ? (
    length(module.aws_observ_infra) > 0 ? module.aws_observ_infra[0].kubeconfig_path : ""
    ) : var.cloud_provider == "azure" ? (
    length(module.azure_observ_infra) > 0 ? module.azure_observ_infra[0].kubeconfig_path : ""
    ) : (
    length(module.gcp_observ_infra) > 0 ? module.gcp_observ_infra[0].kubeconfig_path : ""
  )
}

# Rancher and Keycloak Integration Outputs - DISABLED (only AWS resource creation enabled)
output "rancher_url" {
  description = "URL for accessing Rancher UI - DISABLED"
  value = "DISABLED - Rancher integration not available with AWS resource creation only"
}

output "keycloak_url" {
  description = "URL for accessing Keycloak - DISABLED"
  value = "DISABLED - Keycloak integration not available with AWS resource creation only"
}

output "rancher_bootstrap_password" {
  description = "Bootstrap password for Rancher UI - DISABLED"
  value = "DISABLED - Rancher integration not available with AWS resource creation only"
  sensitive = true
}

output "rancher_keycloak_status" {
  description = "Status of Rancher and Keycloak installation"
  value = var.enable_rancher_keycloak_integration ? (
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
  value = var.enable_rancher_keycloak_integration ? (
    var.cloud_provider == "aws" ? (
      length(module.aws_observ_infra) > 0 ? module.aws_observ_infra[0].rancher_keycloak_next_steps : ["Not available"]
      ) : var.cloud_provider == "azure" ? (
      length(module.azure_observ_infra) > 0 ? module.azure_observ_infra[0].rancher_keycloak_next_steps : ["Not available"]
      ) : (
      length(module.gcp_observ_infra) > 0 ? module.gcp_observ_infra[0].rancher_keycloak_next_steps : ["Not available"]
    )
  ) : ["Rancher-Keycloak integration is disabled. Set enable_rancher_keycloak_integration=true to enable."]
}
