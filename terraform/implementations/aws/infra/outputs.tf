# AWS Implementation Outputs
output "cluster_info" {
  description = "Information about the deployed cluster"
  value       = module.mosip_infra.cluster_info
}

output "k8s_cluster_public_ips" {
  description = "Public IP addresses of K8s cluster nodes"
  value       = module.mosip_infra.k8s_cluster_public_ips
}

output "k8s_cluster_private_ips" {
  description = "Private IP addresses of K8s cluster nodes"
  value       = module.mosip_infra.k8s_cluster_private_ips
}

output "nginx_public_ip" {
  description = "Public IP address of NGINX instance"
  value       = module.mosip_infra.nginx_public_ip
}

output "nginx_private_ip" {
  description = "Private IP address of NGINX instance"
  value       = module.mosip_infra.nginx_private_ip
}

output "control_plane_node_1" {
  description = "First control plane node information"
  value       = module.mosip_infra.control_plane_node_1
}

output "k8s_token" {
  description = "Kubernetes cluster token"
  value       = module.mosip_infra.k8s_token
  sensitive   = true
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.mosip_infra.vpc_id
}

# RKE2 Deployment Information
output "rke2_deployment_info" {
  description = "RKE2 deployment information including Cloud-Init data and instructions"
  value       = module.mosip_infra.rke2_deployment_info
}

# Quick access to deployment method and kubeconfig location
output "deployment_summary" {
  description = "Summary of deployment method and file locations"
  value = {
    deployment_method = try(module.mosip_infra.rke2_deployment_info.deployment_method, "Unknown")
    kubeconfig_location = try(module.mosip_infra.rke2_deployment_info.kubeconfig_files_location, "Unknown")
    control_plane_nodes = try(module.mosip_infra.rke2_deployment_info.control_plane_nodes, {})
    kubectl_usage_example = try(module.mosip_infra.rke2_deployment_info.kubectl_usage, "Run terraform apply to see instructions")
  }
}
