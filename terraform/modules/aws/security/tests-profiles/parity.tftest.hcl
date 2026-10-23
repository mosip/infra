# Legacy-parity checks for a profile's real rule table. Run once per profile
# with that profile's security.tfvars (no table here, so -var-file is used):
#   terraform test -test-directory=tests-profiles \
#     -var-file=../../../../profiles/<profile>/aws/security.tfvars
# The rules must match the pre-#273 monolith (aws-main.tf SECURITY_GROUP
# local), plus the #432 metrics ports and no ::/0 (#480).

mock_provider "aws" {}

variables {
  cluster_name   = "testcluster"
  vpc_id         = "vpc-0123456789abcdef0"
  network_cidr   = "172.0.0.0/8"
  wireguard_cidr = "172.0.0.0/8"
}

run "nginx_sg_matches_legacy_ingress_rules" {
  command = plan

  # Legacy: SECURITY_GROUP.NGINX_SECURITY_GROUP had exactly 10 ingress rules
  # (SSH, ICMP, HTTP, HTTPS, Minio, Postgres, Postgres-alt, ActiveMQ, NFS-tcp, NFS-udp)
  assert {
    condition     = length(aws_security_group.nginx.ingress) == 10
    error_message = "nginx SG ingress rule count changed from legacy's 10 rules"
  }

  assert {
    condition = anytrue([
      for r in aws_security_group.nginx.ingress :
      r.from_port == 22 && r.to_port == 22 && r.protocol == "TCP" && contains(r.cidr_blocks, "0.0.0.0/0")
    ])
    error_message = "nginx SG missing legacy SSH (22/TCP, 0.0.0.0/0) ingress rule"
  }

  assert {
    condition = anytrue([
      for r in aws_security_group.nginx.ingress :
      r.from_port == 9000 && r.to_port == 9000 && r.protocol == "TCP" && contains(r.cidr_blocks, "172.0.0.0/8")
    ])
    error_message = "nginx SG missing legacy Minio console (9000/TCP, network_cidr) ingress rule"
  }

  assert {
    condition = anytrue([
      for r in aws_security_group.nginx.ingress :
      r.from_port == 2049 && r.to_port == 2049 && r.protocol == "UDP"
    ])
    error_message = "nginx SG missing legacy NFS UDP (2049) ingress rule"
  }

  assert {
    condition     = aws_security_group.nginx.tags.Role == "nginx"
    error_message = "nginx SG missing the new Role=nginx tag (intentional #275 addition, not in the legacy monolith)"
  }
}

run "control_plane_sg_matches_legacy_ingress_rules" {
  command = plan

  # Legacy: K8S_CONTROL_PLANE_SECURITY_GROUP had exactly 12 ingress rules
  # (SSH, ICMP, K8s API, RKE2 supervisor, Kubelet metrics, ETCD client/peer/
  # metrics, NodePort range, Canal VXLAN, Canal health-check, PostgreSQL)
  # + 4 Prometheus metrics ports (9100, 10249, 10257, 10259) from #432.
  assert {
    condition     = length(aws_security_group.k8s_control_plane.ingress) == 16
    error_message = "control-plane SG ingress rule count changed (legacy 12 + 4 metrics)"
  }

  assert {
    condition = anytrue([
      for r in aws_security_group.k8s_control_plane.ingress :
      r.from_port == 6443 && r.to_port == 6443 && r.protocol == "TCP"
    ])
    error_message = "control-plane SG missing legacy Kubernetes API (6443) ingress rule"
  }

  assert {
    condition = anytrue([
      for r in aws_security_group.k8s_control_plane.ingress :
      r.from_port == 9345 && r.to_port == 9345 && r.protocol == "TCP"
    ])
    error_message = "control-plane SG missing legacy RKE2 supervisor API (9345) ingress rule"
  }

  # Legacy quirk: control-plane's Canal CNI health-check rule uses network_cidr,
  # NOT 0.0.0.0/0 (unlike ETCD's equivalent rule below) — must be preserved exactly.
  assert {
    condition = anytrue([
      for r in aws_security_group.k8s_control_plane.ingress :
      r.from_port == 9099 && r.to_port == 9099 && contains(r.cidr_blocks, "172.0.0.0/8") && !contains(r.cidr_blocks, "0.0.0.0/0")
    ])
    error_message = "control-plane SG's Canal CNI health-check rule must use network_cidr, not 0.0.0.0/0 (legacy behavior)"
  }

  assert {
    condition     = aws_security_group.k8s_control_plane.tags.Role == "control-plane"
    error_message = "control-plane SG missing the new Role=control-plane tag"
  }
}

