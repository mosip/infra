# compute-specific values — MOSIP platform profile
# cluster_name/aws_provider_region/vpc_name come from ./common.tfvars

specific_availability_zones = []

k8s_instance_type   = "t3a.2xlarge"
nginx_instance_type = "t3a.2xlarge"

nginx_node_root_volume_size   = 24
k8s_instance_root_volume_size = 64

# Control-plane, ETCD, Worker — production shape for 7 nodes: 3 / 0 / 4.
# With the k8s-infra RKE2 templates (release-1.2.1.x):
#   control-plane  rke2-server: API server, scheduler, controller-manager and
#                  etcd. etcd members = control-plane count -> keep it odd
#                  (3 tolerates 1 node failure, 5 tolerates 2).
#   etcd           started as rke2-agent, which skips the template's
#                  server-only settings — joins as a worker, NOT an etcd
#                  member. Leave at 0 unless that changes.
#   worker         rke2-agent; kubelet only.
# No template adds taints, so every node also runs workloads.
k8s_control_plane_node_count = 3
k8s_etcd_node_count          = 0
k8s_worker_node_count        = 5

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

# ── #437 AWS test only — revert before GH-issue-273-v2 merges to develop ──
# Terraform power-state test: WORKER-NODE-5 stopped (#463), now back to running.
k8s_node_state = { "WORKER-NODE-5" = "running" }

# Instance type per node (optional, rarely needed) — overrides k8s_instance_type
# for the named nodes only, e.g. for a rolling resize (one node per compute
# run; drain it first; control-plane nodes one at a time). Same instance, IP
# and disk: the node is stopped, resized and started.
# k8s_node_instance_type = { "WORKER-NODE-5" = "m6a.2xlarge" }
