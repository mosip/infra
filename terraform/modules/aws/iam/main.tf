terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.48.0"
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
  # Record changes only in the zones certbot needs for the DNS-01 challenge.
  # ListHostedZones / GetChange can't be scoped to a zone, so they stay on *.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ChangeRecordsInCertZones"
        Effect   = "Allow"
        Action   = ["route53:ChangeResourceRecordSets"]
        Resource = [for id in var.route53_zone_ids : "arn:aws:route53:::hostedzone/${id}"]
      },
      {
        Sid      = "FindZonesAndPollChanges"
        Effect   = "Allow"
        Action   = ["route53:ListHostedZones", "route53:GetChange"]
        Resource = "*"
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "certbot_policy_attachment" {
  role       = aws_iam_role.certbot_role.name
  policy_arn = aws_iam_policy.certbot_policy.arn
}

# Created before compute (legacy order: IAM, then EC2). The compute root finds
# this profile by name and sets it on the nginx instance at creation, so no
# post-creation association is needed.
resource "aws_iam_instance_profile" "certbot_profile" {
  name = "${var.cluster_name}-certbot-instance-profile"
  role = aws_iam_role.certbot_role.name
}