run "etcd_sg_matches_legacy_ingress_rules_including_quirk" {
  command = plan

  # Legacy: K8S_ETCD_SECURITY_GROUP had exactly 10 ingress rules
  assert {
    condition     = length(aws_security_group.k8s_etcd.ingress) == 12
    error_message = "etcd SG ingress rule count changed from legacy's 10 rules"
  }

  # The exact legacy quirk this decoupling had to preserve deliberately:
  # ETCD's Canal CNI health-check rule uses 0.0.0.0/0, NOT network_cidr —
  # opposite of control-plane's equivalent rule. Confirmed against
  # aws-main.tf's K8S_ETCD_SECURITY_GROUP definition.
  assert {
    condition = anytrue([
      for r in aws_security_group.k8s_etcd.ingress :
      r.from_port == 9099 && r.to_port == 9099 && contains(r.cidr_blocks, "0.0.0.0/0")
    ])
    error_message = "etcd SG's Canal CNI health-check rule must use 0.0.0.0/0 (legacy quirk, differs from control-plane's equivalent rule) — regression risk if this ever gets 'fixed' to match control-plane"
  }

  assert {
    condition     = aws_security_group.k8s_etcd.tags.Role == "etcd"
    error_message = "etcd SG missing the new Role=etcd tag"
  }
}

run "worker_sg_matches_legacy_ingress_rules" {
  command = plan

  # Legacy: K8S_WORKER_SECURITY_GROUP had exactly 7 ingress rules
  assert {
    condition     = length(aws_security_group.k8s_worker.ingress) == 9
    error_message = "worker SG ingress rule count changed from legacy's 7 rules"
  }

  assert {
    condition = anytrue([
      for r in aws_security_group.k8s_worker.ingress :
      r.from_port == 8472 && r.to_port == 8472 && r.protocol == "UDP"
    ])
    error_message = "worker SG missing legacy Canal CNI VXLAN (8472/UDP) ingress rule"
  }

  assert {
    condition     = aws_security_group.k8s_worker.tags.Role == "worker"
    error_message = "worker SG missing the new Role=worker tag"
  }
}

run "shared_egress_rules_match_legacy_on_every_group" {
  command = plan

  # Legacy: aws-resource-creation-main.tf's aws_security_group.security-group
  # had exactly 6 egress blocks, shared identically across all 4 node types.
  assert {
    condition     = length(aws_security_group.nginx.egress) == 6
    error_message = "nginx SG egress rule count changed from legacy's 6 shared rules"
  }
  assert {
    condition     = length(aws_security_group.k8s_control_plane.egress) == 6
    error_message = "control-plane SG egress rule count changed from legacy's 6 shared rules"
  }
  assert {
    condition     = length(aws_security_group.k8s_etcd.egress) == 6
    error_message = "etcd SG egress rule count changed from legacy's 6 shared rules"
  }
  assert {
    condition     = length(aws_security_group.k8s_worker.egress) == 6
    error_message = "worker SG egress rule count changed from legacy's 6 shared rules"
  }

  assert {
    condition = anytrue([
      for r in aws_security_group.nginx.egress :
      r.from_port == 51820 && r.to_port == 51820 && r.protocol == "udp" && contains(r.cidr_blocks, "172.0.0.0/8")
    ])
    error_message = "nginx SG missing legacy WireGuard egress rule (51820/udp to wireguard_cidr)"
  }

  assert {
    condition = anytrue([
      for r in aws_security_group.nginx.egress :
      r.protocol == "-1" && contains(r.cidr_blocks, "10.42.0.0/16") && contains(r.cidr_blocks, "10.43.0.0/16")
    ])
    error_message = "nginx SG missing legacy internal-communication egress rule (VPC + Pod networks, all protocols)"
  }
}

run "metrics_ports_vpc_only_ipv4_only" {
  command = plan

  assert {
    condition = alltrue(flatten([
      for g in [aws_security_group.k8s_control_plane, aws_security_group.k8s_etcd, aws_security_group.k8s_worker] : [
        for r in g.ingress : length(r.cidr_blocks) == 1 && contains(r.cidr_blocks, "172.0.0.0/8") && length(r.ipv6_cidr_blocks) == 0 && r.protocol == "TCP"
        if contains([9100, 10249, 10257, 10259], r.from_port)
      ]
    ]))
    error_message = "Metrics ports must allow only the VPC CIDR over IPv4 (no ::/0)"
  }

  assert {
    condition = (
      length([for r in aws_security_group.k8s_control_plane.ingress : r if contains([9100, 10249, 10257, 10259], r.from_port)]) == 4 &&
      length([for r in aws_security_group.k8s_etcd.ingress : r if contains([9100, 10249], r.from_port)]) == 2 &&
      length([for r in aws_security_group.k8s_worker.ingress : r if contains([9100, 10249], r.from_port)]) == 2 &&
      length([for r in aws_security_group.nginx.ingress : r if contains([9100, 10249, 10257, 10259], r.from_port)]) == 0
    )
    error_message = "control plane: 9100/10249/10257/10259; etcd + worker: 9100/10249; nginx: none"
  }
}

run "no_builtin_rule_allows_ipv6" {
  command = plan

  assert {
    condition = alltrue(flatten([
      for g in [aws_security_group.nginx, aws_security_group.k8s_control_plane, aws_security_group.k8s_etcd, aws_security_group.k8s_worker] : [
        for r in setunion(g.ingress, g.egress) : length(r.ipv6_cidr_blocks) == 0
      ]
    ]))
    error_message = "Built-in rules must not allow IPv6 (ipv6_cidr_blocks = [])"
  }
}
