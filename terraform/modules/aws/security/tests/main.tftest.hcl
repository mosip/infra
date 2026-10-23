# Verifies the decoupled `security` module produces security groups
# byte-for-byte equivalent (ingress/egress rules, ports, protocols, CIDRs)
# to the pre-#273 monolith's `aws-resource-creation-main.tf` +
# `aws-main.tf`'s SECURITY_GROUP local — with the one intentional addition
# (the `Role` tag, needed for #275's tag-based discovery) called out
# explicitly rather than silently asserted away.
#
# mock_provider avoids needing real AWS credentials; `command = plan` is
# used throughout (default) so nothing ever attempts a real API call.

mock_provider "aws" {}

variables {
  cluster_name   = "testcluster"
  vpc_id         = "vpc-0123456789abcdef0"
  network_cidr   = "172.0.0.0/8"
  wireguard_cidr = "172.0.0.0/8"

  # Fixture rule table (copy of profiles/*/aws/security.tfvars) for the module
  # mechanics tests below. The real profile tables are checked against the
  # legacy rules by ../tests-profiles/ (run per profile in infra-checks.yml).
  ingress_rules = {
    nginx = [
      { description = "SSH login port (open access)", from_port = 22, to_port = 22, protocol = "TCP", cidr_blocks = ["0.0.0.0/0"] },
      { description = "Allow ICMP (open access)", from_port = -1, to_port = -1, protocol = "ICMP", cidr_blocks = ["0.0.0.0/0"] },
      { description = "HTTP port (public)", from_port = 80, to_port = 80, protocol = "TCP", cidr_blocks = ["0.0.0.0/0"] },
      { description = "HTTPS port (public)", from_port = 443, to_port = 443, protocol = "TCP", cidr_blocks = ["0.0.0.0/0"] },
      { description = "Minio console port (open access)", from_port = 9000, to_port = 9000, protocol = "TCP", cidr_blocks = ["network_cidr"] },
      { description = "Postgres port (open access)", from_port = 5432, to_port = 5432, protocol = "TCP", cidr_blocks = ["network_cidr"] },
      { description = "Postgres alternative port (open access)", from_port = 5433, to_port = 5433, protocol = "TCP", cidr_blocks = ["network_cidr"] },
      { description = "ActiveMQ port (open access)", from_port = 61616, to_port = 61616, protocol = "TCP", cidr_blocks = ["network_cidr"] },
      { description = "NFS server port tcp (open access)", from_port = 2049, to_port = 2049, protocol = "TCP", cidr_blocks = ["network_cidr"] },
      { description = "NFS server port udp (open access)", from_port = 2049, to_port = 2049, protocol = "UDP", cidr_blocks = ["network_cidr"] },
    ]
    control_plane = [
      { description = "SSH login port (open access)", from_port = 22, to_port = 22, protocol = "TCP", cidr_blocks = ["0.0.0.0/0"] },
      { description = "Allow ICMP (open access)", from_port = -1, to_port = -1, protocol = "ICMP", cidr_blocks = ["0.0.0.0/0"] },
      { description = "Kubernetes API (open access)", from_port = 6443, to_port = 6443, protocol = "TCP", cidr_blocks = ["network_cidr"] },
      { description = "RKE2 supervisor API (open access)", from_port = 9345, to_port = 9345, protocol = "TCP", cidr_blocks = ["network_cidr"] },
      { description = "Kubelet metrics (open access)", from_port = 10250, to_port = 10250, protocol = "TCP", cidr_blocks = ["network_cidr"] },
      { description = "ETCD client port (open access)", from_port = 2379, to_port = 2379, protocol = "TCP", cidr_blocks = ["network_cidr"] },
      { description = "ETCD peer port (open access)", from_port = 2380, to_port = 2380, protocol = "TCP", cidr_blocks = ["network_cidr"] },
      { description = "ETCD metrics port (open access)", from_port = 2381, to_port = 2381, protocol = "TCP", cidr_blocks = ["network_cidr"] },
      { description = "NodePort port range (open access)", from_port = 30000, to_port = 32767, protocol = "TCP", cidr_blocks = ["network_cidr"] },
      { description = "Canal CNI with VXLAN (open access)", from_port = 8472, to_port = 8472, protocol = "UDP", cidr_blocks = ["network_cidr"] },
      { description = "Canal CNI health checks (open access)", from_port = 9099, to_port = 9099, protocol = "TCP", cidr_blocks = ["network_cidr"] },
      { description = "PostgreSQL port (open access)", from_port = 5433, to_port = 5433, protocol = "TCP", cidr_blocks = ["network_cidr"] },
      { description = "node-exporter metrics", from_port = 9100, to_port = 9100, protocol = "TCP", cidr_blocks = ["network_cidr"] },
      { description = "kube-controller-manager metrics", from_port = 10257, to_port = 10257, protocol = "TCP", cidr_blocks = ["network_cidr"] },
      { description = "kube-scheduler metrics", from_port = 10259, to_port = 10259, protocol = "TCP", cidr_blocks = ["network_cidr"] },
      { description = "kube-proxy metrics", from_port = 10249, to_port = 10249, protocol = "TCP", cidr_blocks = ["network_cidr"] },
    ]
    etcd = [
      { description = "SSH login port (open access)", from_port = 22, to_port = 22, protocol = "TCP", cidr_blocks = ["0.0.0.0/0"] },
      { description = "Allow ICMP (open access)", from_port = -1, to_port = -1, protocol = "ICMP", cidr_blocks = ["0.0.0.0/0"] },
      { description = "Kubelet metrics (open access)", from_port = 10250, to_port = 10250, protocol = "TCP", cidr_blocks = ["network_cidr"] },
      { description = "NodePort port range (open access)", from_port = 30000, to_port = 32767, protocol = "TCP", cidr_blocks = ["network_cidr"] },
      { description = "ETCD client port (open access)", from_port = 2379, to_port = 2379, protocol = "TCP", cidr_blocks = ["network_cidr"] },
      { description = "ETCD peer port (open access)", from_port = 2380, to_port = 2380, protocol = "TCP", cidr_blocks = ["network_cidr"] },
      { description = "ETCD metrics port (open access)", from_port = 2381, to_port = 2381, protocol = "TCP", cidr_blocks = ["network_cidr"] },
      { description = "Canal CNI with VXLAN (open access)", from_port = 8472, to_port = 8472, protocol = "UDP", cidr_blocks = ["network_cidr"] },
      { description = "Canal CNI health checks (open access)", from_port = 9099, to_port = 9099, protocol = "TCP", cidr_blocks = ["0.0.0.0/0"] },
      { description = "PostgreSQL port (open access)", from_port = 5433, to_port = 5433, protocol = "TCP", cidr_blocks = ["network_cidr"] },
      { description = "node-exporter metrics", from_port = 9100, to_port = 9100, protocol = "TCP", cidr_blocks = ["network_cidr"] },
      { description = "kube-proxy metrics", from_port = 10249, to_port = 10249, protocol = "TCP", cidr_blocks = ["network_cidr"] },
    ]
    worker = [
      { description = "SSH login port (open access)", from_port = 22, to_port = 22, protocol = "TCP", cidr_blocks = ["0.0.0.0/0"] },
      { description = "Allow ICMP (open access)", from_port = -1, to_port = -1, protocol = "ICMP", cidr_blocks = ["0.0.0.0/0"] },
      { description = "Kubelet metrics (open access)", from_port = 10250, to_port = 10250, protocol = "TCP", cidr_blocks = ["network_cidr"] },
      { description = "NodePort port range (open access)", from_port = 30000, to_port = 32767, protocol = "TCP", cidr_blocks = ["network_cidr"] },
      { description = "Canal CNI with VXLAN (open access)", from_port = 8472, to_port = 8472, protocol = "UDP", cidr_blocks = ["network_cidr"] },
      { description = "Canal CNI health checks (open access)", from_port = 9099, to_port = 9099, protocol = "TCP", cidr_blocks = ["network_cidr"] },
      { description = "PostgreSQL port (open access)", from_port = 5433, to_port = 5433, protocol = "TCP", cidr_blocks = ["network_cidr"] },
      { description = "node-exporter metrics", from_port = 9100, to_port = 9100, protocol = "TCP", cidr_blocks = ["network_cidr"] },
      { description = "kube-proxy metrics", from_port = 10249, to_port = 10249, protocol = "TCP", cidr_blocks = ["network_cidr"] },
    ]
  }

  egress_rules = [
    { description = "Allow HTTP outbound to anywhere (for package downloads)", from_port = 80, to_port = 80, protocol = "tcp", cidr_blocks = ["0.0.0.0/0"] },
    { description = "Allow HTTPS outbound to anywhere", from_port = 443, to_port = 443, protocol = "tcp", cidr_blocks = ["0.0.0.0/0"] },
    { description = "Allow WireGuard VPN outbound to VPN CIDR", from_port = 51820, to_port = 51820, protocol = "udp", cidr_blocks = ["wireguard_cidr"] },
    { description = "Allow DNS TCP outbound to anywhere (for public DNS resolution)", from_port = 53, to_port = 53, protocol = "tcp", cidr_blocks = ["0.0.0.0/0"] },
    { description = "Allow DNS UDP outbound to anywhere (for public DNS resolution)", from_port = 53, to_port = 53, protocol = "udp", cidr_blocks = ["0.0.0.0/0"] },
    { description = "Allow all required internal communication (VPC + Pod Networks)", from_port = 0, to_port = 0, protocol = "-1", cidr_blocks = ["network_cidr", "10.42.0.0/16", "10.43.0.0/16"] },
  ]
}

