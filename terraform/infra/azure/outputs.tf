# Azure Infrastructure Outputs (placeholder)
output "k8s_cluster_public_ips" {
  description = "Public IP addresses of K8s cluster nodes"
  value       = []
}

output "k8s_cluster_private_ips" {
  description = "Private IP addresses of K8s cluster nodes"
  value       = []
}

output "nginx_public_ip" {
  description = "Public IP address of NGINX instance"
  value       = ""
}

output "nginx_private_ip" {
  description = "Private IP address of NGINX instance"
  value       = ""
}

output "control_plane_node_1" {
  description = "First control plane node information"
  value       = ""
}

output "k8s_token" {
  description = "Kubernetes cluster token"
  value       = ""
  sensitive   = true
}

output "vpc_id" {
  description = "VNet ID"
  value       = ""
}
