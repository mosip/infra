## Terraform Script to setup RKE2 kubernetes cluster

## Overview
This documentation provides an overview of the Terraform script and associated shell script (rke2-setup.sh) to set up an RKE2 cluster.
This setup includes the primary control plane node, additional control plane nodes, ETCD nodes, and worker nodes.
The RKE2 configuration is managed through a GitHub repository.

## Requirements
* Terraform version: `v1.8.4`
* AWS Account
* AWS CLI configured with appropriate credentials
  ```
  $ export AWS_ACCESS_KEY_ID=<AWS_ACCESS_KEY_ID>
  $ export AWS_SECRET_ACCESS_KEY=<AWS_SECRET_ACCESS_KEY>
  ```
* Ensure SSH key created for accessing EC2 instances on AWS.
* Ensure you have access to the private SSH key that corresponds to the public key used when launching the EC2 instance.
* Git is installed on the EC2 instance.

## Files
* `main.tf`: Main Terraform script that defines providers, resources, and output values.
* `rke2-setup.sh`: This scripts install and setup rke2 cluster configuration.

## Setup
* Initialize Terraform
  ```
  terraform init
  ```
* Terraform validate & plan the terraform scripts:
  ```
  terraform validate
  ```
  ```
  terraform plan -var-file="aws.tfvars"
  ```
* Apply the Terraform configuration:
  ```
  terraform apply -var-file="aws.tfvars"
  ```

## Destroy
To destroy AWS resources, follow the steps below:
* Ensure to have `terraform.tfstate` file.
  ```
  terraform destroy
  ```

## Input Variables
* `K8S_CLUSTER_PUBLIC_IPS`: Map of public IP addresses for the Kubernetes cluster nodes.
* `K8S_CLUSTER_PRIVATE_IPS`: Map of private IP addresses for the Kubernetes cluster nodes.
* `SSH_PRIVATE_KEY`: SSH private key for accessing the nodes.
* `K8S_INFRA_REPO_URL`: URL of the Kubernetes infrastructure GitHub repository.
* `K8S_INFRA_BRANCH`: Branch of the Kubernetes infrastructure GitHub repository.
* `RANCHER_IMPORT_URL`: Rancher import URL for kubectl apply.

## Local Variables
* `CONTROL_PLANE_NODE_1`: Private IP of the primary control plane node.
* `K8S_CLUSTER_PRIVATE_IPS_STR`: Comma-separated string of the cluster's private IP addresses.
* `RKE_CONFIG`: Map of configuration parameters.
* `K8S_CLUSTER_PUBLIC_IPS_EXCEPT_CONTROL_PLANE_NODE_1`: Map of public IP addresses excluding the primary control plane node.
* `datetime`: Timestamp for backup purposes.
* `backup_command`: Command to back up the environment file.
* `update_commands`: Commands to update the environment file with RKE2 configuration.

## Terraform Scripts

#### main.tf
The Terraform script is structured to:

* Define necessary variables and local values.
* Provision the primary control plane node.
* Provision additional nodes (control plane, ETCD, and worker nodes).
* Import the RKE2 cluster into Rancher.

#### rke2-setup.sh
The shell script `rke2-setup.sh` performs the following actions on each node:

* Set up logging and error handling.
* Install RKE2 if it is not already installed.
* Clone the Kubernetes infrastructure repository.
* Create and configure the RKE2 configuration file based on the node's role.
* Start the appropriate RKE2 service (server or agent).