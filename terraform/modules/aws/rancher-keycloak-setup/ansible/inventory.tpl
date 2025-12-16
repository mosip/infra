[control_plane]
${control_plane_ip} ansible_user=ubuntu ansible_ssh_private_key_file=${ssh_key_file}

[control_plane:vars]
ansible_ssh_common_args='-o StrictHostKeyChecking=no'
