# Verifies the decoupled `storage` module's separate aws_ebs_volume +
# aws_volume_attachment resources produce the same device names, sizes,
# type, and encryption settings as the legacy monolith's inline
# ebs_block_device blocks (aws-resource-creation/variables.tf's
# NGINX_INSTANCE.ebs_block_device local) — including the exact same
# conditional-creation gates for volumes 2 and 3.

mock_provider "aws" {}

variables {
  cluster_name               = "testcluster"
  nginx_instance_id          = "i-0123456789abcdef0"
  availability_zone          = "ap-south-1a"
  nginx_tag_name             = "testcluster-NGINX-NODE"
  nginx_node_ebs_volume_size = 300
}

run "mosip_profile_shape_all_three_volumes" {
  command = plan

  variables {
    nginx_node_ebs_volume_size_2 = 200
    nginx_node_ebs_volume_size_3 = 30
    enable_activemq_setup        = true
  }

  assert {
    condition     = aws_ebs_volume.nfs.size == 300 && aws_ebs_volume.nfs.type == "gp3" && aws_ebs_volume.nfs.encrypted == false
    error_message = "nfs (vol1) doesn't match legacy size/type/encryption"
  }
  assert {
    condition     = aws_volume_attachment.nfs.device_name == "/dev/sdb"
    error_message = "nfs volume must attach at /dev/sdb (legacy device name)"
  }
  assert {
    condition     = length(aws_ebs_volume.postgresql) == 1 && aws_ebs_volume.postgresql[0].size == 200
    error_message = "postgresql (vol2) should be created with size 200 when nginx_node_ebs_volume_size_2 > 0"
  }
  assert {
    condition     = aws_volume_attachment.postgresql[0].device_name == "/dev/sdc"
    error_message = "postgresql volume must attach at /dev/sdc (legacy device name)"
  }
  assert {
    condition     = length(aws_ebs_volume.activemq) == 1 && aws_ebs_volume.activemq[0].size == 30
    error_message = "activemq (vol3) should be created with size 30 when enabled and nginx_node_ebs_volume_size_3 > 0"
  }
  assert {
    condition     = aws_volume_attachment.activemq[0].device_name == "/dev/sdd"
    error_message = "activemq volume must attach at /dev/sdd (legacy device name)"
  }
  assert {
    condition     = alltrue([aws_ebs_volume.nfs.availability_zone == "ap-south-1a"])
    error_message = "nfs volume must be created in the nginx instance's actual AZ"
  }
}

run "esignet_standalone_shape_only_nfs_volume" {
  command = plan

  # Matches the esignet-standalone profile: no postgresql, no activemq volume.
  variables {
    nginx_node_ebs_volume_size_2 = 0
    nginx_node_ebs_volume_size_3 = 0
    enable_activemq_setup        = false
  }

  assert {
    condition     = length(aws_ebs_volume.postgresql) == 0
    error_message = "postgresql volume must NOT be created when nginx_node_ebs_volume_size_2 == 0 (legacy: conditional list entry omitted)"
  }
  assert {
    condition     = length(aws_ebs_volume.activemq) == 0
    error_message = "activemq volume must NOT be created when enable_activemq_setup == false"
  }
  assert {
    condition     = length(aws_volume_attachment.postgresql) == 0 && length(aws_volume_attachment.activemq) == 0
    error_message = "no attachment should exist for volumes that weren't created"
  }
  assert {
    condition     = aws_ebs_volume.nfs.size == 300
    error_message = "nfs volume must always be created regardless of postgresql/activemq settings"
  }
}

run "activemq_volume_gated_by_both_conditions_independently" {
  command = plan

  # Legacy quirk (preserved exactly): activemq's volume needs BOTH
  # enable_activemq_setup AND nginx_node_ebs_volume_size_3 > 0 — either one
  # alone must not create it. This run proves the flag-true/size-zero case.
  variables {
    nginx_node_ebs_volume_size_2 = 0
    nginx_node_ebs_volume_size_3 = 0
    enable_activemq_setup        = true
  }

  assert {
    condition     = length(aws_ebs_volume.activemq) == 0
    error_message = "activemq volume must NOT be created when enable_activemq_setup=true but size_3=0 — both conditions are required, not just one"
  }
}
