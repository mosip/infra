# Pass through outputs from the AWS main module
output "K8S_CLUSTER_PUBLIC_IPS" {
  description = "Public IPs of the K8s cluster nodes"
  value       = module.aws_observation_infrastructure.K8S_CLUSTER_PUBLIC_IPS
}

output "K8S_CLUSTER_PRIVATE_IPS" {
  description = "Private IPs of the K8s cluster nodes"
  value       = module.aws_observation_infrastructure.K8S_CLUSTER_PRIVATE_IPS
}

output "NGINX_PUBLIC_IP" {
  description = "Public IP of the NGINX load balancer"
  value       = module.aws_observation_infrastructure.NGINX_PUBLIC_IP
}

output "NGINX_PRIVATE_IP" {
  description = "Private IP of the NGINX load balancer"
  value       = module.aws_observation_infrastructure.NGINX_PRIVATE_IP
}

output "CONTROL_PLANE_NODE_1" {
  description = "First control plane node information"
  value       = module.aws_observation_infrastructure.CONTROL_PLANE_NODE_1
}

output "K8S_TOKEN" {
  description = "K8s cluster token"
  value       = module.aws_observation_infrastructure.K8S_TOKEN
  sensitive   = true
}

# Add missing outputs for compatibility
output "control_plane_node_1" {
  description = "First control plane node information (lowercase alias)"
  value       = module.aws_observation_infrastructure.CONTROL_PLANE_NODE_1
}

output "k8s_token" {
  description = "K8s cluster token (lowercase alias)"
  value       = module.aws_observation_infrastructure.K8S_TOKEN
  sensitive   = true
}

output "vpc_id" {
  description = "VPC ID (lowercase alias)"
  value       = module.aws_observation_infrastructure.VPC_ID
}

# Rancher and Keycloak outputs
output "rancher_url" {
  description = "URL for accessing Rancher UI"
  value       = var.enable_rancher_keycloak_integration && length(module.rancher_keycloak_setup) > 0 ? module.rancher_keycloak_setup[0].rancher_url : "Rancher integration disabled"
}

output "keycloak_url" {
  description = "URL for accessing Keycloak"
  value       = var.enable_rancher_keycloak_integration && length(module.rancher_keycloak_setup) > 0 ? module.rancher_keycloak_setup[0].keycloak_url : "Keycloak integration disabled"
}

output "rancher_bootstrap_password" {
  description = "Bootstrap password for Rancher UI"
  value       = var.enable_rancher_keycloak_integration && length(module.rancher_keycloak_setup) > 0 ? module.rancher_keycloak_setup[0].rancher_bootstrap_password : "N/A"
  sensitive   = true
}

output "rancher_keycloak_status" {
  description = "Status of Rancher and Keycloak installation"
  value       = var.enable_rancher_keycloak_integration && length(module.rancher_keycloak_setup) > 0 ? module.rancher_keycloak_setup[0].installation_status : "Rancher and Keycloak integration disabled"
}

output "rancher_keycloak_next_steps" {
  description = "Next steps after Rancher and Keycloak installation"
  value       = var.enable_rancher_keycloak_integration && length(module.rancher_keycloak_setup) > 0 ? module.rancher_keycloak_setup[0].next_steps : ["Rancher and Keycloak integration disabled"]
  sensitive   = true
}

# Infrastructure outputs
output "cluster_ready" {
  description = "Indicates when the cluster is ready"
  value       = true
  depends_on  = [module.aws_observation_infrastructure]
}

output "kubeconfig_path" {
  description = "Path to the kubeconfig file"
  value       = "/home/ubuntu/.kube/config"
}
