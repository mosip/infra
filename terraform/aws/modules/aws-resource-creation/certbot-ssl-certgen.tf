resource "aws_iam_role" "certbot_role" {
  name = "${var.CLUSTER_NAME}-certbot-route53-role"
  tags = {
    Name    = "${var.CLUSTER_NAME}-certbot-route53-role"
    Cluster = var.CLUSTER_NAME
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
  name = "${var.CLUSTER_NAME}-certbot-route53-policy"
  tags = {
    Name    = "${var.CLUSTER_NAME}-certbot-route53-policy"
    Cluster = var.CLUSTER_NAME
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
  name = "certbot-instance-profile"
  role = aws_iam_role.certbot_role.name
}