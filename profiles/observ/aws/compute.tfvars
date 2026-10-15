# compute-specific values — observ profile (single-node observability cluster)
# cluster_name/aws_provider_region/vpc_name come from ./common.tfvars

specific_availability_zones = []

# Minimal node counts for observability — single control-plane node, no
# etcd/worker groups.
k8s_control_plane_node_count = 1
k8s_etcd_node_count          = 0
k8s_worker_node_count        = 0

# Minimal instance types for observability
k8s_instance_type   = "t3a.2xlarge"
nginx_instance_type = "t3a.large"

nginx_node_root_volume_size   = 24
k8s_instance_root_volume_size = 32

# nginx gets the certbot Route53 instance profile from the iam component.
# Set false when profile.yml uses another TLS mode (byo, http01, dns01 with
# a non-route53 provider).
attach_certbot_profile = true

# Power state (optional). Unset = Terraform starts instances when it creates
# them and leaves running/stopped alone afterwards (use the "instances
# start / stop" workflow). When set, every compute run enforces it.
# k8s_instance_state   = "stopped"                         # all cluster nodes
# k8s_node_state       = { "WORKER-NODE-5" = "stopped" }   # per node, overrides
# nginx_instance_state = "running"

# Instance type per node (optional, rarely needed) — overrides k8s_instance_type
# for the named nodes only, e.g. for a rolling resize (one node per compute
# run; drain it first; control-plane nodes one at a time). Same instance, IP
# and disk: the node is stopped, resized and started.
# k8s_node_instance_type = { "WORKER-NODE-5" = "m6a.2xlarge" }
