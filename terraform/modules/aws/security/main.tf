terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.48.0"
    }
  }
}

# Shared egress rules — identical across all 4 groups, kept as one local so it's
# defined once instead of repeated 4 times; ingress stays fully separate per
# resource below since that's what actually differs and what future edits target.
locals {
  common_egress_rules = [
    {
      description      = "Allow HTTP outbound to anywhere (for package downloads)"
      from_port        = 80
      to_port          = 80
      protocol         = "tcp"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = []
    },
    {
      description      = "Allow HTTPS outbound to anywhere"
      from_port        = 443
      to_port          = 443
      protocol         = "tcp"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = []
    },
    {
      description      = "Allow WireGuard VPN outbound to VPN CIDR"
      from_port        = 51820
      to_port          = 51820
      protocol         = "udp"
      cidr_blocks      = [var.wireguard_cidr]
      ipv6_cidr_blocks = []
    },
    {
      description      = "Allow DNS TCP outbound to anywhere (for public DNS resolution)"
      from_port        = 53
      to_port          = 53
      protocol         = "tcp"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = []
    },
    {
      description      = "Allow DNS UDP outbound to anywhere (for public DNS resolution)"
      from_port        = 53
      to_port          = 53
      protocol         = "udp"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = []
    },
    {
      description      = "Allow all required internal communication (VPC + Pod Networks)"
      from_port        = 0
      to_port          = 0
      protocol         = "-1"
      cidr_blocks      = [var.network_cidr, "10.42.0.0/16", "10.43.0.0/16"]
      ipv6_cidr_blocks = []
    },
  ]
}

