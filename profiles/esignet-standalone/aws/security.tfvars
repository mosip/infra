# security — esignet-standalone profile. No values of its own beyond ./common.tfvars;
# kept so every component has the same <component>.tfvars layout.

# ═══ Optional settings ═══════════════════════════════════════════════════
# Commented out = default (only the built-in rules of
# terraform/modules/aws/security). Uncomment to add rules for this
# environment, then run terraform plan / apply with COMPONENT=security (plan
# first): the security groups are updated in place, instances are untouched.
# Groups: nginx, control_plane, etcd, worker. Each rule needs cidr_blocks
# and/or ipv6_cidr_blocks; protocol "tcp", "udp", "icmp" or "-1" (all).
# Back to default: comment the rule out again and apply — it is removed.

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
