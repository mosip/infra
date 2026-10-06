# Standalone VM

Create servers outside the cluster — a bastion host, a tools box, a reporting database — each
with **its own security group and IAM policy**, in one run. This is the `vm` component; it has
its own state and is never part of `COMPONENT=all`.

## 1. Describe the groups

Edit `profiles/<profile>/aws/vm.tfvars`. Each entry is one workload:

```hcl
instance_groups = {
  bastion = {
    instance_type           = "t3a.small"
    subnet                  = "public"                       # public | private (default)
    ingress                 = [{ port = 22, cidrs = ["203.0.113.0/24"], description = "office SSH" }]
    iam_managed_policy_arns = ["arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"]
  }

  reports-db = {
    count          = 1
    instance_type  = "t3a.large"
    root_volume_gb = 50
    ingress        = [{ port = 5432, source_groups = ["bastion"] }]   # only from the bastion
    iam_policy_json = <<-JSON
      { "Version": "2012-10-17",
        "Statement": [{ "Effect": "Allow", "Action": ["s3:GetObject", "s3:PutObject"],
                        "Resource": "arn:aws:s3:::reports-backup/*" }] }
    JSON
  }
}
```

| Field | Default | |
|---|---|---|
| `instance_type` | required | |
| `count` | `1` | 0–20 |
| `subnet` | `private` | `public` gets a public IP |
| `ami`, `key_name` | from `common.tfvars` | |
| `root_volume_gb` | `20` | encrypted |
| `ingress` | `[]` | `port`, `to_port`, `protocol`, `cidrs` and/or `source_groups` |
| `egress_all` | `true` | |
| `iam_managed_policy_arns` / `iam_policy_json` | none | a role is created only when set |
| `user_data`, `tags` | — | |

## 2. Apply

Run **terraform plan / apply** with `COMPONENT=vm`, your `PROFILE`, `TERRAFORM_APPLY` ✅.

## Guardrails

- IMDSv2 required, root volumes encrypted.
- SSH from `0.0.0.0/0` is rejected unless `allow_ssh_from_anywhere = true`.
- Group names can't be `nginx`, `control-plane`, `etcd` or `worker` (reserved for the cluster).
- Every resource is tagged `Cluster=<cluster_name>`, `Role=<group>` — the DNS component's
  `extra_records` can point names at them.

## Remove

**terraform destroy** with `COMPONENT=vm` (also included in `COMPONENT=all`).