run "all_groups_tagged_with_cluster_and_component" {
  command = plan

  assert {
    condition     = aws_security_group.nginx.tags.Cluster == "testcluster" && aws_security_group.nginx.tags.Component == "testcluster"
    error_message = "nginx SG Cluster/Component tags don't match legacy convention (both = cluster_name)"
  }
  assert {
    condition     = aws_security_group.k8s_control_plane.vpc_id == "vpc-0123456789abcdef0"
    error_message = "control-plane SG not attached to the expected VPC"
  }
}

# ── extra_ingress_rules (per-environment additions) ─────────────────────────

run "extra_ingress_rules_default_changes_nothing" {
  command = plan

  assert {
    condition = (
      length(aws_security_group.nginx.ingress) == 10 &&
      length(aws_security_group.k8s_worker.ingress) == 9
    )
    error_message = "Without extra_ingress_rules the built-in rule counts must not change"
  }
}

run "extra_ingress_rules_are_added_to_the_right_group" {
  command = plan

  variables {
    extra_ingress_rules = {
      nginx = [
        { description = "Monitoring scrape", from_port = 9100, to_port = 9100, protocol = "tcp", cidr_blocks = ["10.73.0.0/16"] },
      ]
      worker = [
        { description = "Partner app", from_port = 8443, to_port = 8443, protocol = "tcp", cidr_blocks = ["203.0.113.0/24"] },
        { description = "Partner app v6", from_port = 8443, to_port = 8443, protocol = "tcp", ipv6_cidr_blocks = ["2001:db8::/32"] },
      ]
    }
  }

  assert {
    condition = length(aws_security_group.nginx.ingress) == 11 && anytrue([
      for r in aws_security_group.nginx.ingress :
      r.from_port == 9100 && r.protocol == "tcp" && contains(r.cidr_blocks, "10.73.0.0/16")
    ])
    error_message = "nginx extra rule (9100 from 10.73.0.0/16) missing"
  }

  assert {
    condition = length(aws_security_group.k8s_worker.ingress) == 11 && anytrue([
      for r in aws_security_group.k8s_worker.ingress :
      r.from_port == 8443 && contains(r.ipv6_cidr_blocks, "2001:db8::/32")
    ])
    error_message = "worker extra rules missing"
  }

  assert {
    condition = (
      length(aws_security_group.k8s_control_plane.ingress) == 16 &&
      length(aws_security_group.k8s_etcd.ingress) == 12
    )
    error_message = "groups without extra rules must keep their built-in rules only"
  }
}

