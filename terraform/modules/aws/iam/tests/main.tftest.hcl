# Verifies the decoupled `iam` module's certbot IAM role/policy/profile
# match the legacy monolith's certbot-ssl-certgen.tf exactly (name patterns,
# tags, assume-role trust policy, Route53 permissions policy).
#
# Runs use command = plan with a mocked provider — no AWS credentials.

mock_provider "aws" {}

variables {
  cluster_name     = "testcluster"
  route53_zone_ids = ["Z0123456789ABCDEFGHI"]
}

run "certbot_role_matches_legacy_name_and_trust_policy" {
  command = plan

  assert {
    condition     = aws_iam_role.certbot_role.name == "testcluster-certbot-route53-role"
    error_message = "certbot role name doesn't match legacy's <cluster_name>-certbot-route53-role convention"
  }
  assert {
    condition     = aws_iam_role.certbot_role.tags.Name == "testcluster-certbot-route53-role" && aws_iam_role.certbot_role.tags.Cluster == "testcluster"
    error_message = "certbot role tags don't match legacy convention"
  }
  assert {
    condition     = can(jsondecode(aws_iam_role.certbot_role.assume_role_policy))
    error_message = "assume_role_policy must be valid JSON"
  }
  assert {
    condition     = jsondecode(aws_iam_role.certbot_role.assume_role_policy).Statement[0].Principal.Service == "ec2.amazonaws.com"
    error_message = "assume_role_policy must trust ec2.amazonaws.com (legacy: certbot-ssl-certgen.tf's assume_role_policy)"
  }
  assert {
    condition     = jsondecode(aws_iam_role.certbot_role.assume_role_policy).Statement[0].Action == "sts:AssumeRole"
    error_message = "assume_role_policy must allow sts:AssumeRole"
  }
}

run "certbot_policy_matches_legacy_route53_permissions" {
  command = plan

  assert {
    condition     = aws_iam_policy.certbot_policy.name == "testcluster-certbot-route53-policy"
    error_message = "certbot policy name doesn't match legacy's <cluster_name>-certbot-route53-policy convention"
  }
  assert {
    condition     = can(jsondecode(aws_iam_policy.certbot_policy.policy))
    error_message = "policy document must be valid JSON"
  }
  assert {
    condition = toset(flatten([for s in jsondecode(aws_iam_policy.certbot_policy.policy).Statement : s.Action])) == toset([
      "route53:ListHostedZones",
      "route53:GetChange",
      "route53:ChangeResourceRecordSets",
    ])
    error_message = "certbot policy must grant exactly the 3 legacy Route53 actions — ListHostedZones, GetChange, ChangeResourceRecordSets"
  }
  assert {
    condition     = alltrue([for s in jsondecode(aws_iam_policy.certbot_policy.policy).Statement : s.Effect == "Allow"])
    error_message = "certbot policy statements must be Allow, not Deny"
  }
}

run "record_changes_scoped_to_the_given_zones" {
  command = plan

  variables {
    route53_zone_ids = ["ZONEA00000000000000", "ZONEB00000000000000"]
  }

  assert {
    condition = [
      for s in jsondecode(aws_iam_policy.certbot_policy.policy).Statement : s.Resource
      if contains(flatten([s.Action]), "route53:ChangeResourceRecordSets")
      ][0] == [
      "arn:aws:route53:::hostedzone/ZONEA00000000000000",
      "arn:aws:route53:::hostedzone/ZONEB00000000000000",
    ]
    error_message = "ChangeResourceRecordSets must be limited to the listed zones, never *"
  }
}

run "zone_ids_are_required" {
  command = plan

  variables {
    route53_zone_ids = []
  }

  expect_failures = [var.route53_zone_ids]
}

run "role_policy_attachment_links_role_to_policy" {
  command = plan

  assert {
    condition     = aws_iam_role_policy_attachment.certbot_policy_attachment.role == "testcluster-certbot-route53-role"
    error_message = "policy attachment must reference the certbot role by name"
  }
}

run "instance_profile_matches_legacy_name_and_role" {
  command = plan

  assert {
    condition     = aws_iam_instance_profile.certbot_profile.name == "testcluster-certbot-instance-profile"
    error_message = "instance profile name doesn't match legacy's <cluster_name>-certbot-instance-profile convention"
  }
  assert {
    condition     = aws_iam_instance_profile.certbot_profile.role == "testcluster-certbot-route53-role"
    error_message = "instance profile must be built on the certbot role"
  }
}
