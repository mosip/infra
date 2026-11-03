# Things to Know While Working with Terraform Workflows

## GitHub Actions Workflow Parameters Reference

> **Visual Guide:** See [Workflow Guide - Workflow Parameters Explained](WORKFLOW_GUIDE.md#workflow-parameters-explained) for detailed explanations with examples!

## Common Parameters for All Terraform Workflows

- **`CLOUD_PROVIDER`**: `aws` | `azure` | `gcp` (cloud platform selection)
  - **Choose**: `aws` — Azure/GCP only have `base-infra`
  - Data-centre VMs need no Terraform at all: see [Deployment sequence](DEPLOYMENT_SEQUENCE.md#data-centre)
- **`COMPONENT`**: what to run — each component is its own Terraform root with its own state
  - **all**: every component in order, then `configure`. With `TERRAFORM_APPLY` unchecked it plans every component of an **existing** environment and skips `configure`; a new environment needs apply (each component looks up what the earlier ones created in AWS)
  - **security** → **iam** → **compute** → **storage** → **dns**: one component (day-2 changes, e.g. `dns` to update only Route53, `compute` to resize or add nodes)
  - **configure**: Ansible only (TLS + nginx, RKE2, Rancher import, NFS, PostgreSQL, ActiveMQ, Rancher/Keycloak)
  - **vm**: standalone EC2 instances with their own security group and IAM (`profiles/<profile>/aws/vm.tfvars`) — not part of `all`
  - **base-infra**: VPC, networking, jump server, WireGuard (deploy FIRST, once)
- **`PROFILE`**: deployment shape — see [Profiles](PROFILES.md)

  | Profile | Values | Cluster size | Use for |
  |---------|--------|--------------|---------|
  | `mosip` | `profiles/mosip/` | 7 nodes (3/3/1) | Full MOSIP platform |
  | `esignet-standalone` | `profiles/esignet-standalone/` | 4 nodes (1/1/2) | eSignet standalone |
  | `observ` | `profiles/observ/` | 1 node | Rancher UI + Keycloak (optional) |

  - The profile decides the tfvars (`profiles/<profile>/aws/*.tfvars`), the Layer-3 components and the DNS subdomains
  - State is scoped per component and profile, so profiles coexist on the same branch
- **`SSH_PRIVATE_KEY`**: GitHub secret name containing SSH private key for instance access
  - Must match `ssh_key_name` in `profiles/<profile>/aws/common.tfvars`
  - [How to create SSH keys](SECRET_GENERATION_GUIDE.md#1-ssh-keys)
- **`TERRAFORM_APPLY`**: Checkbox ☐ or ✅ (apply changes or plan-only mode)
  - ☐ **Unchecked** = Dry run (preview only, **no infrastructure changes**)
  - ✅ **Checked** = Apply (actually creates infrastructure, **real changes**)
- **Visual Explanation:**

```
☐ Unchecked → Terraform Plan Only
→ Shows: "Will create 25 resources"
→ Does: Nothing (preview only)
→ AWS: No changes made

✅ Checked → Terraform Apply
→ Shows: "Creating resources..."
→ Does: Creates actual infrastructure
→ AWS: Servers, networks, databases created
→ Cost: Billing starts
```

- **`DNS_PROVIDER`**: who creates the DNS records — `terraform-route53` (default, `dns` component), `godaddy` / `cloudflare` / `rfc2136` (Ansible, provider secrets), or `manual` ("no DNS yet": builds the cluster, skips TLS, the nginx proxy and the Rancher import, and prints the records to create)
- **`ENABLE_RANCHER_IMPORT`** / **`RANCHER_CLUSTER_NAME`** / **`PUBLISH_KUBECONFIG`** / **`GRANT_GROUP_ACCESS`**: register the cluster in the observ Rancher (needs `RANCHER_API_URL` + `RANCHER_API_TOKEN`), publish its kubeconfig as the `KUBECONFIG` environment secret, and grant team access
- **Relationship with Rancher Import:**

```
If COMPONENT = all/configure AND ENABLE_RANCHER_IMPORT = ✅
→ Infrastructure deployed AND cluster imported to Rancher UI (during configure)

If ENABLE_RANCHER_IMPORT = ☐
→ Infrastructure deployed but cluster runs standalone

If Terraform Apply = ☐ (unchecked - plan only)
→ Nothing is applied or committed, just shows plans
→ COMPONENT=all: every component planned in order (existing environment), configure skipped
→ Rancher Import setting is ignored
```

## Backend Configuration Options

- **`local`**: GPG-encrypted local state storage (recommended for development and small teams)
  - State files stored in repository with GPG encryption
  - No external dependencies required
  - Automatic encryption/decryption via GitHub Actions
  - **Best for**: Development, testing, small teams
  - **Requires**: GPG_PASSPHRASE secret
- **`remote`**: state in a cloud bucket (recommended for production and large teams)
  - Set **`REMOTE_BACKEND_CONFIG`**: `aws:<bucket_base_name>:<region>`, `azure:<resource_group>:<storage_account>:<container>` or `gcp:<bucket>` — the workflow creates the bucket if needed
  - Tick **`ENABLE_STATE_LOCKING`** for locking (DynamoDB on AWS)
  - State key per provider, component, profile and branch
  - **Best for**: Production, large teams, multiple environments

## Understanding Terraform Modes

Before running any Terraform workflow, understand these modes:

| Mode                                             | What It Does                                   | When to Use                                | Visual             |
| ------------------------------------------------ | ---------------------------------------------- | ------------------------------------------ | ------------------ |
| **Terraform Plan** (checkbox unchecked ☐) | Shows what WOULD happen without making changes | Testing configurations, previewing changes | ☐ Terraform apply |
| **Apply** (checkbox checked ✅)            | Actually creates/modifies infrastructure       | Real deployments, making actual changes    | ✅ Terraform apply |

**Tip**: Always run terraform plan first to preview changes, then run with apply checked to actually deploy!

## Best Practices

1. **Always Plan First**: Use unchecked mode (☐) to preview changes before applying
2. **Consistent Naming**: Ensure `ssh_key_name` (profiles/<profile>/aws/common.tfvars) matches the GitHub secret
3. **Secret Management**: Keep SSH private keys secure and never commit to repository
4. **Environment Isolation**: Use separate branches/environments for different deployments
5. **State Management**: Choose the backend (`local` vs `remote`) based on team size and requirements

## Troubleshooting Common Issues

### SSH Key Mismatch
**Error**: "Key pair 'xxx' does not exist"
**Solution**: Ensure `ssh_key_name` in `profiles/<profile>/aws/common.tfvars` matches the GitHub secret name exactly (case-sensitive)

### State Lock Issues
**Error**: "Error locking state: ConditionalCheckFailedException"
**Solution**: Wait for previous operations to complete, or manually unlock state if previous run was interrupted

### Permission Errors
**Error**: "UnauthorizedOperation: You are not authorized to perform this operation"
**Solution**: Verify AWS credentials have sufficient permissions for the resources being created

### Backend Configuration Errors
**Error**: "Backend configuration changed"
**Solution**: Run terraform init to reinitialize backend configuration

## Destroying

Use **Actions → terraform destroy** with the same `PROFILE`, `BACKEND_TYPE` and `SSH_PRIVATE_KEY`. `COMPONENT=all` destroys in reverse order (`dns → storage → compute → iam → security`, plus `vm` if it was applied); leave **`TERRAFORM_DESTROY`** unchecked for a `plan -destroy` preview. `base-infra` is destroyed separately and last. See the [Environment Destruction Guide](ENVIRONMENT_DESTRUCTION_GUIDE.md).
