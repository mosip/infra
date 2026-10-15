variable "cluster_name" { type = string }

variable "ami" {
  type = string
  validation {
    condition     = can(regex("^ami-[a-f0-9]{17}$", var.ami))
    error_message = "Invalid AMI format. It should be in the format 'ami-xxxxxxxxxxxxxxxxx'"
  }
}

variable "ssh_key_name" { type = string }

variable "nginx_instance_type" {
  type = string
  validation {
    condition     = can(regex("^[a-z0-9]+\\..*", var.nginx_instance_type))
    error_message = "Invalid instance type format. Must be in the form 'series.type'."
  }
}

variable "k8s_instance_type" {
  type = string
  validation {
    condition     = can(regex("^[a-z0-9]+\\..*", var.k8s_instance_type))
    error_message = "Invalid instance type format. Must be in the form 'series.type'."
  }
}

variable "nginx_node_root_volume_size" { type = number }
variable "k8s_instance_root_volume_size" { type = number }

variable "public_subnet_ids" {
  description = "Public subnet IDs for the nginx instance"
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for K8s instances"
  type        = list(string)
}

variable "nginx_sg_id" {
  description = "Security group ID for the nginx instance — looked up by tag from #274's security component"
  type        = string
}

variable "k8s_control_plane_sg_id" { type = string }
variable "k8s_etcd_sg_id" { type = string }
variable "k8s_worker_sg_id" { type = string }

variable "k8s_control_plane_node_count" { type = number }
variable "k8s_etcd_node_count" { type = number }
variable "k8s_worker_node_count" { type = number }

# NGINX TAG NAME
locals {
  nginx_tag_name = "${var.cluster_name}-NGINX-NODE"
}

variable "nginx_iam_instance_profile" {
  description = "Instance profile for the nginx node (certbot's Route53 access, from the iam component). Null = none."
  type        = string
  default     = null
}

# ── power state ──────────────────────────────────────────────────────────────
# "running" is enforced when an instance is created. After that the state is
# not managed by Terraform unless set here — then every compute run enforces
# it (and undoes a stop/start made with the instance-power workflow).

variable "k8s_instance_state" {
  description = "Desired state of every cluster node: running | stopped. null (default) = not managed after creation"
  type        = string
  default     = null
  validation {
    condition     = var.k8s_instance_state == null || contains(["running", "stopped"], coalesce(var.k8s_instance_state, "running"))
    error_message = "k8s_instance_state must be running, stopped or null."
  }
}

variable "k8s_node_state" {
  description = "Desired state per cluster node name (e.g. { \"WORKER-NODE-5\" = \"stopped\" }); overrides k8s_instance_state"
  type        = map(string)
  default     = {}
  validation {
    condition     = alltrue([for s in values(var.k8s_node_state) : contains(["running", "stopped"], s)])
    error_message = "k8s_node_state values must be running or stopped."
  }
  validation {
    condition     = alltrue([for n in keys(var.k8s_node_state) : can(regex("^(CONTROL-PLANE|ETCD|WORKER)-NODE-[1-9][0-9]*$", n))])
    error_message = "k8s_node_state keys must be node names like CONTROL-PLANE-NODE-1, ETCD-NODE-1, WORKER-NODE-5."
  }
}

variable "nginx_instance_state" {
  description = "Desired state of the nginx node: running | stopped. null (default) = not managed after creation"
  type        = string
  default     = null
  validation {
    condition     = var.nginx_instance_state == null || contains(["running", "stopped"], coalesce(var.nginx_instance_state, "running"))
    error_message = "nginx_instance_state must be running, stopped or null."
  }
}
