---
all:
  vars:
    cluster_name: "${cluster_name}"
    cluster_env_domain: "${cluster_env_domain}"
    k8s_infra_repo_url: "${k8s_infra_repo_url}"
    k8s_infra_branch: "${k8s_infra_branch}"
    install_rke2_version: "${install_rke2_version}"
    enable_rancher_import: ${enable_rancher_import}
    rancher_import_url: ${rancher_import_url}
    ansible_user: ubuntu
    ansible_ssh_private_key_file: ./ssh_key
    ansible_ssh_common_args: '-o StrictHostKeyChecking=no'
    
  children:
    control_plane:
      hosts:
%{ for idx, ip in control_plane_ips ~}
        ${cluster_name}-CONTROL-PLANE-NODE-${idx + 1}:
          ansible_host: ${ip}
          node_role: control_plane
          is_primary: ${idx == 0 ? "true" : "false"}
          node_index: ${idx}
%{ endfor ~}
    
%{ if length(etcd_ips) > 0 ~}
    etcd:
      hosts:
%{ for idx, ip in etcd_ips ~}
        ${cluster_name}-ETCD-NODE-${idx + 1}:
          ansible_host: ${ip}
          node_role: etcd
%{ endfor ~}
%{ endif ~}
    
%{ if length(worker_ips) > 0 ~}
    workers:
      hosts:
%{ for idx, ip in worker_ips ~}
        ${cluster_name}-WORKER-NODE-${idx + 1}:
          ansible_host: ${ip}
          node_role: worker
%{ endfor ~}
%{ endif ~}

    rke2_cluster:
      children:
        control_plane:
%{ if length(etcd_ips) > 0 ~}
        etcd:
%{ endif ~}
%{ if length(worker_ips) > 0 ~}
        workers:
%{ endif ~}
