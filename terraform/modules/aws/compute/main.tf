terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.48.0"
    }
  }
}

# ── nginx instance ─────────────────────────────────────────────────────────
# No ebs_block_device here (decision 3 — EBS volumes are #276's job, attached
# post-creation via aws_ebs_volume + aws_volume_attachment, not owned by this
# instance resource). No iam_instance_profile either (decision 4 — certbot's
# IAM role/profile moves to #278/nginx, attached post-creation via
# aws_iam_instance_profile_association once this instance exists).
resource "aws_instance" "nginx" {
  ami                         = var.ami
  instance_type               = var.nginx_instance_type
  associate_public_ip_address = true
  key_name                    = var.ssh_key_name
  vpc_security_group_ids      = [var.nginx_sg_id]
  subnet_id                   = var.public_subnet_ids[0]

  # Sets TOKEN/INTERNAL_IP in /etc/environment for downstream Ansible use.
  # The original EBS-mount-to-/srv/nfs block is intentionally dropped here —
  # #276 (storage) attaches the volume after this instance exists, so there's
  # nothing to mount at boot time anymore; #281 (nfs) mounts it post-attachment,
  # mirroring how postgresql/activemq already handle their own volumes.
  user_data = <<-EOF
    #!/bin/bash
    LOG_FILE="/tmp/ec2-userdata.log"
    ENV_FILE_PATH="/etc/environment"
    exec > >(tee -a "$LOG_FILE") 2>&1
    set -e
    set -o errexit
    set -o nounset
    set -o errtrace
    set -o pipefail

    export TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
    echo "export TOKEN=$TOKEN" | sudo tee -a $ENV_FILE_PATH
    echo "export INTERNAL_IP=\"$(curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/local-ipv4)\"" | sudo tee -a $ENV_FILE_PATH
  EOF

  root_block_device {
    volume_size           = var.nginx_node_root_volume_size
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = false
    tags = {
      Name      = local.nginx_tag_name
      Cluster   = var.cluster_name
      Component = var.cluster_name
    }
  }

  tags = {
    Name      = local.nginx_tag_name
    Cluster   = var.cluster_name
    Component = var.cluster_name
    Role      = "nginx"
  }
}

resource "aws_ec2_instance_state" "nginx_ready" {
  instance_id = aws_instance.nginx.id
  state       = "running"

  timeouts {
    create = "10m"
    update = "10m"
  }
}

# ── k8s cluster instances ────────────────────────────────────────────────────
# for_each keyed by node name (not count) — verified safe for independent
# add/remove: bumping/dropping a node count only touches that node's key,
# every other node is untouched (no index-shift recreation).
resource "aws_instance" "k8s_cluster" {
  for_each = merge(
    { for idx in range(var.k8s_control_plane_node_count) : "CONTROL-PLANE-NODE-${idx + 1}" => { index = idx, role = "control-plane" } },
    { for idx in range(var.k8s_etcd_node_count) : "ETCD-NODE-${idx + 1}" => { index = idx, role = "etcd" } },
    { for idx in range(var.k8s_worker_node_count) : "WORKER-NODE-${idx + 1}" => { index = idx, role = "worker" } }
  )

  ami                         = var.ami
  instance_type               = var.k8s_instance_type
  associate_public_ip_address = false
  key_name                    = var.ssh_key_name
  subnet_id                   = var.private_subnet_ids[each.value.index % length(var.private_subnet_ids)]

  user_data = templatefile("${path.module}/rke-user-data.sh.tpl", {
    index          = each.value.index
    role           = each.key
    cluster_domain = var.cluster_name
  })

  vpc_security_group_ids = [
    each.value.role == "control-plane" ? var.k8s_control_plane_sg_id :
    each.value.role == "etcd" ? var.k8s_etcd_sg_id : var.k8s_worker_sg_id
  ]

  root_block_device {
    volume_size           = var.k8s_instance_root_volume_size
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = false
    tags = {
      Name      = "${var.cluster_name}-${each.key}"
      Cluster   = var.cluster_name
      Component = var.cluster_name
    }
  }

  tags = {
    Name      = "${var.cluster_name}-${each.key}"
    Cluster   = var.cluster_name
    Component = var.cluster_name
    Role      = each.value.role
    # Primary designates the one control-plane node RKE2 bootstraps from —
    # same "NODE-1 is primary" convention already used in rke-user-data.sh.tpl's
    # IS_PRIMARY_CONTROL_PLANE logic, now also expressed as a tag so other
    # Terraform roots / Ansible can discover it via data source instead of
    # depending on map iteration order.
    Primary = (each.value.role == "control-plane" && each.key == "CONTROL-PLANE-NODE-1") ? "true" : "false"
  }

  lifecycle {
    # Create new instances before destroying old ones during updates
    create_before_destroy = true
    # Ignore changes to user_data after initial creation (prevents recreation on node scaling)
    ignore_changes = [user_data]
  }
}

resource "aws_ec2_instance_state" "k8s_ready" {
  for_each    = aws_instance.k8s_cluster
  instance_id = each.value.id
  state       = "running"

  timeouts {
    create = "10m"
    update = "10m"
  }
}
