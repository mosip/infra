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

# ═══ Optional settings ═══════════════════════════════════════════════════
# Everything below is commented out = default behaviour. Uncomment only the
# line(s) of the feature you need, then run terraform plan / apply with
# COMPONENT=compute (plan first). "Back to default" says how to undo each one.

# ── 1. Power state — keep nodes stopped or running (Terraform-managed) ───────
# Default (commented out): Terraform starts each instance when it creates it,
#   then leaves running/stopped alone. Stop/start ad hoc with the
#   "instances start / stop" workflow (by private IP).
# Uncomment when the state should be recorded in git and enforced on every
#   compute run (it then also undoes a stop/start made with the workflow):
# k8s_instance_state   = "stopped"                         # every cluster node
# k8s_node_state       = { "WORKER-NODE-1" = "stopped" }   # named nodes; overrides the line above
# nginx_instance_state = "stopped"                         # nginx node (public IP, NFS, PostgreSQL)
#   Values: "running" | "stopped". Node names: CONTROL-PLANE-NODE-n,
#   ETCD-NODE-n, WORKER-NODE-n.
# Back to default: set the value to "running" and apply (starts the node),
#   then comment the line out. The plan then shows "1 to destroy" for
#   aws_ec2_instance_state — that only stops managing the state; the instance
#   keeps running. Commenting out while "stopped" leaves the node stopped.

# ── 2. Instance type per node — rolling resize (rarely needed) ───────────────
# Default (commented out): every cluster node uses k8s_instance_type above.
#   Changing k8s_instance_type resizes ALL cluster nodes in the same run
#   (whole cluster down for a few minutes).
# Uncomment to give named nodes another type, one node per compute run:
# k8s_node_instance_type = { "WORKER-NODE-1" = "m6a.2xlarge" }
#   Each listed node is stopped, resized and started — same instance, private
#   IP and disk; RKE2 rejoins on boot, no configure needed. Drain the node
#   first; change control-plane nodes one at a time. Keep the AMI's CPU
#   architecture (x86: t3a / m6a / m7a; ARM types need an ARM AMI).
# Back to default: comment the line out — the next compute run resizes the
#   node back to k8s_instance_type.