# ── nginx ────────────────────────────────────────────────────────────────────
resource "aws_security_group" "nginx" {
  vpc_id      = var.vpc_id
  description = "Rules which allow the outgoing traffic from the instances associated with the security group NGINX_SECURITY_GROUP"

  tags = {
    Name      = "${var.cluster_name}-NGINX_SECURITY_GROUP"
    Cluster   = var.cluster_name
    Component = var.cluster_name
    Role      = "nginx"
  }

  ingress {
    description      = "SSH login port (open access)"
    from_port        = 22
    to_port          = 22
    protocol         = "TCP"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = []
  }
  ingress {
    description      = "Allow ICMP (open access)"
    from_port        = -1
    to_port          = -1
    protocol         = "ICMP"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = []
  }
  ingress {
    description      = "HTTP port (public)"
    from_port        = 80
    to_port          = 80
    protocol         = "TCP"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = []
  }
  ingress {
    description      = "HTTPS port (public)"
    from_port        = 443
    to_port          = 443
    protocol         = "TCP"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = []
  }
  ingress {
    description      = "Minio console port (open access)"
    from_port        = 9000
    to_port          = 9000
    protocol         = "TCP"
    cidr_blocks      = [var.network_cidr]
    ipv6_cidr_blocks = []
  }
  ingress {
    description      = "Postgres port (open access)"
    from_port        = 5432
    to_port          = 5432
    protocol         = "TCP"
    cidr_blocks      = [var.network_cidr]
    ipv6_cidr_blocks = []
  }
  ingress {
    description      = "Postgres alternative port (open access)"
    from_port        = 5433
    to_port          = 5433
    protocol         = "TCP"
    cidr_blocks      = [var.network_cidr]
    ipv6_cidr_blocks = []
  }
  ingress {
    description      = "ActiveMQ port (open access)"
    from_port        = 61616
    to_port          = 61616
    protocol         = "TCP"
    cidr_blocks      = [var.network_cidr]
    ipv6_cidr_blocks = []
  }
  ingress {
    description      = "NFS server port tcp (open access)"
    from_port        = 2049
    to_port          = 2049
    protocol         = "TCP"
    cidr_blocks      = [var.network_cidr]
    ipv6_cidr_blocks = []
  }
  ingress {
    description      = "NFS server port udp (open access)"
    from_port        = 2049
    to_port          = 2049
    protocol         = "UDP"
    cidr_blocks      = [var.network_cidr]
    ipv6_cidr_blocks = []
  }

  # Per-environment additions (security.tfvars: extra_ingress_rules.nginx).
  dynamic "ingress" {
    for_each = lookup(var.extra_ingress_rules, "nginx", [])
    content {
      description      = ingress.value.description
      from_port        = ingress.value.from_port
      to_port          = ingress.value.to_port
      protocol         = ingress.value.protocol
      cidr_blocks      = ingress.value.cidr_blocks
      ipv6_cidr_blocks = ingress.value.ipv6_cidr_blocks
    }
  }

  # Built-in outbound rules + per-environment additions
  # (security.tfvars: extra_egress_rules.nginx).
  dynamic "egress" {
    for_each = concat(local.common_egress_rules, lookup(var.extra_egress_rules, "nginx", []))
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

# ── k8s control plane ──────────────────────────────────────────────────────
resource "aws_security_group" "k8s_control_plane" {
  vpc_id      = var.vpc_id
  description = "Rules which allow the outgoing traffic from the instances associated with the security group K8S_CONTROL_PLANE_SECURITY_GROUP"

  tags = {
    Name      = "${var.cluster_name}-K8S_CONTROL_PLANE_SECURITY_GROUP"
    Cluster   = var.cluster_name
    Component = var.cluster_name
    Role      = "control-plane"
  }

  ingress {
    description      = "SSH login port (open access)"
    from_port        = 22
    to_port          = 22
    protocol         = "TCP"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = []
  }
  ingress {
    description      = "Allow ICMP (open access)"
    from_port        = -1
    to_port          = -1
    protocol         = "ICMP"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = []
  }
  ingress {
    description      = "Kubernetes API (open access)"
    from_port        = 6443
    to_port          = 6443
    protocol         = "TCP"
    cidr_blocks      = [var.network_cidr]
    ipv6_cidr_blocks = []
  }
  ingress {
    description      = "RKE2 supervisor API (open access)"
    from_port        = 9345
    to_port          = 9345
    protocol         = "TCP"
    cidr_blocks      = [var.network_cidr]
    ipv6_cidr_blocks = []
  }
  ingress {
    description      = "Kubelet metrics (open access)"
    from_port        = 10250
    to_port          = 10250
    protocol         = "TCP"
    cidr_blocks      = [var.network_cidr]
    ipv6_cidr_blocks = []
  }
  ingress {
    description      = "ETCD client port (open access)"
    from_port        = 2379
    to_port          = 2379
    protocol         = "TCP"
    cidr_blocks      = [var.network_cidr]
    ipv6_cidr_blocks = []
  }
  ingress {
    description      = "ETCD peer port (open access)"
    from_port        = 2380
    to_port          = 2380
    protocol         = "TCP"
    cidr_blocks      = [var.network_cidr]
    ipv6_cidr_blocks = []
  }
  ingress {
    description      = "ETCD metrics port (open access)"
    from_port        = 2381
    to_port          = 2381
    protocol         = "TCP"
    cidr_blocks      = [var.network_cidr]
    ipv6_cidr_blocks = []
  }
  ingress {
    description      = "NodePort port range (open access)"
    from_port        = 30000
    to_port          = 32767
    protocol         = "TCP"
    cidr_blocks      = [var.network_cidr]
    ipv6_cidr_blocks = []
  }
  ingress {
    description      = "Canal CNI with VXLAN (open access)"
    from_port        = 8472
    to_port          = 8472
    protocol         = "UDP"
    cidr_blocks      = [var.network_cidr]
    ipv6_cidr_blocks = []
  }
  ingress {
    description      = "Canal CNI health checks (open access)"
    from_port        = 9099
    to_port          = 9099
    protocol         = "TCP"
    cidr_blocks      = [var.network_cidr]
    ipv6_cidr_blocks = []
  }
  ingress {
    description      = "PostgreSQL port (open access)"
    from_port        = 5433
    to_port          = 5433
    protocol         = "TCP"
    cidr_blocks      = [var.network_cidr]
    ipv6_cidr_blocks = []
  }

  ingress {
    description      = "node-exporter metrics"
    from_port        = 9100
    to_port          = 9100
    protocol         = "TCP"
    cidr_blocks      = [var.network_cidr]
    ipv6_cidr_blocks = []
  }
  ingress {
    description      = "kube-controller-manager metrics"
    from_port        = 10257
    to_port          = 10257
    protocol         = "TCP"
    cidr_blocks      = [var.network_cidr]
    ipv6_cidr_blocks = []
  }
  ingress {
    description      = "kube-scheduler metrics"
    from_port        = 10259
    to_port          = 10259
    protocol         = "TCP"
    cidr_blocks      = [var.network_cidr]
    ipv6_cidr_blocks = []
  }
  ingress {
    description      = "kube-proxy metrics"
    from_port        = 10249
    to_port          = 10249
    protocol         = "TCP"
    cidr_blocks      = [var.network_cidr]
    ipv6_cidr_blocks = []
  }

  # Per-environment additions (security.tfvars: extra_ingress_rules.control_plane).
  dynamic "ingress" {
    for_each = lookup(var.extra_ingress_rules, "control_plane", [])
    content {
      description      = ingress.value.description
      from_port        = ingress.value.from_port
      to_port          = ingress.value.to_port
      protocol         = ingress.value.protocol
      cidr_blocks      = ingress.value.cidr_blocks
      ipv6_cidr_blocks = ingress.value.ipv6_cidr_blocks
    }
  }

  # Built-in outbound rules + per-environment additions
  # (security.tfvars: extra_egress_rules.control_plane).
  dynamic "egress" {
    for_each = concat(local.common_egress_rules, lookup(var.extra_egress_rules, "control_plane", []))
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

# ── k8s etcd ─────────────────────────────────────────────────────────────────
resource "aws_security_group" "k8s_etcd" {
  vpc_id      = var.vpc_id
  description = "Rules which allow the outgoing traffic from the instances associated with the security group K8S_ETCD_SECURITY_GROUP"

  tags = {
    Name      = "${var.cluster_name}-K8S_ETCD_SECURITY_GROUP"
    Cluster   = var.cluster_name
    Component = var.cluster_name
    Role      = "etcd"
  }

  ingress {
    description      = "SSH login port (open access)"
    from_port        = 22
    to_port          = 22
    protocol         = "TCP"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = []
  }
  ingress {
    description      = "Allow ICMP (open access)"
    from_port        = -1
    to_port          = -1
    protocol         = "ICMP"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = []
  }
  ingress {
    description      = "Kubelet metrics (open access)"
    from_port        = 10250
    to_port          = 10250
    protocol         = "TCP"
    cidr_blocks      = [var.network_cidr]
    ipv6_cidr_blocks = []
  }
  ingress {
    description      = "NodePort port range (open access)"
    from_port        = 30000
    to_port          = 32767
    protocol         = "TCP"
    cidr_blocks      = [var.network_cidr]
    ipv6_cidr_blocks = []
  }
  ingress {
    description      = "ETCD client port (open access)"
    from_port        = 2379
    to_port          = 2379
    protocol         = "TCP"
    cidr_blocks      = [var.network_cidr]
    ipv6_cidr_blocks = []
  }
  ingress {
    description      = "ETCD peer port (open access)"
    from_port        = 2380
    to_port          = 2380
    protocol         = "TCP"
    cidr_blocks      = [var.network_cidr]
    ipv6_cidr_blocks = []
  }
  ingress {
    description      = "ETCD metrics port (open access)"
    from_port        = 2381
    to_port          = 2381
    protocol         = "TCP"
    cidr_blocks      = [var.network_cidr]
    ipv6_cidr_blocks = []
  }
  ingress {
    description      = "Canal CNI with VXLAN (open access)"
    from_port        = 8472
    to_port          = 8472
    protocol         = "UDP"
    cidr_blocks      = [var.network_cidr]
    ipv6_cidr_blocks = []
  }
  ingress {
    # NOTE: this one is intentionally 0.0.0.0/0, not network_cidr — matches the
    # existing aws-resource-creation-main.tf rule exactly (K8S_ETCD_SECURITY_GROUP
    # differs here from K8S_CONTROL_PLANE_SECURITY_GROUP's equivalent rule).
    description      = "Canal CNI health checks (open access)"
    from_port        = 9099
    to_port          = 9099
    protocol         = "TCP"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = []
  }
  ingress {
    description      = "PostgreSQL port (open access)"
    from_port        = 5433
    to_port          = 5433
    protocol         = "TCP"
    cidr_blocks      = [var.network_cidr]
    ipv6_cidr_blocks = []
  }

  ingress {
    description      = "node-exporter metrics"
    from_port        = 9100
    to_port          = 9100
    protocol         = "TCP"
    cidr_blocks      = [var.network_cidr]
    ipv6_cidr_blocks = []
  }
  ingress {
    description      = "kube-proxy metrics"
    from_port        = 10249
    to_port          = 10249
    protocol         = "TCP"
    cidr_blocks      = [var.network_cidr]
    ipv6_cidr_blocks = []
  }

  # Per-environment additions (security.tfvars: extra_ingress_rules.etcd).
  dynamic "ingress" {
    for_each = lookup(var.extra_ingress_rules, "etcd", [])
    content {
      description      = ingress.value.description
      from_port        = ingress.value.from_port
      to_port          = ingress.value.to_port
      protocol         = ingress.value.protocol
      cidr_blocks      = ingress.value.cidr_blocks
      ipv6_cidr_blocks = ingress.value.ipv6_cidr_blocks
    }
  }

  # Built-in outbound rules + per-environment additions
  # (security.tfvars: extra_egress_rules.etcd).
  dynamic "egress" {
    for_each = concat(local.common_egress_rules, lookup(var.extra_egress_rules, "etcd", []))
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

# ── k8s worker ───────────────────────────────────────────────────────────────
resource "aws_security_group" "k8s_worker" {
  vpc_id      = var.vpc_id
  description = "Rules which allow the outgoing traffic from the instances associated with the security group K8S_WORKER_SECURITY_GROUP"

  tags = {
    Name      = "${var.cluster_name}-K8S_WORKER_SECURITY_GROUP"
    Cluster   = var.cluster_name
    Component = var.cluster_name
    Role      = "worker"
  }

  ingress {
    description      = "SSH login port (open access)"
    from_port        = 22
    to_port          = 22
    protocol         = "TCP"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = []
  }
  ingress {
    description      = "Allow ICMP (open access)"
    from_port        = -1
    to_port          = -1
    protocol         = "ICMP"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = []
  }
  ingress {
    description      = "Kubelet metrics (open access)"
    from_port        = 10250
    to_port          = 10250
    protocol         = "TCP"
    cidr_blocks      = [var.network_cidr]
    ipv6_cidr_blocks = []
  }
  ingress {
    description      = "NodePort port range (open access)"
    from_port        = 30000
    to_port          = 32767
    protocol         = "TCP"
    cidr_blocks      = [var.network_cidr]
    ipv6_cidr_blocks = []
  }
  ingress {
    description      = "Canal CNI with VXLAN (open access)"
    from_port        = 8472
    to_port          = 8472
    protocol         = "UDP"
    cidr_blocks      = [var.network_cidr]
    ipv6_cidr_blocks = []
  }
  ingress {
    description      = "Canal CNI health checks (open access)"
    from_port        = 9099
    to_port          = 9099
    protocol         = "TCP"
    cidr_blocks      = [var.network_cidr]
    ipv6_cidr_blocks = []
  }
  ingress {
    description      = "PostgreSQL port (open access)"
    from_port        = 5433
    to_port          = 5433
    protocol         = "TCP"
    cidr_blocks      = [var.network_cidr]
    ipv6_cidr_blocks = []
  }

  ingress {
    description      = "node-exporter metrics"
    from_port        = 9100
    to_port          = 9100
    protocol         = "TCP"
    cidr_blocks      = [var.network_cidr]
    ipv6_cidr_blocks = []
  }
  ingress {
    description      = "kube-proxy metrics"
    from_port        = 10249
    to_port          = 10249
    protocol         = "TCP"
    cidr_blocks      = [var.network_cidr]
    ipv6_cidr_blocks = []
  }

  # Per-environment additions (security.tfvars: extra_ingress_rules.worker).
  dynamic "ingress" {
    for_each = lookup(var.extra_ingress_rules, "worker", [])
    content {
      description      = ingress.value.description
      from_port        = ingress.value.from_port
      to_port          = ingress.value.to_port
      protocol         = ingress.value.protocol
      cidr_blocks      = ingress.value.cidr_blocks
      ipv6_cidr_blocks = ingress.value.ipv6_cidr_blocks
    }
  }

  # Built-in outbound rules + per-environment additions
  # (security.tfvars: extra_egress_rules.worker).
  dynamic "egress" {
    for_each = concat(local.common_egress_rules, lookup(var.extra_egress_rules, "worker", []))
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
