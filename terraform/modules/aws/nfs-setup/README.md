## Terraform NFS Server and CSI Setup Module

## Overview

This Terraform module automates the setup of an NFS server and the installation of the NFS CSI (Container Storage Interface) on a Kubernetes cluster.
The module configures the NFS server and deploys the necessary components to enable Kubernetes to use NFS as a storage backend.

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
* Domain and DNS: Ensure that you have a domain and that its DNS is managed by Route 53.
* Git is installed on the EC2 instance.

## Files

* `nfs-setup-main.tf`: Main Terraform script that defines providers, resources, and output values.
* `nfs-csi.sh`: This scripts setup NFS CSI in kubernetes cluster.

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
  terraform plan
  ```
* Apply the Terraform configuration:

  ```
  terraform apply
  ```

## Destroy

To destroy AWS resources, follow the steps below:

* Ensure to have `terraform.tfstate` file.
  ```
  terraform destroy
  ```

## Input Variables

* `NFS_SERVER_LOCATION` (string): The location on the NFS server where the NFS share is located. Must be an absolute path.
* `NFS_SERVER` (string): The address of the NFS server, which can be a DNS name, IPv4, or IPv6 address.
* `SSH_PRIVATE_KEY` (string): The private SSH key used to connect to the NFS server.
* `K8S_INFRA_REPO_URL` (string): The URL of the Kubernetes infrastructure GitHub repository.
* `K8S_INFRA_BRANCH` (string): The branch of the GitHub repository to clone. Default is "main".
* `CLUSTER_NAME` (string): The name of the Kubernetes cluster.

## Terraform Scripts

#### nfs-setup-main.tf

* **null_resource.nfs-server-setup**:
  This resource uses SSH to connect to the NFS server and runs the install-nfs-server.sh script to configure the NFS server.
  The script logs its output to a file `/tmp/nfs-server-log` on the server.
* **null_resource.nfs-csi-setup**:
  This resource runs the nfs-csi.sh script locally after the NFS server has been set up.
  The script configures the NFS CSI driver and logs its output locally `./tmp/nfs-csi-log`.

#### nfs-csi.sh

The nfs-csi.sh script is responsible for setting up the NFS CSI driver on the Kubernetes cluster.
It clones the Kubernetes infrastructure repository, installs Helm if necessary, and runs the required scripts to configure the CSI driver.

* The script creates a log file in the `./tmp` directory and redirects all output to this log file.
* The script sources environment variables from `/etc/environment` and verifies their presence.
* If Helm is not found in the current directory, the script downloads and installs it.
* The script clones the Kubernetes infrastructure repository specified by `K8S_INFRA_REPO_URL` and checks out the branch specified by `K8S_INFRA_BRANCH`.
* The script copies the control plane node configuration file for the specified `CLUSTER_NAME` to the appropriate location.
* The script navigates to the directory containing the NFS CSI setup script and runs it with the copied configuration file.
