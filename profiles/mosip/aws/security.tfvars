# security — mosip profile. Every security group rule for this environment.
#
# Change a port: edit, add or delete a row below, then run terraform plan /
# apply with COMPONENT=security (plan first). The groups are updated in place;
# instances are untouched. Only this environment changes.
#   - Groups: nginx, control_plane, etcd, worker (all four required).
#   - protocol: "TCP"/"tcp", "UDP"/"udp", "ICMP"/"icmp" or "-1" (all);
#     from_port = to_port = -1 for ICMP, 0 for "-1".
#   - cidr_blocks: CIDRs, or the placeholders "network_cidr" (VPC CIDR) and
#     "wireguard_cidr" — filled in from ./common.tfvars.
#   - ipv6_cidr_blocks: optional, default [] (none).
# Keep descriptions as they are: changing one makes AWS replace that rule.

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
  { description = "Allow SMTP submission outbound (Alertmanager email alerts)", from_port = 587, to_port = 587, protocol = "tcp", cidr_blocks = ["0.0.0.0/0"] },
  { description = "Allow all required internal communication (VPC + Pod Networks)", from_port = 0, to_port = 0, protocol = "-1", cidr_blocks = ["network_cidr", "10.42.0.0/16", "10.43.0.0/16"] },
]

# ═══ Optional: extra_ingress_rules / extra_egress_rules ═════════════════
# Added on top of the tables above (kept for existing setups). For a new port,
# just add a row to ingress_rules / egress_rules instead.

# ── 1. Extra INBOUND rules (ingress) ──────────────────────────────────────────
# extra_ingress_rules = {
#   nginx = [
#     { description = "Monitoring scrape", from_port = 9100, to_port = 9100, protocol = "tcp", cidr_blocks = ["10.73.0.0/16"] },
#   ]
#   worker = [
#     { description = "App from partner network", from_port = 8443, to_port = 8443, protocol = "tcp", cidr_blocks = ["203.0.113.0/24"] },
#   ]
# }

# ── 2. Extra OUTBOUND rules (egress) ──────────────────────────────────────────
# Built-in outbound on every group: 80, 443, DNS 53, WireGuard 51820/udp and
# everything inside the VPC + pod networks. Add what else the nodes must reach:
# extra_egress_rules = {
#   worker = [
#     { description = "SMTP relay", from_port = 587, to_port = 587, protocol = "tcp", cidr_blocks = ["198.51.100.25/32"] },
#   ]
# }
