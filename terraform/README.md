# Terraform Project Structure

This repository contains a cloud-agnostic Terraform setup with modular architecture. The Terraform directory is structured as follows:

## Terraform architecture for MOSIP infrastructure
![terraform-architecture-mosip-infrastructure.jpg](../docs/_images/terraform-architecture-mosip-infrastructure.png)


## Root Level
- `main.tf` - The main Terraform configuration file for managing infrastructure.
- `modules/` - Contains cloud-specific child modules.

## Child Modules
The `modules` directory includes separate modules for different cloud providers:

- [AWS Module](./modules/aws/README.md)
- [Azure Module](./modules/azure/README.md)
- [GCP Module](./modules/gcp/README.md)

Each module has a `README.md` file explaining its functionality and usage.

## Usage
The root `main.tf` dynamically selects the appropriate module based on the cloud provider specified in the variables.

For detailed instructions on each module, refer to the respective `README.md` files linked above.
