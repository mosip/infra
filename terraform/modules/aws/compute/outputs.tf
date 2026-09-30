# Provisioning contract: ansible/inventory/generate.py --from-terraform reads
# nginx_public_ip, nginx_private_ip and k8s_node_ips from these outputs. Any
# other provider's compute module must produce the same names.

output "nginx_public_ip" {
  value = aws_instance.nginx.public_ip
}

output "nginx_private_ip" {
  value = aws_instance.nginx.private_ip
}

output "nginx_instance_id" {
  value = aws_instance.nginx.id
}

output "k8s_node_ips" {
  description = "Map of node name => private IP, e.g. \"CONTROL-PLANE-NODE-1\" => \"10.0.1.10\""
  value       = { for name, instance in aws_instance.k8s_cluster : name => instance.private_ip }
}

output "k8s_node_ips_by_role" {
  description = "Private IPs grouped by role (control-plane/etcd/worker) — the map keyed shape the provisioning contract expects"
  value = {
    control-plane = [for name, instance in aws_instance.k8s_cluster : instance.private_ip if instance.tags["Role"] == "control-plane"]
    etcd          = [for name, instance in aws_instance.k8s_cluster : instance.private_ip if instance.tags["Role"] == "etcd"]
    worker        = [for name, instance in aws_instance.k8s_cluster : instance.private_ip if instance.tags["Role"] == "worker"]
  }
}

output "k8s_primary_control_plane_ip" {
  value = [for name, instance in aws_instance.k8s_cluster : instance.private_ip if instance.tags["Primary"] == "true"][0]
}
