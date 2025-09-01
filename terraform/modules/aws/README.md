The infrastructure consists of four key components:

* `AWS resource creation`
* `NGINX setup`
* `RKE2 (Rancher Kubernetes Engine 2) cluster setup`
* `NFS server setup`

### Components

1. **AWS Resource Creation:**

   * This component is responsible for creating all the necessary AWS infrastructure that other components depend on. It sets up:
   * AWS Security Groups to control network traffic.
   * IAM roles and policies are used to grant permission to the Nginx EC2 instance to update DNS records for certbot validation in order to generate an SSL certificate.
   * EC2 Instances for Nginx load balancer, Kubernetes Control Plane, ETCD, and Worker nodes.
   * DNS Records (Route53) for domain name resolution.
2. **NGINX setup:**

   * The NGINX setup component is responsible for deploying an NGINX server and updating its configuration file to act as a load balancer.
   * This ensures that external traffic can be routed to Istio node ports, which then route the request to the services running on the Kubernetes cluster.
3. **RKE2 Setup**

   * This component focuses on deploying the `Rancher Kubernetes Engine 2 (RKE2) cluster` and importing it into the `Rancher UI` dashboard.
   * It also handles downloading necessary files such as the `kubectl` binary and `kubeconfig` file from the control plane nodes, using the infrastructure provisioned by the AWS component. It manages:
4. **NFS Setup**

   * The NFS setup component provides shared file storage for the Kubernetes cluster. This involves:
     * **NFS Server Setup** for hosting the storage.
     * **NFS Client Configuration** for enabling Kubernetes workloads to use NFS volumes as storage class.
   * By default, the Nginx node is used as the NFS server.
     If you wish to designate a separate node for this purpose, please update the following variables in the `main.tf` file for the `nfs-setup` module:
     * `NFS_SERVER_LOCATION`
     * `NFS_SERVER`
     * `SSH_PRIVATE_KEY`

## Create MOSIP Infrastructure

### Prerequisites

* Import `infra` repository to your GitHub account and set its visibility to private to ensure confidentiality.
  - Go to the repository URL and click "Use this template" or "Fork"
  - Set repository visibility to "Private"
  - Import may take some time to prepare the repository
* Create a new branch `env-<environment_name>` from master branch.
* Goto `terraform/` location and update environment related details in `env.tfvars` file.
  * `CLUSTER_NAME`: The name of the Kubernetes cluster.Example: `sandbox`
  * `CLUSTER_ENV_DOMAIN`: The domain name for MOSIP.Example: `sandbox.xyz.net`
  * `MOSIP_EMAIL_ID`: The email address used by Certbot to send SSL certificate expiry notifications.
  * `SSH_KEY_NAME`: The SSH key name used for accessing AWS node instances via SSH. Ensure an SSH key pair is created/exists on AWS, and provide the key pair name in this field.Example: `my-ssh-key`
  * `AWS_PROVIDER_REGION`: The AWS region where resources will be created.Example: `ap-south-1`
  * `K8S_INSTANCE_TYPE`: The instance type for Kubernetes nodes.Default: `t3a.2xlarge`
  * `NGINX_INSTANCE_TYPE`: The instance type for the Nginx server.Default: `t3a.medium`
  * `ZONE_ID`: The Route 53 hosted zone ID associated with the domain.
  * `AMI`: The Amazon Machine Image (AMI) ID for the instances.Default: `ami-0ad21ae1d0696ad58`Note: `This is specific to Ubuntu 24.04.`
  * `K8S_INFRA_REPO_URL`: The URL of the Kubernetes infrastructure repository.Default: `https://github.com/mosip/k8s-infra.git`
  * `K8S_INFRA_BRANCH`: The branch of the Kubernetes infrastructure repository to be used.Default: `MOSIP-34911`
  * `NGINX_NODE_ROOT_VOLUME_SIZE`: The root volume size (in GB) for the Nginx node.Default: `24`
  * `NGINX_NODE_EBS_VOLUME_SIZE`: The EBS volume size (in GB) for the Nginx node.
    This volume will be used as a NFS server location for kubernetes storage class.Default: `300`
  * `K8S_INSTANCE_ROOT_VOLUME_SIZE`: The root volume size (in GB) for the Kubernetes nodes.Default: `64`
  * `K8S_CONTROL_PLANE_NODE_COUNT`: The number of control-plane nodes for the Kubernetes cluster. These nodes will serve as a control-plane, ETCD, and worker node within the Kubernetes cluster.Default: `4`
  * `K8S_ETCD_NODE_COUNT`: The number of ETCD nodes in the Kubernetes cluster. These nodes will serve as a ETCD and worker node within the Kubernetes cluster.Default: `2`
  * `K8S_WORKER_NODE_COUNT`: The number of worker nodes in the Kubernetes cluster. These nodes will serve as a worker node within the Kubernetes cluster.Default: `2`
  * `RANCHER_IMPORT_URL`: The Rancher import URL used to import the Kubernetes cluster into Rancher.
    Default: `"kubectl apply -f <rancher-import-url>"`

