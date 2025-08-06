# AWS Observation Implementation Outputs
output "cluster_info" {
  description = "Information about the deployed observation cluster"
  value       = module.mosip_observ_infra.cluster_info
}

output "k8s_cluster_public_ips" {
  description = "Public IP addresses of K8s observation cluster nodes"
  value       = module.mosip_observ_infra.k8s_cluster_public_ips
}

output "k8s_cluster_private_ips" {
  description = "Private IP addresses of K8s observation cluster nodes"
  value       = module.mosip_observ_infra.k8s_cluster_private_ips
}

output "nginx_public_ip" {
  description = "Public IP address of NGINX instance for observation tools"
  value       = module.mosip_observ_infra.nginx_public_ip
}

output "nginx_private_ip" {
  description = "Private IP address of NGINX instance for observation tools"
  value       = module.mosip_observ_infra.nginx_private_ip
}

output "control_plane_node_1" {
  description = "First control plane node information for observation cluster"
  value       = module.mosip_observ_infra.control_plane_node_1
}

output "k8s_token" {
  description = "Kubernetes observation cluster token"
  value       = module.mosip_observ_infra.k8s_token
  sensitive   = true
}

output "vpc_id" {
  description = "VPC ID for observation infrastructure"
  value       = module.mosip_observ_infra.vpc_id
}

# Rancher-Keycloak Integration Outputs
output "rancher_url" {
  description = "URL to access Rancher UI"
  value       = module.mosip_observ_infra.rancher_url
}

output "keycloak_url" {
  description = "URL to access Keycloak"
  value       = module.mosip_observ_infra.keycloak_url
}

output "rancher_bootstrap_password" {
  description = "Bootstrap password for Rancher UI"
  value       = module.mosip_observ_infra.rancher_bootstrap_password
  sensitive   = true
}

output "rancher_keycloak_status" {
  description = "Status of Rancher and Keycloak installation"
  value       = module.mosip_observ_infra.rancher_keycloak_status
}

output "rancher_keycloak_next_steps" {
  description = "Next steps after Rancher and Keycloak installation"
  value       = module.mosip_observ_infra.rancher_keycloak_next_steps
  sensitive   = true
}
