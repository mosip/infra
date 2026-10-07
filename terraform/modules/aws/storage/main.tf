terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.48.0"
    }
  }
}

# ── volume 1 — /dev/sdb, always created (NFS) ────────────────────────────────
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
  device_name = "/dev/sdb"
  volume_id   = aws_ebs_volume.nfs.id
  instance_id = var.nginx_instance_id
}

# ── volume 2 — /dev/sdc, conditional (PostgreSQL) ────────────────────────────
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
  device_name = "/dev/sdc"
  volume_id   = aws_ebs_volume.postgresql[0].id
  instance_id = var.nginx_instance_id
}

# ── volume 3 — /dev/sdd, conditional (ActiveMQ) ──────────────────────────────
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
  device_name = "/dev/sdd"
  volume_id   = aws_ebs_volume.activemq[0].id
  instance_id = var.nginx_instance_id
}
