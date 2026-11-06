output "nginx_sg_id" {
  value = aws_security_group.nginx.id
}

output "k8s_control_plane_sg_id" {
  value = aws_security_group.k8s_control_plane.id
}

output "k8s_etcd_sg_id" {
  value = aws_security_group.k8s_etcd.id
}

output "k8s_worker_sg_id" {
  value = aws_security_group.k8s_worker.id
}
