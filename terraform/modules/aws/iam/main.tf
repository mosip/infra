terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.48.0"
    }
    null = {
      source = "hashicorp/null"
    }
  }
}

resource "aws_iam_role" "certbot_role" {
  name = "${var.cluster_name}-certbot-route53-role"
  tags = {
    Name    = "${var.cluster_name}-certbot-route53-role"
    Cluster = var.cluster_name
  }
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_policy" "certbot_policy" {
  name = "${var.cluster_name}-certbot-route53-policy"
  tags = {
    Name    = "${var.cluster_name}-certbot-route53-policy"
    Cluster = var.cluster_name
  }
  description = "Allow Certbot to modify Route 53 records"
  policy      = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "route53:ListHostedZones",
        "route53:GetChange",
        "route53:ChangeResourceRecordSets"
      ],
      "Resource": "*"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "certbot_policy_attachment" {
  role       = aws_iam_role.certbot_role.name
  policy_arn = aws_iam_policy.certbot_policy.arn
}

resource "aws_iam_instance_profile" "certbot_profile" {
  name = "${var.cluster_name}-certbot-instance-profile"
  role = aws_iam_role.certbot_role.name
}

# Attached post-creation, keyed off the instance ID discovered by tag — #275's
# ec2 root creates the bare instance with no iam_instance_profile argument at
# all. The hashicorp/aws provider has no resource type for associating an
# instance profile with an already-existing instance (verified — there is no
# "aws_iam_instance_profile_association"), so this is the one place a
# local-exec is the correct tool: a single, idempotent AWS control-plane API
# call with no Terraform-native resource for it, not procedural host
# configuration (which is what CLAUDE.md's Ansible-unwrap decision actually
# objects to).
resource "null_resource" "attach_certbot_profile" {
  triggers = {
    instance_id     = var.nginx_instance_id
    instance_profile = aws_iam_instance_profile.certbot_profile.name
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      existing=$(aws ec2 describe-iam-instance-profile-associations \
        --filters "Name=instance-id,Values=${var.nginx_instance_id}" "Name=state,Values=associating,associated" \
        --query "IamInstanceProfileAssociations[0].AssociationId" --output text)
      if [ "$existing" = "None" ] || [ -z "$existing" ]; then
        aws ec2 associate-iam-instance-profile \
          --instance-id "${var.nginx_instance_id}" \
          --iam-instance-profile Name="${aws_iam_instance_profile.certbot_profile.name}"
      else
        echo "Instance profile already associated ($existing) — skipping"
      fi
    EOT
  }

  depends_on = [aws_iam_role_policy_attachment.certbot_policy_attachment]
}
