# Azure Terraform Module

## Overview

This module facilitates the deployment of MOSIP (Modular Open Source Identity Platform) infrastructure on Microsoft Azure. It mirrors the structure of the AWS module, encompassing four primary components:

- Resource Creation: Establishes foundational Azure resources necessary for MOSIP operations.
- NGINX Setup: Configures NGINX as a reverse proxy or load balancer to manage and distribute incoming traffic efficiently.
- RKE2 (Rancher Kubernetes Engine 2) Cluster Setup: Deploys a Kubernetes cluster using RKE2, ensuring scalable and reliable     orchestration of containerized applications.
- NFS (Network File System) Server Setup: Implements an NFS server to provide shared storage solutions across the      infrastructure.

## Community Contributions

This module is a WIP and is available for community contributions.