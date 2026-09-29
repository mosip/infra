# Verifies the decoupled `compute` module produces the same nginx + K8s node
# instance configuration as the pre-#273 monolith's
# `aws-resource-creation-main.tf`, with the intentional differences
# (dropped ebs_block_device/iam_instance_profile — moved to #276/#278; added
# Role/Primary tags — needed for tag-based discovery) called out explicitly.

mock_provider "aws" {}

variables {
  cluster_name                  = "testcluster"
  ami                           = "ami-0ad21ae1d0696ad58"
  ssh_key_name                  = "test-ssh-key"
  nginx_instance_type           = "t3a.large"
  k8s_instance_type             = "t3a.2xlarge"
  nginx_node_root_volume_size   = 24
  k8s_instance_root_volume_size = 64
  public_subnet_ids             = ["subnet-public1", "subnet-public2"]
  private_subnet_ids            = ["subnet-private1", "subnet-private2", "subnet-private3"]
  nginx_sg_id                   = "sg-nginx"
  k8s_control_plane_sg_id       = "sg-control-plane"
  k8s_etcd_sg_id                = "sg-etcd"
  k8s_worker_sg_id              = "sg-worker"
  # Matches the real mosip profile's node counts (3 control-plane, 3 etcd, 1 worker)
  k8s_control_plane_node_count = 3
  k8s_etcd_node_count          = 3
  k8s_worker_node_count        = 1
}

run "nginx_instance_matches_legacy_config" {
  command = plan

  assert {
    condition     = aws_instance.nginx.ami == "ami-0ad21ae1d0696ad58"
    error_message = "nginx instance AMI mismatch"
  }
  assert {
    condition     = aws_instance.nginx.instance_type == "t3a.large"
    error_message = "nginx instance_type mismatch"
  }
  assert {
    condition     = aws_instance.nginx.associate_public_ip_address == true
    error_message = "nginx must always get a public IP (legacy: associate_public_ip_address = true, hardcoded)"
  }
  assert {
    condition     = contains(aws_instance.nginx.vpc_security_group_ids, "sg-nginx")
    error_message = "nginx instance not attached to the expected (looked-up) security group"
  }
  assert {
    condition     = aws_instance.nginx.subnet_id == "subnet-public1"
    error_message = "nginx instance must land in the first public subnet (legacy: PUBLIC_SUBNET_IDS[0])"
  }
  assert {
    condition     = aws_instance.nginx.root_block_device[0].volume_size == 24 && aws_instance.nginx.root_block_device[0].volume_type == "gp3"
    error_message = "nginx root_block_device doesn't match legacy (size from var, type gp3)"
  }
  assert {
    condition     = length(aws_instance.nginx.ebs_block_device) == 0
    error_message = "nginx instance must NOT have any ebs_block_device — that's #276/storage's job now, attached post-creation (decision 3)"
  }
  assert {
    condition     = aws_instance.nginx.tags.Name == "testcluster-NGINX-NODE"
    error_message = "nginx Name tag doesn't match legacy's TAG_NAME.NGINX_TAG_NAME convention"
  }
  assert {
    condition     = aws_instance.nginx.tags.Role == "nginx"
    error_message = "nginx instance missing the new Role=nginx tag (intentional #275 addition)"
  }
}

run "k8s_cluster_node_counts_match_input" {
  command = plan

  assert {
    condition     = length([for k, v in aws_instance.k8s_cluster : k if startswith(k, "CONTROL-PLANE-NODE")]) == 3
    error_message = "expected 3 control-plane nodes"
  }
  assert {
    condition     = length([for k, v in aws_instance.k8s_cluster : k if startswith(k, "ETCD-NODE")]) == 3
    error_message = "expected 3 etcd nodes"
  }
  assert {
    condition     = length([for k, v in aws_instance.k8s_cluster : k if startswith(k, "WORKER-NODE")]) == 1
    error_message = "expected 1 worker node"
  }
  assert {
    condition     = length(aws_instance.k8s_cluster) == 7
    error_message = "expected exactly 7 total K8s nodes (3 control-plane + 3 etcd + 1 worker)"
  }
}

