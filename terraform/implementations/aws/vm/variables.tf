# cluster_name/aws_provider_region/vpc_name/ami/ssh_key_name come from
# profiles/<profile>/aws/common.tfvars; instance_groups from vm.tfvars.
variable "cluster_name" { type = string }
variable "aws_provider_region" { type = string }
variable "vpc_name" { type = string }
variable "ami" { type = string }
variable "ssh_key_name" { type = string }

variable "allow_ssh_from_anywhere" {
  type    = bool
  default = false
}

variable "instance_groups" {
  description = "See modules/aws/instance-group — one entry per workload"
  type        = any
  default     = {}
}

# ── VPC choice (vm.tfvars, optional — default: vpc_name from common.tfvars) ──
variable "vm_use_default_vpc" {
  description = "Use the region's default VPC (public default-for-az subnets only)"
  type        = bool
  default     = false
}

variable "vm_vpc_id" {
  description = "Existing VPC by ID"
  type        = string
  default     = null
  validation {
    condition     = var.vm_vpc_id == null || can(regex("^vpc-[0-9a-f]{8,17}$", coalesce(var.vm_vpc_id, "x")))
    error_message = "vm_vpc_id must look like vpc-0123456789abcdef0."
  }
}

variable "vm_vpc_name" {
  description = "Existing VPC by Name tag (instead of vpc_name from common.tfvars)"
  type        = string
  default     = null
}

variable "vm_public_subnet_ids" {
  description = "Public subnet IDs to use instead of the Type = Public lookup"
  type        = list(string)
  default     = null
  validation {
    condition     = var.vm_public_subnet_ids == null || alltrue([for s in coalesce(var.vm_public_subnet_ids, []) : can(regex("^subnet-[0-9a-f]{8,17}$", s))])
    error_message = "vm_public_subnet_ids must be subnet IDs like subnet-0123456789abcdef0."
  }
}

variable "vm_private_subnet_ids" {
  description = "Private subnet IDs to use instead of the Type = Private lookup"
  type        = list(string)
  default     = null
  validation {
    condition     = var.vm_private_subnet_ids == null || alltrue([for s in coalesce(var.vm_private_subnet_ids, []) : can(regex("^subnet-[0-9a-f]{8,17}$", s))])
    error_message = "vm_private_subnet_ids must be subnet IDs like subnet-0123456789abcdef0."
  }
}
