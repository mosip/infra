# security — observ profile. No values of its own beyond ./common.tfvars;
# kept so every component has the same <component>.tfvars layout.

# Optional: extra ingress rules per security group, added to the built-in
# ones (default: none). Keys: nginx, control_plane, etcd, worker. Apply with
# COMPONENT=security; existing rules and instances are untouched.
# extra_ingress_rules = {
#   nginx = [
#     { description = "Monitoring scrape", from_port = 9100, to_port = 9100, protocol = "tcp", cidr_blocks = ["10.73.0.0/16"] },
#   ]
#   worker = [
#     { description = "App from partner network", from_port = 8443, to_port = 8443, protocol = "tcp", cidr_blocks = ["203.0.113.0/24"] },
#   ]
# }
