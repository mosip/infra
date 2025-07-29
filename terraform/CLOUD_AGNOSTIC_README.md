# Cloud-Agnostic MOSIP Infrastructure

This Terraform configuration provides a cloud-agnostic │   │   ├── observ-infra/
│   │   │   ├── main.tf               # AWS observation implementation entry point
│   │   │   ├── variables.tf          # AWS observation variables
│   │   │   ├── outputs.tf            # AWS observation outputs
│   │   │   ├── aws.tfvars            # AWS observation configuration
│   │   │   └── terraform.tfstate     # AWS observation-specific state
│   ├── azure/
│   │   ├── base-infra/               # Azure base infrastructure
│   │   ├── infra/                    # Azure MOSIP infrastructure
│   │   └── observ-infra/             # Azure observation infrastructure
│   └── gcp/
│       ├── base-infra/               # GCP base infrastructure
│       ├── infra/                    # GCP MOSIP infrastructure
│       └── observ-infra/             # GCP observation infrastructureeploying MOSIP infrastructure across AWS, Azure, and GCP with three distinct components.

## Three-Component Architecture

### 🏛️ base-infra
- **Purpose**: Foundational networking and VPN access
- **Includes**: VPC/VNet, Subnets, Security Groups, Jumpserver, WireGuard VPN
- **Lifecycle**: Deploy once, rarely destroyed

### 🚀 infra  
- **Purpose**: MOSIP core and external services
- **Includes**: Kubernetes cluster for MOSIP workloads
- **Workloads**: Authentication, Registration, Partner Management, etc.
- **Resources**: Production-level CPU/Memory configuration

### 🔧 observ-infra
- **Purpose**: Observation and monitoring tools
- **Includes**: Minimal Kubernetes cluster for observation tools
- **Workloads**: Rancher UI, Keycloak, Integration services
- **Resources**: Minimal CPU/Memory configuration

## Project Structure

```
terraform/
├── main.tf                           # Root configuration
├── base-infra/                       # Foundational infrastructure module
│   ├── main.tf                       # Main cloud selector
│   ├── variables.tf                  # Common variables
│   ├── outputs.tf                    # Common outputs
│   ├── aws/                          # AWS-specific base infrastructure
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── azure/                        # Azure-specific base infrastructure  
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   └── gcp/                          # GCP-specific base infrastructure
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
├── infra/                            # MOSIP infrastructure module
│   ├── main.tf                       # Main cloud selector
│   ├── variables.tf                  # Common variables
│   ├── outputs.tf                    # Common outputs
│   ├── aws/                          # AWS-specific MOSIP infrastructure
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── azure/                        # Azure-specific MOSIP infrastructure  
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   └── gcp/                          # GCP-specific MOSIP infrastructure
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
├── observ-infra/                     # Observation infrastructure module
│   ├── main.tf                       # Main cloud selector
│   ├── variables.tf                  # Common variables
│   ├── outputs.tf                    # Common outputs
│   ├── aws/                          # AWS-specific observation infrastructure
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── azure/                        # Azure-specific observation infrastructure  
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   └── gcp/                          # GCP-specific observation infrastructure
│       ├── main.tf
│       ├── variables.tf
│       └── outputs.tf
├── modules/                          # Cloud-specific modules
│   ├── aws/                          # AWS modules (existing)
│   ├── azure/                        # Azure modules (placeholder)
│   └── gcp/                          # GCP modules (placeholder)
└── implementations/                  # Cloud-specific deployments
    ├── aws/
    │   ├── base-infra/
    │   │   ├── main.tf               # AWS base implementation entry point
    │   │   ├── variables.tf          # AWS base variables
    │   │   ├── outputs.tf            # AWS base outputs
    │   │   ├── aws.tfvars            # AWS base configuration
    │   │   └── terraform.tfstate     # AWS base-specific state
    │   ├── infra/
    │   │   ├── main.tf               # AWS MOSIP implementation entry point
    │   │   ├── variables.tf          # AWS MOSIP variables
    │   │   ├── outputs.tf            # AWS MOSIP outputs
    │   │   ├── aws.tfvars            # AWS MOSIP configuration
    │   │   └── terraform.tfstate     # AWS MOSIP-specific state
    │   └── observ-infra/
    │       ├── main.tf               # AWS management implementation entry point
    │       ├── variables.tf          # AWS management variables
    │       ├── outputs.tf            # AWS management outputs
    │       ├── aws.tfvars            # AWS management configuration
    │       └── terraform.tfstate     # AWS management-specific state
    ├── azure/
    │   ├── base-infra/               # Azure base infrastructure
    │   ├── infra/                    # Azure MOSIP infrastructure
    │   └── observ-infra/             # Azure management infrastructure
    └── gcp/
        ├── base-infra/               # GCP base infrastructure
        ├── infra/                    # GCP MOSIP infrastructure
        └── observ-infra/             # GCP management infrastructure
```

## Key Benefits

### 1. **Cloud Agnostic Design**
- Single interface for all cloud providers
- Consistent variable naming and structure
- Easy to switch between clouds

### 2. **Three-Component Isolation**
- Clear separation between base networking, MOSIP services, and observation tools
- Independent lifecycle management for each component
- Minimal resource allocation for observation infrastructure

### 3. **Isolated State Management**
- Each cloud provider and component has its own Terraform state file
- No conflicts between cloud deployments or components
- Safe to deploy to multiple clouds and components simultaneously

### 4. **Maintainable Structure**
- Clear separation of concerns
- Reusable modules across components
- Consistent patterns across all clouds

## Usage

### AWS Deployment

1. **Navigate to AWS implementation directory:**
   ```bash
   cd implementations/aws/infra
   ```

2. **Configure AWS settings in `aws.tfvars`:**
   ```hcl
   cluster_name = "my-mosip-cluster"
   cluster_env_domain = "sandbox.example.com"
   aws_provider_region = "us-east-1"
   vpc_name = "my-existing-vpc"
   # ... other AWS-specific configurations
   ```

3. **Set SSH private key:**
   ```bash
   export TF_VAR_ssh_private_key="$(cat ~/.ssh/id_rsa)"
   ```

4. **Deploy:**
   ```bash
   terraform init
   terraform plan -var-file="aws.tfvars"
   terraform apply -var-file="aws.tfvars"
   ```

## AWS Implementation Status

✅ **Fully Implemented**: AWS infrastructure is complete and ready for use
- Uses existing VPC with tagged subnets
- Deploys NGINX in public subnets
- Deploys K8s nodes in private subnets
- Creates all necessary security groups and DNS records

## State Management

Each cloud provider maintains its own Terraform state file in the respective implementation directory:

- **AWS**: `implementations/aws/infra/terraform.tfstate`
- **Azure**: `implementations/azure/infra/terraform.tfstate`
- **GCP**: `implementations/gcp/infra/terraform.tfstate`

This isolation ensures:
- No state conflicts between cloud providers
- Safe parallel deployments
- Independent lifecycle management

## Destruction

To destroy infrastructure for a specific cloud:

```bash
# For AWS
cd implementations/aws/infra
terraform destroy -var-file="aws.tfvars"
```
