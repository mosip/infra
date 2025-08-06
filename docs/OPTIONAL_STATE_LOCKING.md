# Optional Cloud-Agnostic State Locking

## Overview

Terraform state locking is now **optional** across all cloud providers in our infrastructure setup. Each provider handles state locking differently:

- **AWS**: Uses DynamoDB tables for distributed locking
- **Azure**: Uses built-in blob lease-based locking 
- **GCP**: Uses built-in object consistency and versioning

## When to Use Each Option

### 🔒 **With State Locking (Default - Recommended)**
- **Good for**: Production, team environments, CI/CD pipelines, all use cases
- **Pros**: Prevents state corruption from concurrent modifications
- **Cons**: Requires additional permissions/setup (AWS only)

### ✅ **Without State Locking (Manual Override)**
- **Good for**: Quick testing, single-user environments
- **Pros**: Simpler setup, no additional resources (AWS)
- **Cons**: No protection against concurrent Terraform runs (risk of state corruption)

## Provider-Specific Details

### AWS - DynamoDB Locking
- **Cost**: Essentially free (~$0.00-$0.04/month typical usage)
- **Setup**: Automatically creates DynamoDB table when enabled
- **IAM Requirements**: DynamoDB permissions in addition to S3

### Azure - Built-in Blob Locking  
- **Cost**: No additional cost (included with storage account)
- **Setup**: No additional resources required
- **Requirements**: Standard Azure Storage permissions

### GCP - Built-in Consistency
- **Cost**: No additional cost (included with Cloud Storage)
- **Setup**: Uses object versioning and consistency guarantees
- **Requirements**: Standard Cloud Storage permissions

## How to Enable/Disable

### GitHub Actions Workflow

Set the `ENABLE_STATE_LOCKING` input parameter:

```yaml
# Enable DynamoDB locking (DEFAULT - recommended for all environments)
ENABLE_STATE_LOCKING: true

# Disable DynamoDB locking (only if DynamoDB setup is not available)
ENABLE_STATE_LOCKING: false
```

### Manual Script Usage

```bash
# With DynamoDB locking
./setup-cloud-storage.sh \
  --provider aws \
  --config "aws:mybucket:us-east-1" \
  --branch main \
  --component infra \
  --enable-locking

# Without DynamoDB locking (default)
./setup-cloud-storage.sh \
  --provider aws \
  --config "aws:mybucket:us-east-1" \
  --branch main \
  --component infra
```

## What Gets Created

### Without Locking (ENABLE_STATE_LOCKING: false)
```
S3 Bucket: mybucket-infra-main
└── Terraform state files only
```

### With Locking (ENABLE_STATE_LOCKING: true - DEFAULT)  
```
S3 Bucket: mybucket-infra-main
└── Terraform state files

DynamoDB Table: terraform-state-lock-infra-main
└── State locking entries
```

## Generated Backend Configuration

### Without Locking
```hcl
terraform {
  backend "s3" {
    bucket = "mybucket-infra-main"
    key    = "aws-infra-main-terraform.tfstate"
    region = "us-east-1"
  }
}
```

### With Locking
```hcl
terraform {
  backend "s3" {
    bucket         = "mybucket-infra-main"
    key            = "aws-infra-main-terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-state-lock-infra-main"
    encrypt        = true
  }
}
```

## IAM Permissions Required

### For S3-Only (No Locking)
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket",
        "s3:GetObject", 
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:CreateBucket",
        "s3:HeadBucket",
        "s3:GetBucketVersioning",
        "s3:PutBucketVersioning",
        "s3:GetBucketEncryption",
        "s3:PutBucketEncryption",
        "s3:GetPublicAccessBlock",
        "s3:PutPublicAccessBlock"
      ],
      "Resource": [
        "arn:aws:s3:::*terraform*",
        "arn:aws:s3:::*terraform*/*"
      ]
    }
  ]
}
```

### For S3 + DynamoDB Locking
Add these additional permissions:
```json
{
  "Effect": "Allow", 
  "Action": [
    "dynamodb:DescribeTable",
    "dynamodb:CreateTable",
    "dynamodb:GetItem",
    "dynamodb:PutItem", 
    "dynamodb:DeleteItem"
  ],
  "Resource": [
    "arn:aws:dynamodb:*:*:table/terraform-state-lock-*"
  ]
}
```

## Cost Comparison

### S3 Only
- **S3 Storage**: ~$0.023/GB/month
- **S3 Requests**: Minimal cost
- **Total**: ~$1-5/month for typical usage

### S3 + DynamoDB
- **S3 Storage**: ~$0.023/GB/month
- **DynamoDB**: ~$0.25/month (5 RCU/WCU always free tier)
- **Total**: ~$1-5/month (virtually no additional cost)

## Recommendations

- **All Environments**: Use `ENABLE_STATE_LOCKING: true` (DEFAULT)
- **Quick Testing Only**: Use `ENABLE_STATE_LOCKING: false` (when DynamoDB setup not available)
- **Production**: Always use `ENABLE_STATE_LOCKING: true` 
- **Team Environments**: Always use `ENABLE_STATE_LOCKING: true`
- **CI/CD Pipelines**: Always use `ENABLE_STATE_LOCKING: true`

The cost difference is negligible, but the safety benefit is significant! The new default makes the system secure by default.
