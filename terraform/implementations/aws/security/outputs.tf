output "nginx_sg_id" {
  value = module.security.nginx_sg_id
}

output "k8s_control_plane_sg_id" {
  value = module.security.k8s_control_plane_sg_id
}

output "k8s_etcd_sg_id" {
  value = module.security.k8s_etcd_sg_id
}

output "k8s_worker_sg_id" {
  value = module.security.k8s_worker_sg_id
}
