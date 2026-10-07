output "nginx_public_ip" {
  value = module.compute.nginx_public_ip
}

output "nginx_private_ip" {
  value = module.compute.nginx_private_ip
}

output "nginx_instance_id" {
  value = module.compute.nginx_instance_id
}

output "k8s_node_ips" {
  value = module.compute.k8s_node_ips
}

output "k8s_node_ips_by_role" {
  value = module.compute.k8s_node_ips_by_role
}

output "k8s_primary_control_plane_ip" {
  value = module.compute.k8s_primary_control_plane_ip
}
