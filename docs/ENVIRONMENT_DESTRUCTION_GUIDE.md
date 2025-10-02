# Environment Destruction Guide

This guide provides comprehensive instructions for safely destroying and decommissioning MOSIP environments. Follow these steps carefully to ensure complete cleanup and avoid unexpected costs.

## Table of Contents

1. [When to Destroy an Environment](#when-to-destroy-an-environment)
2. [Pre-Destruction Checklist](#pre-destruction-checklist)
3. [Destruction Order (Critical!)](#destruction-order-critical)
4. [Step-by-Step Destruction](#step-by-step-destruction)
5. [Verification and Cleanup](#verification-and-cleanup)
6. [Cost Monitoring](#cost-monitoring)

---

## When to Destroy an Environment

### Valid Reasons to Destroy

✅ **Development/Testing environments**
- No longer needed after testing complete
- Recreating from scratch with new configuration
- Cost optimization during non-working hours

✅ **Temporary deployments**
- Demo environments after presentation
- Training environments after session ends
- Proof-of-concept completed

✅ **Failed deployments**
- Major configuration errors requiring restart
- Corrupted state that can't be recovered

✅ **Cost management**
- Shutting down unused environments
- Scaling down during off-hours

### Think Twice Before Destroying

❌ **Production environments**
- Contains live user data
- Active identity records
- Operational identity services

❌ **Environments with valuable data**
- Databases with test data you might need
- Configurations you haven't backed up
- Logs needed for troubleshooting

---

## Pre-Destruction Checklist

### Before Destroying ANY Environment

#### 1. Backup Critical Data

```bash
# Backup PostgreSQL databases
kubectl exec -n postgres postgres-0 -- pg_dumpall -U postgres > mosip_backup_$(date +%Y%m%d).sql

# Backup MinIO object storage
mc alias set mosip https://minio.your-domain.net minioadmin minioadmin
mc mirror mosip/mosip ./minio-backup/

# Backup Keycloak realm configurations
kubectl exec -n keycloak keycloak-0 -- /opt/jboss/keycloak/bin/standalone.sh \
 -Djboss.socket.binding.port-offset=100 -Dkeycloak.migration.action=export \
 -Dkeycloak.migration.provider=singleFile \
 -Dkeycloak.migration.file=/tmp/keycloak-export.json
```

#### 2. Export Configurations

```bash
# Export Terraform state (if using local backend)
cd terraform/implementations/aws/infra/
tar -czf terraform-state-backup-$(date +%Y%m%d).tar.gz terraform.tfstate*

# Export Kubernetes configurations
kubectl get all --all-namespaces -o yaml > k8s-resources-backup.yaml

# Export secrets (be careful with these!)
kubectl get secrets --all-namespaces -o yaml > k8s-secrets-backup.yaml
# Store securely, contains sensitive data!
```

#### 3. Document Current State

Create a destruction log:

```bash
cat > destruction-log-$(date +%Y%m%d).txt << EOF
Environment Destruction Log
Date: $(date)
Cluster Name: <your-cluster-name>
Domain: <your-domain>
Reason: <why-destroying>

AWS Resources:
- VPC ID: <vpc-id>
- Cluster Name: <cluster-name>
- Region: <region>

Backups Taken:
- [ ] PostgreSQL databases
- [ ] MinIO storage
- [ ] Keycloak configurations
- [ ] Terraform state
- [ ] Kubernetes configs

Destroyed By: <your-name>
EOF
```

#### 4. Notify Stakeholders

- Inform team members
- Update deployment status
- Document in project management tools

#### 5. Double-Check Environment

```bash
# Verify you're destroying the correct environment!
kubectl config current-context
terraform workspace show # If using workspaces

# List EC2 instances to confirm
aws ec2 describe-instances \
 --filters "Name=tag:Environment,Values=<your-env-name>" \
 --query 'Reservations[].Instances[].[InstanceId,Tags[?Key==`Name`].Value|[0],State.Name]' \
 --output table
```

---

## Destruction Order (Critical!)

**IMPORTANT**: Destroy in reverse order of deployment to avoid orphaned resources and dependency issues.

```
Destruction Order (Reverse of Deployment):

5. Test Rigs ← Destroy FIRST
4. MOSIP Services ← Destroy SECOND
3. External Services ← Destroy THIRD
2. Prerequisites ← Destroy FOURTH
1. Infrastructure ← Destroy FIFTH (Kubernetes cluster)
0. Base Infrastructure ← Destroy LAST (VPC, networking)
```

**Why this order matters:**
- Applications depend on infrastructure
- Destroying infrastructure first leaves orphaned resources
- Proper order ensures clean deletion of all dependencies

---

## Step-by-Step Destruction

### Phase 1: Destroy Helmsman Deployments

#### Step 1: Destroy Test Rigs (Optional, if deployed)

**Time Required**: 5-10 minutes

```bash
# Option A: Using Helmsman (Recommended)
cd Helmsman/
helmsman --destroy -f dsf/testrigs-dsf.yaml

# Option B: Using Helm directly
helm list -n apitestrig
helm uninstall <release-name> -n apitestrig

helm list -n dsltestrig
helm uninstall <release-name> -n dsltestrig

helm list -n uitestrig
helm uninstall <release-name> -n uitestrig

# Option C: Delete namespaces entirely
kubectl delete namespace apitestrig
kubectl delete namespace dsltestrig
kubectl delete namespace uitestrig
```

**Verify deletion:**
```bash
kubectl get namespaces | grep testrig
# Should return nothing
```

---

#### Step 2: Destroy MOSIP Services

**Time Required**: 10-20 minutes

```bash
# Option A: Using Helmsman (Recommended)
cd Helmsman/
helmsman --destroy -f dsf/mosip-dsf.yaml

# Option B: Delete namespace with all resources
kubectl delete namespace mosip

# Watch deletion progress
kubectl get namespace mosip -w
# Wait until namespace is fully deleted
```

**Verify deletion:**
```bash
kubectl get all -n mosip
# Should return "No resources found"

kubectl get pvc -n mosip
# Should return "No resources found"
```

---

#### Step 3: Destroy External Dependencies

**Time Required**: 10-20 minutes

```bash
# Option A: Using Helmsman (Recommended)
cd Helmsman/
helmsman --destroy -f dsf/external-dsf.yaml

# Option B: Delete namespaces one by one
kubectl delete namespace postgres
kubectl delete namespace keycloak
kubectl delete namespace minio
kubectl delete namespace kafka
kubectl delete namespace activemq

# Watch for completion
watch kubectl get namespaces
```

**Verify deletion:**
```bash
kubectl get pods --all-namespaces | grep -E "postgres|keycloak|minio|kafka|activemq"
# Should return nothing
```

**Important: Persistent Volume Claims**
```bash
# PVCs may not be deleted automatically
# List all PVCs
kubectl get pvc --all-namespaces

# Delete manually if they exist
kubectl delete pvc --all -n postgres
kubectl delete pvc --all -n minio
kubectl delete pvc --all -n kafka
```

---

#### Step 4: Destroy Prerequisites

**Time Required**: 5-10 minutes

```bash
# Option A: Using Helmsman (Recommended)
cd Helmsman/
helmsman --destroy -f dsf/prereq-dsf.yaml

# Option B: Delete monitoring and Istio
kubectl delete namespace cattle-monitoring-system
kubectl delete namespace cattle-logging-system
kubectl delete namespace istio-system
kubectl delete namespace istio-operator

# Watch deletion
watch kubectl get namespaces
```

**Verify deletion:**
```bash
kubectl get namespaces | grep -E "cattle|istio"
# Should return nothing
```

---

### Phase 2: Destroy Terraform Infrastructure

#### Step 5: Destroy Main Infrastructure (Kubernetes Cluster)

**Time Required**: 15-30 minutes

##### Option A: Using GitHub Actions (Recommended)

1. **Navigate to GitHub Actions**
 ```
 Repository → Actions → Terraform Infrastructure Destroy
 ```

2. **Run Workflow**
 ```
 Click: "Run workflow"
 
 Parameters:
 - Branch: release-0.1.0 (your deployment branch)
 - Cloud Provider: aws
 - Component: infra
 - Backend: local (or s3, match your deployment)
 ```

3. **Monitor Progress**
 - Watch workflow logs in real-time
 - Destruction takes 15-30 minutes
 - Verify successful completion

##### Option B: Using Terraform CLI Locally

**Prerequisites:**
- WireGuard VPN active
- AWS credentials configured
- Terraform state accessible

```bash
# Navigate to infra directory
cd terraform/implementations/aws/infra/

# Verify Terraform state
terraform state list

# Preview destruction
terraform plan -destroy

# Destroy infrastructure
terraform destroy -auto-approve

# Watch for completion
# This will delete:
# - Kubernetes cluster (RKE2)
# - EC2 instances (control plane, workers)
# - Load balancer (nginx)
# - PostgreSQL (if deployed via Terraform)
# - Security groups
# - Network interfaces
# - EBS volumes
```

**Verify deletion in AWS Console:**
```
AWS Console → EC2 → Instances
Look for: Cluster name tag
Status: Should all be "terminated"
```

---

#### Step 6: Destroy Observability Infrastructure (If deployed)

**Time Required**: 10-20 minutes

##### Using GitHub Actions

```
Actions → Terraform Observability Infrastructure Destroy
Parameters:
- Component: observ-infra
- Others: same as infra destroy
```

##### Using Terraform CLI

```bash
cd terraform/observ-infra/aws/

terraform plan -destroy
terraform destroy -auto-approve
```

---

#### Step 7: Destroy Base Infrastructure (VPC, Networking)

**Time Required**: 10-15 minutes

**DESTROY THIS LAST!** Base infrastructure includes VPC and networking used by all other resources.

##### Using GitHub Actions

```
Actions → Terraform Base Infrastructure Destroy
Parameters:
- Component: base-infra
- Others: same as previous destroys
```

##### Using Terraform CLI

```bash
cd terraform/base-infra/aws/

# List resources to be destroyed
terraform state list

# Preview destruction
terraform plan -destroy

# Destroy base infrastructure
terraform destroy -auto-approve

# This will delete:
# - VPC
# - Subnets
# - Internet Gateway
# - NAT Gateway
# - Route Tables
# - Security Groups
# - Jump Server
# - WireGuard VPN
# - Elastic IPs
```

---

### Phase 3: Manual Cleanup (If Needed)

#### Check for Orphaned Resources

Sometimes resources aren't fully destroyed due to dependencies or errors.

##### 1. Check EC2 Instances

```bash
# List instances by cluster tag
aws ec2 describe-instances \
 --filters "Name=tag:kubernetes.io/cluster/<cluster-name>,Values=owned" \
 --query 'Reservations[].Instances[].[InstanceId,State.Name,Tags[?Key==`Name`].Value|[0]]' \
 --output table

# Terminate any remaining instances
aws ec2 terminate-instances --instance-ids <instance-id>
```

##### 2. Check Load Balancers

```bash
# List load balancers
aws elbv2 describe-load-balancers --query 'LoadBalancers[].[LoadBalancerName,LoadBalancerArn]'

# Delete if any exist
aws elbv2 delete-load-balancer --load-balancer-arn <arn>
```

##### 3. Check Security Groups

```bash
# List security groups in VPC
aws ec2 describe-security-groups \
 --filters "Name=vpc-id,Values=<vpc-id>" \
 --query 'SecurityGroups[].[GroupId,GroupName]'

# Delete security groups (may need to delete dependencies first)
aws ec2 delete-security-group --group-id <sg-id>
```

##### 4. Check Network Interfaces

```bash
# List network interfaces
aws ec2 describe-network-interfaces \
 --filters "Name=vpc-id,Values=<vpc-id>" \
 --query 'NetworkInterfaces[].[NetworkInterfaceId,Status]'

# Detach and delete if needed
aws ec2 delete-network-interface --network-interface-id <eni-id>
```

##### 5. Check EBS Volumes

```bash
# List volumes
aws ec2 describe-volumes \
 --filters "Name=tag:kubernetes.io/cluster/<cluster-name>,Values=owned" \
 --query 'Volumes[].[VolumeId,State,Size]'

# Delete available volumes
aws ec2 delete-volume --volume-id <vol-id>
```

##### 6. Check Elastic IPs

```bash
# List Elastic IPs
aws ec2 describe-addresses --query 'Addresses[].[PublicIp,AllocationId,AssociationId]'

# Release unassociated Elastic IPs
aws ec2 release-address --allocation-id <eipalloc-id>
```

##### 7. Check Route 53 Records

```bash
# List DNS records
aws route53 list-resource-record-sets \
 --hosted-zone-id <zone-id> \
 --query 'ResourceRecordSets[?Type==`A`].[Name,Type,ResourceRecords]'

# Delete MOSIP-related records manually via AWS Console
# Go to Route 53 → Hosted Zones → Your zone → Delete records
```

##### 8. Check S3 Buckets (If using S3 backend)

```bash
# List S3 buckets
aws s3 ls | grep -i mosip

# Delete bucket and contents (CAREFUL - THIS IS PERMANENT!)
aws s3 rb s3://<bucket-name> --force
```

---

## Verification and Cleanup

### Final Verification Checklist

After completing all destruction steps, verify nothing remains:

#### AWS Resources

```bash
# Check for any remaining instances
aws ec2 describe-instances \
 --filters "Name=tag:Environment,Values=<env-name>" \
 --query 'Reservations[].Instances[?State.Name!=`terminated`].[InstanceId,State.Name]'

# Should return empty

# Check for VPCs
aws ec2 describe-vpcs --query 'Vpcs[?Tags[?Key==`Name` && contains(Value, `mosip`)]].[VpcId,Tags]'

# Should return empty (or only non-MOSIP VPCs)

# Check for volumes
aws ec2 describe-volumes \
 --filters "Name=status,Values=available" \
 --query 'Volumes[?Tags[?Key==`Environment` && Value==`<env-name>`]].[VolumeId,State]'

# Should return empty
```

#### GitHub Cleanup

```bash
# Optional: Clean up environment secrets (if no longer needed)
# Go to: Settings → Environments → Delete environment

# Optional: Archive workflow runs
# Go to: Actions → Select old runs → Delete workflow runs
```

#### Local Cleanup

```bash
# Remove local Terraform state (if using local backend and no longer needed)
rm -rf terraform/implementations/aws/*/terraform.tfstate*
rm -rf terraform/implementations/aws/*/.terraform/

# Remove backed-up kubeconfig
rm ~/.kube/config-<cluster-name>

# Remove WireGuard configs
# On Linux
sudo rm /etc/wireguard/wg-mosip.conf
sudo wg-quick down wg-mosip

# On Mac
# Remove config from WireGuard app

# On Windows
# Remove tunnel from WireGuard app
```

---

## Cost Monitoring

### Monitor AWS Costs After Destruction

#### Immediate Check (5 minutes after destruction)

```bash
# Check for running instances
aws ec2 describe-instances \
 --filters "Name=instance-state-name,Values=running" \
 --query 'Reservations[].Instances[].[InstanceId,InstanceType,LaunchTime]'

# If any instances are running that shouldn't be, investigate immediately
```

#### Daily Cost Monitoring (First 3 days)

```
1. Log into AWS Console
2. Go to Cost Explorer or Billing Dashboard
3. Check daily costs
4. Look for unexpected charges

Expected cost reduction:
- Day 1: 50-70% reduction (some hourly services still billing)
- Day 2: 80-90% reduction 
- Day 3+: 95%+ reduction (only long-term resources like S3, Route53)
```

#### What Costs Remain After Destruction

**Normal remaining costs:**
- ✅ Route 53 hosted zone: ~$0.50/month
- ✅ S3 buckets (if keeping backups): Variable
- ✅ Elastic IPs (if not released): $0.005/hour per IP
- ✅ EBS snapshots (if created): Variable

**Unexpected costs to investigate:**
- ❌ Running EC2 instances
- ❌ Load balancers still active
- ❌ EBS volumes not deleted
- ❌ NAT Gateways still running

---

## Troubleshooting Destruction Issues

### Issue 1: Terraform Destroy Fails with Dependency Errors

**Symptom:**
```
Error: cannot destroy X because Y depends on it
```

**Solution:**

```bash
# Option A: Destroy resources in specific order
terraform destroy -target=<dependent-resource>
terraform destroy -target=<main-resource>

# Option B: Force resource removal from state (use carefully!)
terraform state rm <resource-name>

# Option C: Manual deletion in AWS Console, then clean state
# Delete resource in AWS Console
terraform refresh
terraform state rm <resource-name>
```

---

### Issue 2: Namespace Stuck in "Terminating" State

**Symptom:**
```bash
kubectl get namespace
NAME STATUS AGE
mosip Terminating 30m # Stuck!
```

**Solution:**

```bash
# Method 1: Check for finalizers
kubectl get namespace mosip -o json | jq '.spec.finalizers'

# Remove finalizers
kubectl patch namespace mosip -p '{"spec":{"finalizers":[]}}' --type=merge

# Method 2: Force delete (if above doesn't work)
kubectl delete namespace mosip --grace-period=0 --force

# Method 3: Manual cleanup of stuck resources
kubectl api-resources --verbs=list --namespaced -o name \
 | xargs -n 1 kubectl get --show-kind --ignore-not-found -n mosip
```

---

### Issue 3: PVCs Not Deleting

**Symptom:**
```bash
kubectl get pvc -n postgres
NAME STATUS AGE
data-pvc Terminating 1h # Stuck!
```

**Solution:**

```bash
# Check what's using the PVC
kubectl describe pvc data-pvc -n postgres

# Remove protection
kubectl patch pvc data-pvc -n postgres -p '{"metadata":{"finalizers":null}}'

# If EBS volume stuck, delete in AWS
aws ec2 describe-volumes --filters "Name=tag:kubernetes.io/created-for/pvc/name,Values=data-pvc"
aws ec2 delete-volume --volume-id <vol-id>
```

---

### Issue 4: Can't Delete VPC Due to Dependencies

**Symptom:**
```
Error: DependencyViolation - The vpc 'vpc-xxx' has dependencies and cannot be deleted
```

**Solution:**

```bash
# 1. Check and delete network interfaces
aws ec2 describe-network-interfaces --filters "Name=vpc-id,Values=<vpc-id>"
# Delete each: aws ec2 delete-network-interface --network-interface-id <eni-id>

# 2. Check and delete security groups
aws ec2 describe-security-groups --filters "Name=vpc-id,Values=<vpc-id>"
# Delete each: aws ec2 delete-security-group --group-id <sg-id>

# 3. Check and delete subnets
aws ec2 describe-subnets --filters "Name=vpc-id,Values=<vpc-id>"
# Delete each: aws ec2 delete-subnet --subnet-id <subnet-id>

# 4. Check and delete internet gateways
aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=<vpc-id>"
# Detach: aws ec2 detach-internet-gateway --internet-gateway-id <igw-id> --vpc-id <vpc-id>
# Delete: aws ec2 delete-internet-gateway --internet-gateway-id <igw-id>

# 5. Try VPC deletion again
aws ec2 delete-vpc --vpc-id <vpc-id>
```

---

## Destruction Time Estimates

| Phase | Component | Time Required |
|-------|-----------|---------------|
| **Phase 1** | Test Rigs | 5-10 minutes |
| | MOSIP Services | 10-20 minutes |
| | External Services | 10-20 minutes |
| | Prerequisites | 5-10 minutes |
| **Phase 2** | Main Infrastructure | 15-30 minutes |
| | Observability Infra | 10-20 minutes |
| | Base Infrastructure | 10-15 minutes |
| **Phase 3** | Manual Cleanup | 10-30 minutes |
| **Total** | Complete Destruction | **1-2 hours** |

---

## Quick Destruction Script (Use with Caution!)

**WARNING**: This script will destroy EVERYTHING. Use only if you're absolutely sure!

```bash
#!/bin/bash
# complete-destruction.sh
# USE WITH EXTREME CAUTION!

set -e

CLUSTER_NAME="your-cluster-name"
ENV_NAME="your-env-name"

echo " WARNING: This will destroy the entire $ENV_NAME environment!"
echo "Press Ctrl+C to cancel, or press Enter to continue..."
read

echo "Step 1/7: Destroying Test Rigs..."
kubectl delete namespace apitestrig dsltestrig uitestrig --ignore-not-found

echo "Step 2/7: Destroying MOSIP Services..."
kubectl delete namespace mosip --ignore-not-found

echo "Step 3/7: Destroying External Services..."
kubectl delete namespace postgres keycloak minio kafka activemq --ignore-not-found

echo "Step 4/7: Destroying Prerequisites..."
kubectl delete namespace cattle-monitoring-system cattle-logging-system istio-system --ignore-not-found

echo "Step 5/7: Waiting for namespace deletion..."
sleep 60

echo "Step 6/7: Destroying Kubernetes Infrastructure..."
cd terraform/implementations/aws/infra/
terraform destroy -auto-approve

echo "Step 7/7: Destroying Base Infrastructure..."
cd ../../base-infra/aws/
terraform destroy -auto-approve

echo "✅ Destruction complete!"
echo "Please verify manually that all resources are deleted."
```

---

## Recovery After Accidental Destruction

### If You Accidentally Destroyed Production

1. **Stop immediately** - Don't panic, assess damage
2. **Check backups** - Locate most recent backups
3. **Restore from backup**:

```bash
# Restore PostgreSQL
kubectl exec -n postgres postgres-0 -- psql -U postgres < mosip_backup_YYYYMMDD.sql

# Restore MinIO
mc mirror ./minio-backup/ mosip/mosip

# Restore Keycloak
# Re-import realm configuration through Keycloak admin UI
```

4. **Document incident** - Write post-mortem
5. **Implement safeguards**:
 - Add production environment protection in GitHub
 - Require manual approval for destruction workflows
 - Regular backup schedules

---

## Best Practices

### Protection Mechanisms

1. **GitHub Environment Protection**
 ```
 Settings → Environments → Production → Protection rules
 - Required reviewers: 2
 - Wait timer: 5 minutes
 - Restrict to specific branches
 ```

2. **Terraform State Locking**
 ```hcl
 # Use S3 backend with DynamoDB locking for production
 backend "s3" {
 bucket = "terraform-state"
 key = "prod/terraform.tfstate"
 region = "us-west-2"
 dynamodb_table = "terraform-locks"
 }
 ```

3. **AWS Resource Tags**
 ```hcl
 tags = {
 Environment = "production"
 Protected = "true"
 Team = "ops"
 }
 ```

4. **Deletion Protection**
 ```hcl
 # Enable termination protection on critical resources
 resource "aws_instance" "k8s_master" {
 disable_api_termination = true # For production only
 }
 ```

---

## Need Help?

- **Before destroying production**: Get team approval
- **Stuck during destruction**: Check troubleshooting section
- **Unexpected costs after destruction**: Review Cost Monitoring section
- **Need to recover**: See Recovery section

---

**Navigation**: [Back to Main README](../README.md) | [View All Docs](.)
