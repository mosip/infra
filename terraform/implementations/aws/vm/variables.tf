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