### Run `terraform plan / apply` workflow to set up MOSIP infrastructure

* This GitHub Action automates the Terraform workflow,
  allowing users to run `terraform plan` and optionally `terraform apply` commands within a CI/CD pipeline.
  The workflow is triggered manually via workflow_dispatch.
* To trigger this workflow:
  1. Go to the `Actions` tab in your GitHub repository
  2. Select `terraform plan / apply` workflow
  3. Click `Run workflow`
  4. Provide the required inputs
  5. Click `Run workflow` to start the workflow

### Inputs

* `SSH_PRIVATE_KEY (required)`: GitHub secret name containing the AWS's key-pair private key for SSH login on the nginx node.
* `TERRAFORM_APPLY (optional)`: Boolean flag to apply the Terraform plan. Defaults to false.

### Environment Variables

* `AWS_ACCESS_KEY_ID`: The AWS access key ID used for authenticating with AWS services. This is stored as a GitHub secret `AWS_ACCESS_KEY_ID`.
* `AWS_SECRET_ACCESS_KEY`: The AWS secret access key corresponding to the AWS access key ID. This is stored as a GitHub secret `AWS_SECRET_ACCESS_KEY`.
* `TF_VAR_SSH_PRIVATE_KEY`: The SSH private key used for accessing nginx server. This is referenced from the input `SSH_PRIVATE_KEY` and stored as a GitHub secret.

## Destroy MOSIP Infrastructure

### Run `terraform destroy` workflow

* This GitHub Action automates the `Terraform destroy` command within a CI/CD pipeline.
  The workflow can be manually triggered to destroy infrastructure managed by Terraform.
* To trigger this workflow:
  1. Go to the `Actions` tab in your GitHub repository
  2. Select `terraform destroy` workflow
  3. Click `Run workflow`
  4. Provide the required inputs
  5. Click `Run workflow` to start the workflow

### Inputs

* `SSH_PRIVATE_KEY (required)`: GitHub secret name containing the private key for SSH login on the nginx node.
* `TERRAFORM_DESTROY (optional)`: Boolean flag to determine whether to execute the Terraform destroy command. Defaults to false.

### Environment Variables

* `AWS_ACCESS_KEY_ID`: The AWS access key ID used for authenticating with AWS services. This is stored as a GitHub secret `AWS_ACCESS_KEY_ID`.
* `AWS_SECRET_ACCESS_KEY`: The AWS secret access key corresponding to the AWS access key ID. This is stored as a GitHub secret `AWS_SECRET_ACCESS_KEY`.
* `TF_VAR_SSH_PRIVATE_KEY`: The SSH private key used for accessing nginx server. This is referenced from the input `SSH_PRIVATE_KEY` and stored as a GitHub secret.

# Terraform Setup for MOSIP Infrastructure

## Overview

This Terraform configuration script set up the infrastructure for MOSIP deployment on AWS.

The setup includes:

1. EC2 instance creation for Kubernetes nodes and Nginx server.
2. Security group definition for cluster nodes.
3. Nginx server installation, configuration setup, and SSL certificate generation.
4. Security group for Nginx machine.

## Requirements

* Terraform version: `v1.8.4`
* AWS Account
* AWS CLI configured with appropriate credentials
  ```
  $ export AWS_ACCESS_KEY_ID=<AWS_ACCESS_KEY_ID>
  $ export AWS_SECRET_ACCESS_KEY=<AWS_SECRET_ACCESS_KEY>
  $ export TF_VAR_SSH_PRIVATE_KEY=<EC2_SSH_PRIVATE_KEY>
  ```

## Files

* `aws-main.tf`: Main Terraform script that defines providers, resources, and output values.
* `variables.tf`: Defines variables used in the Terraform scripts.
* `outputs.tf`: Provides the output values.
* `locals.tf`: Defines a local variable `SECURITY_GROUP` containing configuration parameters required for setting up security groups for Nginx and Kubernetes cluster nodes.
* `aws.tfvars`: tfvars file is used to set the actual values of the variables.

## Setup

* Initialize Terraform.

  ```
  terraform init
  ```
* Review and modify variable values:

  * Ensure `locals.tf` contains correct values for your setup.
  * Update values in `env.tfvars` as per your organization requirement.
* Terraform validate & plan the terraform scripts:

  ```
  terraform validate
  ```

  ```
  terraform plan -var-file="./aws.tfvars
  ```
* Apply the Terraform configuration:

  ```
  terraform apply -var-file="./aws.tfvars
  ```

## Destroy

To destroy AWS resources, follow the steps below:

* Ensure to have `terraform.tfstate` file.
  ```
  terraform destroy -var-file=./aws.tfvars
  ```