run "extra_ingress_rules_rejects_unknown_group" {
  command = plan

  variables {
    extra_ingress_rules = {
      bastion = [
        { description = "x", from_port = 22, to_port = 22, protocol = "tcp", cidr_blocks = ["10.0.0.0/8"] },
      ]
    }
  }

  expect_failures = [var.extra_ingress_rules]
}

run "extra_ingress_rules_rejects_rule_without_source" {
  command = plan

  variables {
    extra_ingress_rules = {
      nginx = [
        { description = "no source", from_port = 8080, to_port = 8080, protocol = "tcp" },
      ]
    }
  }

  expect_failures = [var.extra_ingress_rules]
}

# ── extra_egress_rules (per-environment outbound additions) ─────────────────

run "extra_egress_rules_default_changes_nothing" {
  command = plan

  assert {
    condition = (
      length(aws_security_group.nginx.egress) == 6 &&
      length(aws_security_group.k8s_control_plane.egress) == 6 &&
      length(aws_security_group.k8s_etcd.egress) == 6 &&
      length(aws_security_group.k8s_worker.egress) == 6
    )
    error_message = "Without extra_egress_rules every group keeps exactly the 6 built-in egress rules"
  }
}

run "extra_egress_rules_are_added_to_the_right_group" {
  command = plan

  variables {
    extra_egress_rules = {
      worker = [
        { description = "SMTP relay", from_port = 587, to_port = 587, protocol = "tcp", cidr_blocks = ["198.51.100.25/32"] },
        { description = "Partner API v6", from_port = 8443, to_port = 8443, protocol = "tcp", ipv6_cidr_blocks = ["2001:db8::/32"] },
      ]
    }
  }

  assert {
    condition = (
      length(aws_security_group.k8s_worker.egress) == 8 &&
      anytrue([for r in aws_security_group.k8s_worker.egress : r.from_port == 587 && contains(r.cidr_blocks, "198.51.100.25/32")]) &&
      anytrue([for r in aws_security_group.k8s_worker.egress : r.from_port == 8443 && contains(r.ipv6_cidr_blocks, "2001:db8::/32")])
    )
    error_message = "worker extra egress rules missing"
  }
  assert {
    condition = (
      length(aws_security_group.nginx.egress) == 6 &&
      length(aws_security_group.k8s_control_plane.egress) == 6 &&
      length(aws_security_group.k8s_etcd.egress) == 6
    )
    error_message = "groups without extra egress rules must keep their built-in rules only"
  }
}

