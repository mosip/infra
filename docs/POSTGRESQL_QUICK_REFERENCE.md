# PostgreSQL Configuration Quick Reference

## Quick Setup Guide

### **For Production/Staging (External PostgreSQL)**

1. **Configure Terraform variables:**
   ```hcl
   # terraform/implementations/aws/infra/aws.tfvars
   enable_postgresql_setup = true
   nginx_node_ebs_volume_size_2 = 200  # EBS volume size in GB
   postgresql_version = "15"           # PostgreSQL version
   postgresql_port = "5433"           # PostgreSQL port
   ```

2. **Update Helmsman DSF:**
   ```yaml
   # Helmsman/dsf/external-dsf.yaml
   apps:
     postgresql:
       enabled: false  # External PostgreSQL handled by Terraform
   ```

3. **Deploy via GitHub Actions:**
   - Actions → **Terraform Infrastructure**
   - Select your cloud provider
   - Run `apply`
   - PostgreSQL 15 will be automatically installed and configured

### **For Development/Testing (Container PostgreSQL)**

1. **Configure Terraform variables:**
   ```hcl
   # terraform/implementations/aws/infra/aws.tfvars
   enable_postgresql_setup = false
   nginx_node_ebs_volume_size_2 = 0    # No second EBS volume needed
   ```

2. **Update Helmsman DSF:**
   ```yaml
   # Helmsman/dsf/external-dsf.yaml
   apps:
     postgresql:
       enabled: true   # Container PostgreSQL via Kubernetes
   ```

3. **Deploy via GitHub Actions:**
   - Actions → **Terraform Infrastructure** (creates cluster only)
   - Actions → **Helmsman External Dependencies** (deploys PostgreSQL container)

## Configuration Reference

### **Terraform Variables**

| Variable | Type | Default | Description | Required When |
|----------|------|---------|-------------|---------------|
| `enable_postgresql_setup` | bool | `true` | Enable external PostgreSQL | Always |
| `nginx_node_ebs_volume_size_2` | number | `200` | EBS volume size (GB) | `enable_postgresql_setup = true` |
| `postgresql_version` | string | `"15"` | PostgreSQL version | `enable_postgresql_setup = true` |
| `postgresql_port` | string | `"5433"` | PostgreSQL port | `enable_postgresql_setup = true` |

### **Helmsman DSF Configuration**

| DSF File | Setting | Value | When To Use |
|----------|---------|--------|-------------|
| `external-dsf.yaml` | `postgresql.enabled` | `false` | External PostgreSQL (Terraform) |
| `external-dsf.yaml` | `postgresql.enabled` | `true` | Container PostgreSQL (Kubernetes) |

## Architecture Decision Tree

```
PostgreSQL Deployment Decision
├── Do you need persistent, production-ready PostgreSQL?
│   ├── YES → External PostgreSQL
│   │   ├── Set enable_postgresql_setup = true
│   │   ├── Configure EBS volume size
│   │   └── Terraform will handle installation
│   └── NO → Container PostgreSQL  
│       ├── Set enable_postgresql_setup = false
│       └── Helmsman will deploy container
```

## Common Configurations

### **Small Development Environment**
```hcl
enable_postgresql_setup = false
# PostgreSQL will run as Kubernetes container
# Good for: Development, testing, POCs
```

### **Production Environment**
```hcl
enable_postgresql_setup = true
nginx_node_ebs_volume_size_2 = 500  # 500GB for production data
postgresql_version = "15"
postgresql_port = "5433"
# PostgreSQL will be installed on dedicated node with persistent storage
# Good for: Production, staging, high-availability setups
```

### **Staging Environment** 
```hcl
enable_postgresql_setup = true
nginx_node_ebs_volume_size_2 = 200  # 200GB for staging data
postgresql_version = "15"
postgresql_port = "5433"
# Production-like setup with smaller storage
# Good for: Integration testing, pre-production validation
```

## Troubleshooting

**External PostgreSQL Setup Issues:**
1. `enable_postgresql_setup = true`
2. `nginx_node_ebs_volume_size_2 > 0` (required for external PostgreSQL)
3. Terraform logs in GitHub Actions for Ansible execution errors

**MOSIP Connection Issues:**
1. Helmsman DSF: `postgresql.enabled = false` (if using external)
2. PostgreSQL port configuration matches between Terraform and MOSIP
3. Network connectivity between MOSIP pods and PostgreSQL node

**Container PostgreSQL Issues:**
1. `enable_postgresql_setup = false`
2. Helmsman DSF: `postgresql.enabled = true`
3. Sufficient cluster resources for PostgreSQL container

## 📚 **Related Documentation**

- [Complete Deployment Flows](docs/UPDATED_DEPLOYMENT_FLOWS.md)
- [Architecture Diagrams](docs/_images/ARCHITECTURE_DIAGRAMS.md)  
- [Workflow Differences Summary](WORKFLOW_DIFFERENCES_SUMMARY.md)
- [Main README](README.md)

---

*Last Updated: August 2025 - Reflects integrated PostgreSQL management approach*