## COMPONENTS

#### aws-resource-creation

This module is responsible for creating the AWS resources needed for the MOSIP platform, including security groups, an NGINX server, and a Kubernetes cluster nodes.

* Inputs:
  * `CLUSTER_NAME`: The name of the Kubernetes cluster.
  * `AWS_PROVIDER_REGION`: The AWS region for resource creation.
  * `SSH_KEY_NAME`: The name of the SSH key for accessing instances.
  * `K8S_INSTANCE_TYPE`: The instance type for Kubernetes nodes.
  * `NGINX_INSTANCE_TYPE`: The instance type for the NGINX server.
  * `CLUSTER_ENV_DOMAIN`: The domain name for the MOSIP platform.
  * `ZONE_ID`: The Route 53 hosted zone ID.
  * `AMI`: The Amazon Machine Image ID for the instances.
  * `SECURITY_GROUP`: Security group configurations.

#### nginx-setup

This module sets up NGINX and configures it with the provided domain and SSL certificates.

* Inputs:
  * `NGINX_PUBLIC_IP`: The public IP address of the NGINX server.
  * `CLUSTER_ENV_DOMAIN`: The domain name for the MOSIP platform.
  * `MOSIP_K8S_CLUSTER_NODES_PRIVATE_IP_LIST`: List of private IP addresses of the Kubernetes nodes.
  * `MOSIP_PUBLIC_DOMAIN_LIST`: List of public domain names.
  * `CERTBOT_EMAIL`: The email ID for SSL certificate generation.
  * `SSH_KEY_NAME`: SSH private key used for login (i.e., file content of SSH pem key).

#### rke2-setup

This module sets up RKE2 kubernetes cluster.

* **Primary Control Plane Node Setup :**
  This resource sets up the primary control plane node.
  It connects to the node via SSH, uploads the rke2-setup.sh script, and executes it to configure the node.
* **Additional Nodes Setup :**
  This resource sets up additional nodes (control plane, ETCD, and worker nodes) in the cluster.
  It follows a similar process to the primary node setup.
* **Rancher Import :**
  This resource imports the RKE2 cluster into Rancher.
  It connects to the primary control plane node, configures kubectl, and applies the Rancher import URL.

#### nfs-setup

This Terraform module, nfs-setup, is designed to configure and deploy an NFS (Network File System) setup within a Kubernetes cluster environment.
The module depends on other infrastructure modules for AWS resource creation and RKE2 setup.

* Inputs:
  * `NFS_SERVER_LOCATION`: The location on the NFS server where the files will be stored. This is dynamically set based on the `CLUSTER_ENV_DOMAIN` variable.
  * `NFS_SERVER`: The private IP address of the NGINX server, which acts as the NFS server. This value is retrieved from the aws-resource-creation module.
  * `SSH_PRIVATE_KEY`: The SSH private key used for accessing the NFS server.
  * `K8S_INFRA_REPO_URL`: The URL of the Kubernetes infrastructure repository where the configuration files are stored.
  * `K8S_INFRA_BRANCH`: The branch of the Kubernetes infrastructure repository to be used.
  * `CLUSTER_NAME`: The name of the Kubernetes cluster that will use the NFS setup.

## Outputs

The following outputs are provided:

* `K8S_CLUSTER_PUBLIC_IPS`: The public IP addresses of the Kubernetes cluster nodes.
* `K8S_CLUSTER_PRIVATE_IPS`: The private IP addresses of the Kubernetes cluster nodes.
* `NGINX_PUBLIC_IP`: The public IP address of the NGINX server.
* `NGINX_PRIVATE_IP`: The private IP address of the NGINX server.
* `MOSIP_NGINX_SG_ID`: The security group ID for the NGINX server.
* `MOSIP_K8S_SG_ID`: The security group ID for the Kubernetes cluster.
* `MOSIP_K8S_CLUSTER_NODES_PRIVATE_IP_LIST`: The private IP addresses of the Kubernetes cluster nodes.
* `MOSIP_PUBLIC_DOMAIN_LIST`: The public domain names.
* `K8S_CLUSTER_PUBLIC_IPS_EXCEPT_CONTROL_PLANE_NODE_1`: Map of public IP addresses excluding the primary control plane node.
* `CONTROL_PLANE_NODE_1`: Private IP of the primary control plane node.
* `K8S_CLUSTER_PRIVATE_IPS_STR`: Comma-separated string of the cluster's private IP addresses.
* `K8S_TOKEN`: RKE2 Kubernetes access token

# Terraform fetch variables via ENV variables

```
$ export TF_VAR_CLUSTER_NAME=dev
$ export TF_LOG="DEBUG"
$ export TF_LOG_PATH="/tmp/terraform.log"
```

* TF_VAR_ : is a syntax
* CLUSTER_NAME=dev : is variable and its value
