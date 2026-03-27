# AWS ActiveMQ Setup Module

This Terraform module provisions the necessary persistent storage infrastructure for ActiveMQ inside a Kubernetes cluster. It leverages an EBS volume attached to an existing NGINX node, re-exports it via an NFS server, and registers a Kubernetes `StorageClass` to allow pods to dynamically consume it.

## Architecture & Data Flow

1. **EBS Volume Formatting & NFS Setup**
   - Controlled by the `null_resource.activemq-ebs-nfs-setup` resource.
   - Terraform triggers a `local-exec` provisioner running a bash wrapper (`activemq-setup.sh`).
   - The bash wrapper prepares an Ansible environment and invokes `activemq-setup.yml`.
   - **Ansible Execution**:
     - Connects via SSH securely to the NGINX node.
     - Waits for the ActiveMQ EBS block device (e.g., `/dev/nvme3n1`) to appear.
     - Formats the EBS volume as an `xfs` filesystem (if not already formatted).
     - Resolves the stable block device UUID and mounts it to `/srv/activemq`, avoiding device renaming issues.
     - Sets up and enables an NFS kernel server, exporting the mount point `/srv/activemq`.
     - Generates the Kubernetes `StorageClass` YAML artifact (`/tmp/activemq-storageclass.yaml`) locally on the Terraform runner.

2. **Kubernetes StorageClass Provisioning**
   - Controlled by the `null_resource.activemq-k8s-storageclass` resource, which runs after the NFS setup.
   - Terraform connects to the Kubernetes control plane via a `remote-exec` SSH provisioner.
   - It copies the generated `StorageClass` YAML from the runner to the control plane.
   - Uses `kubectl` to apply the YAML (`nfs-csi-activemq`), so that ActiveMQ Helm charts can reference this `StorageClass`.

## File Structure

- **`main.tf`**: The primary Terraform module defining the `null_resource` blocks for the local Ansible execution and remote Kubernetes configuration.
- **`activemq-setup.sh`**: A wrapper bash script that validates inputs, sets up a temporary Ansible workspace (inventory and configs), robustly manages SSH keys, and runs the playbook.
- **`activemq-setup.yml`**: The Ansible playbook that performs the system-level formatting, mounting, and NFS configuration on the target node.

## Inputs

| Name                           | Description                                                          | Type     | Default           | Required |
|--------------------------------|----------------------------------------------------------------------|----------|-------------------|:--------:|
| `NGINX_PUBLIC_IP`              | Public IP of the NGINX node                                          | `string` | n/a               | Yes      |
| `NGINX_PRIVATE_IP`             | Private IP of the NGINX node                                         | `string` | n/a               | Yes      |
| `SSH_PRIVATE_KEY`              | Sensitive SSH private key content to access nodes                    | `string` | n/a               | Yes      |
| `NGINX_NODE_EBS_VOLUME_SIZE_3` | Size of the 3rd EBS volume attached to the target NGINX node         | `number` | n/a               | Yes      |
| `ACTIVEMQ_STORAGE_DEVICE`      | Block device path of the 3rd EBS volume                              | `string` | `/dev/nvme3n1`    | No       |
| `ACTIVEMQ_MOUNT_POINT`         | Mount point for ActiveMQ persistent storage & NFS share path         | `string` | `/srv/activemq`   | No       |
| `CONTROL_PLANE_HOST`           | IP address of the Kubernetes control plane node                      | `string` | n/a               | Yes      |
| `CONTROL_PLANE_USER`           | SSH username for control plane access                                | `string` | `ubuntu`          | No       |

## Security Considerations

The `SSH_PRIVATE_KEY` is passed seamlessly through the environment (`TF_ACTIVEMQ_SSH_KEY`) and is never included in commandline arguments. The bash wrapper creates a temporary key file with `600` permissions and automatically removes it via bash `trap` signals (like `EXIT` or `ERR`) after the pipeline completes, guaranteeing that sensitive keys are not leaked in CI/CD pipeline logs, tfstate command histories, or process lists.