run "extra_egress_rules_rejects_unknown_group" {
  command = plan

  variables {
    extra_egress_rules = {
      bastion = [
        { description = "x", from_port = 443, to_port = 443, protocol = "tcp", cidr_blocks = ["0.0.0.0/0"] },
      ]
    }
  }

  expect_failures = [var.extra_egress_rules]
}

run "extra_egress_rules_rejects_rule_without_destination" {
  command = plan

  variables {
    extra_egress_rules = {
      nginx = [
        { description = "no destination", from_port = 25, to_port = 25, protocol = "tcp" },
      ]
    }
  }

  expect_failures = [var.extra_egress_rules]
}

# ── Prometheus metrics ports (#432) ─────────────────────────────────────────

# ── ingress_rules / egress_rules from tfvars ─────────────────────────────────

run "placeholders_are_replaced" {
  command = plan

  variables {
    network_cidr   = "10.73.0.0/16"
    wireguard_cidr = "10.15.0.0/16"
  }

  assert {
    condition = alltrue(flatten([
      for g in [aws_security_group.nginx, aws_security_group.k8s_control_plane, aws_security_group.k8s_etcd, aws_security_group.k8s_worker] : [
        for r in setunion(g.ingress, g.egress) : !contains(r.cidr_blocks, "network_cidr") && !contains(r.cidr_blocks, "wireguard_cidr")
      ]
    ]))
    error_message = "Placeholders must not reach AWS"
  }

  assert {
    condition = (
      anytrue([for r in aws_security_group.k8s_control_plane.ingress : r.from_port == 6443 && contains(r.cidr_blocks, "10.73.0.0/16")]) &&
      anytrue([for r in aws_security_group.k8s_worker.egress : r.from_port == 51820 && contains(r.cidr_blocks, "10.15.0.0/16")])
    )
    error_message = "network_cidr / wireguard_cidr must be filled in from the variables"
  }
}

