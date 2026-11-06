terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.48.0"
    }
  }
}

# Every rule comes from profiles/<profile>/aws/security.tfvars (ingress_rules per
# group, egress_rules for all groups) plus the optional extra_* additions. This
# module only renders them; it holds no ports of its own. The CIDR placeholders
# "network_cidr" / "wireguard_cidr" are replaced with the values from
# common.tfvars so the VPC CIDR stays in one place.
locals {
  cidr_placeholders = {
    network_cidr   = var.network_cidr
    wireguard_cidr = var.wireguard_cidr
  }

  ingress = {
    for group in ["nginx", "control_plane", "etcd", "worker"] : group => [
      for r in concat(var.ingress_rules[group], lookup(var.extra_ingress_rules, group, [])) :
      merge(r, { cidr_blocks = [for c in r.cidr_blocks : lookup(local.cidr_placeholders, c, c)] })
    ]
  }

  egress = {
    for group in ["nginx", "control_plane", "etcd", "worker"] : group => [
      for r in concat(var.egress_rules, lookup(var.extra_egress_rules, group, [])) :
      merge(r, { cidr_blocks = [for c in r.cidr_blocks : lookup(local.cidr_placeholders, c, c)] })
    ]
  }
}

# ── nginx ──────────────────────────────────────────────────────────────────────
resource "aws_security_group" "nginx" {
  vpc_id      = var.vpc_id
  description = "Rules which allow the outgoing traffic from the instances associated with the security group NGINX_SECURITY_GROUP"

  tags = {
    Name      = "${var.cluster_name}-NGINX_SECURITY_GROUP"
    Cluster   = var.cluster_name
    Component = var.cluster_name
    Role      = "nginx"
  }

  dynamic "ingress" {
    for_each = local.ingress.nginx
    content {
      description      = ingress.value.description
      from_port        = ingress.value.from_port
      to_port          = ingress.value.to_port
      protocol         = ingress.value.protocol
      cidr_blocks      = ingress.value.cidr_blocks
      ipv6_cidr_blocks = ingress.value.ipv6_cidr_blocks
    }
  }

  dynamic "egress" {
    for_each = local.egress.nginx
    content {
      description      = egress.value.description
      from_port        = egress.value.from_port
      to_port          = egress.value.to_port
      protocol         = egress.value.protocol
      cidr_blocks      = egress.value.cidr_blocks
      ipv6_cidr_blocks = egress.value.ipv6_cidr_blocks
    }
  }
}

# ── k8s control plane ──────────────────────────────────────────────────────────
resource "aws_security_group" "k8s_control_plane" {
  vpc_id      = var.vpc_id
  description = "Rules which allow the outgoing traffic from the instances associated with the security group K8S_CONTROL_PLANE_SECURITY_GROUP"

  tags = {
    Name      = "${var.cluster_name}-K8S_CONTROL_PLANE_SECURITY_GROUP"
    Cluster   = var.cluster_name
    Component = var.cluster_name
    Role      = "control-plane"
  }

  dynamic "ingress" {
    for_each = local.ingress.control_plane
    content {
      description      = ingress.value.description
      from_port        = ingress.value.from_port
      to_port          = ingress.value.to_port
      protocol         = ingress.value.protocol
      cidr_blocks      = ingress.value.cidr_blocks
      ipv6_cidr_blocks = ingress.value.ipv6_cidr_blocks
    }
  }

  dynamic "egress" {
    for_each = local.egress.control_plane
    content {
      description      = egress.value.description
      from_port        = egress.value.from_port
      to_port          = egress.value.to_port
      protocol         = egress.value.protocol
      cidr_blocks      = egress.value.cidr_blocks
      ipv6_cidr_blocks = egress.value.ipv6_cidr_blocks
    }
  }
}

# ── k8s etcd ───────────────────────────────────────────────────────────────────
resource "aws_security_group" "k8s_etcd" {
  vpc_id      = var.vpc_id
  description = "Rules which allow the outgoing traffic from the instances associated with the security group K8S_ETCD_SECURITY_GROUP"

  tags = {
    Name      = "${var.cluster_name}-K8S_ETCD_SECURITY_GROUP"
    Cluster   = var.cluster_name
    Component = var.cluster_name
    Role      = "etcd"
  }

  dynamic "ingress" {
    for_each = local.ingress.etcd
    content {
      description      = ingress.value.description
      from_port        = ingress.value.from_port
      to_port          = ingress.value.to_port
      protocol         = ingress.value.protocol
      cidr_blocks      = ingress.value.cidr_blocks
      ipv6_cidr_blocks = ingress.value.ipv6_cidr_blocks
    }
  }

  dynamic "egress" {
    for_each = local.egress.etcd
    content {
      description      = egress.value.description
      from_port        = egress.value.from_port
      to_port          = egress.value.to_port
      protocol         = egress.value.protocol
      cidr_blocks      = egress.value.cidr_blocks
      ipv6_cidr_blocks = egress.value.ipv6_cidr_blocks
    }
  }
}

# ── k8s worker ─────────────────────────────────────────────────────────────────
resource "aws_security_group" "k8s_worker" {
  vpc_id      = var.vpc_id
  description = "Rules which allow the outgoing traffic from the instances associated with the security group K8S_WORKER_SECURITY_GROUP"

  tags = {
    Name      = "${var.cluster_name}-K8S_WORKER_SECURITY_GROUP"
    Cluster   = var.cluster_name
    Component = var.cluster_name
    Role      = "worker"
  }

  dynamic "ingress" {
    for_each = local.ingress.worker
    content {
      description      = ingress.value.description
      from_port        = ingress.value.from_port
      to_port          = ingress.value.to_port
      protocol         = ingress.value.protocol
      cidr_blocks      = ingress.value.cidr_blocks
      ipv6_cidr_blocks = ingress.value.ipv6_cidr_blocks
    }
  }

  dynamic "egress" {
    for_each = local.egress.worker
    content {
      description      = egress.value.description
      from_port        = egress.value.from_port
      to_port          = egress.value.to_port
      protocol         = egress.value.protocol
      cidr_blocks      = egress.value.cidr_blocks
      ipv6_cidr_blocks = egress.value.ipv6_cidr_blocks
    }
  }
}