run "k8s_nodes_get_correct_security_group_per_role" {
  command = plan

  assert {
    condition     = contains(aws_instance.k8s_cluster["CONTROL-PLANE-NODE-1"].vpc_security_group_ids, "sg-control-plane")
    error_message = "control-plane node not attached to the control-plane security group"
  }
  assert {
    condition     = contains(aws_instance.k8s_cluster["ETCD-NODE-1"].vpc_security_group_ids, "sg-etcd")
    error_message = "etcd node not attached to the etcd security group"
  }
  assert {
    condition     = contains(aws_instance.k8s_cluster["WORKER-NODE-1"].vpc_security_group_ids, "sg-worker")
    error_message = "worker node not attached to the worker security group"
  }
}

run "primary_control_plane_tag_only_on_node_1" {
  command = plan

  assert {
    condition     = aws_instance.k8s_cluster["CONTROL-PLANE-NODE-1"].tags.Primary == "true"
    error_message = "CONTROL-PLANE-NODE-1 must be tagged Primary=true (new #275 convention, replaces legacy's implicit alphabetical-map-order assumption)"
  }
  assert {
    condition     = aws_instance.k8s_cluster["CONTROL-PLANE-NODE-2"].tags.Primary == "false"
    error_message = "CONTROL-PLANE-NODE-2 must be tagged Primary=false — only the first control-plane node is primary"
  }
  assert {
    condition     = aws_instance.k8s_cluster["ETCD-NODE-1"].tags.Primary == "false"
    error_message = "non-control-plane nodes must never be tagged Primary=true"
  }
  assert {
    condition     = alltrue([for k, v in aws_instance.k8s_cluster : v.tags.Role == "control-plane" if startswith(k, "CONTROL-PLANE-NODE")])
    error_message = "all control-plane-named nodes must carry Role=control-plane"
  }
}

run "k8s_nodes_always_private_no_public_ip" {
  command = plan

  assert {
    condition     = alltrue([for k, v in aws_instance.k8s_cluster : v.associate_public_ip_address == false])
    error_message = "K8s instances must always be private (legacy: associate_public_ip_address = false, hardcoded)"
  }
  assert {
    condition     = alltrue([for k, v in aws_instance.k8s_cluster : v.root_block_device[0].volume_size == 64 && v.root_block_device[0].volume_type == "gp3"])
    error_message = "K8s node root_block_device doesn't match legacy (size from var, type gp3)"
  }
}

run "subnet_round_robin_matches_legacy_modulo_logic" {
  command = plan

  # Legacy: subnet_id = PRIVATE_SUBNET_IDS[each.value % length(PRIVATE_SUBNET_IDS)]
  # where each.value was the flat numeric index across the merged map.
  # 3 private subnets available; index 0 -> subnet-private1.
  assert {
    condition     = aws_instance.k8s_cluster["CONTROL-PLANE-NODE-1"].subnet_id == "subnet-private1"
    error_message = "first control-plane node should round-robin to the first private subnet (index 0 % 3 == 0)"
  }
}

run "observ_infra_shape_single_node_no_etcd_no_worker" {
  command = plan

  # Same module, same code path — only the input counts differ, matching
  # the observ profile's compute.tfvars (control-plane=1, etcd=0, worker=0).
  # Proves this is genuinely "one module, two parents", not two code paths.
  variables {
    k8s_control_plane_node_count = 1
    k8s_etcd_node_count          = 0
    k8s_worker_node_count        = 0
  }

  assert {
    condition     = length(aws_instance.k8s_cluster) == 1
    error_message = "observ profile shape should produce exactly 1 K8s node total"
  }
  assert {
    condition     = aws_instance.k8s_cluster["CONTROL-PLANE-NODE-1"].tags.Primary == "true"
    error_message = "the sole control-plane node must still be tagged Primary=true even with no other nodes"
  }
  assert {
    condition     = contains(aws_instance.k8s_cluster["CONTROL-PLANE-NODE-1"].vpc_security_group_ids, "sg-control-plane")
    error_message = "the sole node must still get the control-plane security group"
  }
}