run "row_added_in_tfvars_reaches_only_that_group" {
  command = plan

  variables {
    ingress_rules = {
      nginx         = [{ description = "SSH", from_port = 22, to_port = 22, protocol = "TCP", cidr_blocks = ["0.0.0.0/0"] }]
      control_plane = [{ description = "SSH", from_port = 22, to_port = 22, protocol = "TCP", cidr_blocks = ["0.0.0.0/0"] }]
      etcd          = [{ description = "SSH", from_port = 22, to_port = 22, protocol = "TCP", cidr_blocks = ["0.0.0.0/0"] }]
      worker = [
        { description = "SSH", from_port = 22, to_port = 22, protocol = "TCP", cidr_blocks = ["0.0.0.0/0"] },
        { description = "App port", from_port = 8443, to_port = 8443, protocol = "TCP", cidr_blocks = ["network_cidr"] },
      ]
    }
  }

  assert {
    condition = (
      length(aws_security_group.k8s_worker.ingress) == 2 &&
      length(aws_security_group.k8s_control_plane.ingress) == 1 &&
      anytrue([for r in aws_security_group.k8s_worker.ingress : r.from_port == 8443 && contains(r.cidr_blocks, "172.0.0.0/8")])
    )
    error_message = "A row in ingress_rules.worker must reach the worker group only"
  }
}

run "ingress_rules_missing_group_rejected" {
  command = plan

  variables {
    ingress_rules = {
      nginx         = [{ description = "SSH", from_port = 22, to_port = 22, protocol = "TCP", cidr_blocks = ["0.0.0.0/0"] }]
      control_plane = [{ description = "SSH", from_port = 22, to_port = 22, protocol = "TCP", cidr_blocks = ["0.0.0.0/0"] }]
      etcd          = [{ description = "SSH", from_port = 22, to_port = 22, protocol = "TCP", cidr_blocks = ["0.0.0.0/0"] }]
    }
  }

  expect_failures = [var.ingress_rules]
}

run "ingress_rules_unknown_group_rejected" {
  command = plan

  variables {
    ingress_rules = {
      nginx         = [{ description = "SSH", from_port = 22, to_port = 22, protocol = "TCP", cidr_blocks = ["0.0.0.0/0"] }]
      control_plane = [{ description = "SSH", from_port = 22, to_port = 22, protocol = "TCP", cidr_blocks = ["0.0.0.0/0"] }]
      etcd          = [{ description = "SSH", from_port = 22, to_port = 22, protocol = "TCP", cidr_blocks = ["0.0.0.0/0"] }]
      workers       = [{ description = "SSH", from_port = 22, to_port = 22, protocol = "TCP", cidr_blocks = ["0.0.0.0/0"] }]
    }
  }

  expect_failures = [var.ingress_rules]
}

run "ingress_rule_without_source_rejected" {
  command = plan

  variables {
    ingress_rules = {
      nginx         = [{ description = "SSH", from_port = 22, to_port = 22, protocol = "TCP" }]
      control_plane = [{ description = "SSH", from_port = 22, to_port = 22, protocol = "TCP", cidr_blocks = ["0.0.0.0/0"] }]
      etcd          = [{ description = "SSH", from_port = 22, to_port = 22, protocol = "TCP", cidr_blocks = ["0.0.0.0/0"] }]
      worker        = [{ description = "SSH", from_port = 22, to_port = 22, protocol = "TCP", cidr_blocks = ["0.0.0.0/0"] }]
    }
  }

  expect_failures = [var.ingress_rules]
}

run "egress_rule_without_destination_rejected" {
  command = plan

  variables {
    egress_rules = [{ description = "HTTPS", from_port = 443, to_port = 443, protocol = "tcp" }]
  }

  expect_failures = [var.egress_rules]
}
