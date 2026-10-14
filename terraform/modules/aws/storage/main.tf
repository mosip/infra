terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.48.0"
    }
  }
}

# Volumes attach after launch at /dev/sdf..sdh: Ubuntu AMIs reserve /dev/sdb
# and /dev/sdc (ephemeral0/1), so attaching there fails with "Attachment point
# ... is already in use". On Nitro instances the guest sees /dev/nvmeNn1 in
# attach order, so Ansible addresses each disk by its volume ID instead
# (/dev/disk/by-id/nvme-Amazon_Elastic_Block_Store_vol..., set by
# ansible/inventory/generate.py from this component's outputs).

# ── volume 1 — /dev/sdf, always created (NFS) ────────────────────────────────
resource "aws_ebs_volume" "nfs" {
  availability_zone = var.availability_zone
  size              = var.nginx_node_ebs_volume_size
  type              = "gp3"
  encrypted         = false

  tags = {
    Name      = "${var.nginx_tag_name}-vol1"
    Cluster   = var.cluster_name
    Component = var.cluster_name
    Purpose   = "nfs"
  }
}

resource "aws_volume_attachment" "nfs" {
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.nfs.id
  instance_id = var.nginx_instance_id
}

# ── volume 2 — /dev/sdg, conditional (PostgreSQL) ────────────────────────────
resource "aws_ebs_volume" "postgresql" {
  count             = var.nginx_node_ebs_volume_size_2 > 0 ? 1 : 0
  availability_zone = var.availability_zone
  size              = var.nginx_node_ebs_volume_size_2
  type              = "gp3"
  encrypted         = false

  tags = {
    Name      = "${var.nginx_tag_name}-vol2"
    Cluster   = var.cluster_name
    Component = var.cluster_name
    Purpose   = "postgresql"
  }
}

resource "aws_volume_attachment" "postgresql" {
  count       = var.nginx_node_ebs_volume_size_2 > 0 ? 1 : 0
  device_name = "/dev/sdg"
  volume_id   = aws_ebs_volume.postgresql[0].id
  instance_id = var.nginx_instance_id
}

# ── volume 3 — /dev/sdh, conditional (ActiveMQ) ──────────────────────────────
resource "aws_ebs_volume" "activemq" {
  count             = var.enable_activemq_setup && var.nginx_node_ebs_volume_size_3 > 0 ? 1 : 0
  availability_zone = var.availability_zone
  size              = var.nginx_node_ebs_volume_size_3
  type              = "gp3"
  encrypted         = false

  tags = {
    Name      = "${var.nginx_tag_name}-vol3"
    Cluster   = var.cluster_name
    Component = var.cluster_name
    Purpose   = "activemq"
  }
}

resource "aws_volume_attachment" "activemq" {
  count       = var.enable_activemq_setup && var.nginx_node_ebs_volume_size_3 > 0 ? 1 : 0
  device_name = "/dev/sdh"
  volume_id   = aws_ebs_volume.activemq[0].id
  instance_id = var.nginx_instance_id
}
