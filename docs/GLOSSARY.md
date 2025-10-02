# Glossary of Technical Terms

This glossary provides simple, beginner-friendly explanations of technical terms used throughout the MOSIP deployment documentation.

## Table of Contents

- [Cloud & Infrastructure Terms](#cloud--infrastructure-terms)
- [Kubernetes & Container Terms](#kubernetes--container-terms)
- [Deployment & Automation Terms](#deployment--automation-terms)
- [Security & Networking Terms](#security--networking-terms)
- [Database & Storage Terms](#database--storage-terms)

---

## Cloud & Infrastructure Terms

### AWS (Amazon Web Services)
A cloud computing platform provided by Amazon that offers servers, storage, databases, and other computing resources over the internet. Think of it as renting computer resources instead of buying physical servers.

**Example**: Instead of buying a physical server for $10,000, you rent AWS computing power for $100/month.

### Azure
Microsoft's cloud computing platform, similar to AWS. It provides virtual machines, databases, and other cloud services.

### GCP (Google Cloud Platform)
Google's cloud computing platform, similar to AWS and Azure.

### VPC (Virtual Private Cloud)
A private, isolated section of a cloud provider's network that you control. It's like having your own private network in the cloud.

**Why it matters**: VPC keeps your MOSIP deployment separate and secure from other users on the same cloud platform.

### EC2 (Elastic Compute Cloud)
AWS's virtual server service. An EC2 instance is like a computer running in the cloud that you can configure and use remotely.

**Example**: Instead of a physical server in your office, you get a virtual server running in AWS's data center.

### Availability Zones (AZs)
Separate data centers within a cloud region. Using multiple availability zones provides backup if one data center has issues.

**Example**: `us-east-1a`, `us-east-1b` are different data centers in the US East region.

### Region
A geographic location where cloud providers have data centers.

**Example**: `us-west-2` (Oregon, USA), `ap-south-1` (Mumbai, India), `eu-west-1` (Ireland)

### EBS (Elastic Block Store)
Virtual hard drives that attach to AWS EC2 instances for data storage.

**Example**: Like adding an external hard drive to your computer, but in the cloud.

### AMI (Amazon Machine Image)
A pre-configured template that contains the operating system and software needed to launch an EC2 instance.

**Example**: A snapshot of a computer with Ubuntu Linux already installed and configured.

### Load Balancer
A system that distributes incoming traffic across multiple servers to prevent any single server from getting overloaded.

**Example**: Like a receptionist directing customers to different service counters to avoid long queues.

---

## Kubernetes & Container Terms

### Kubernetes (K8s)
An open-source system for managing containerized applications across multiple servers. It automates deployment, scaling, and management of applications.

**Why it matters**: MOSIP runs on Kubernetes to ensure high availability and easy scaling.

### Cluster
A group of servers (called nodes) that work together to run applications. In Kubernetes, a cluster consists of control plane nodes and worker nodes.

**Example**: Instead of one powerful server, you have 5-10 servers working together as a team.

### Node
A single server (physical or virtual) in a Kubernetes cluster. Each node can run multiple application containers.

### Pod
The smallest deployable unit in Kubernetes. A pod contains one or more containers running your application.

**Example**: A pod is like a house, and containers are like rooms in that house.

### Namespace
A way to divide a single Kubernetes cluster into multiple virtual clusters for organization and isolation.

**Example**: Like having separate folders on your computer for work files, personal files, and photos.

### Container
A lightweight, standalone package that includes everything needed to run a piece of software (code, runtime, libraries, settings).

**Example**: Like a shipping container that holds everything needed to run your application, ensuring it works the same everywhere.

### Docker
A platform for creating, deploying, and running applications in containers.

### Helm
A package manager for Kubernetes that helps you install and manage applications on Kubernetes clusters.

**Example**: Like an app store for Kubernetes applications - you can install, update, and remove applications easily.

### Helm Chart
A package of pre-configured Kubernetes resources that defines how to install and configure an application.

**Example**: Like a recipe that tells Helm exactly how to install and set up an application.

### RKE2 (Rancher Kubernetes Engine 2)
A Kubernetes distribution that is easy to install and manage, with enhanced security features.

**Why it matters**: MOSIP uses RKE2 to create and manage Kubernetes clusters.

### Rancher
A management platform for Kubernetes that provides a user-friendly interface to manage multiple clusters.

**Example**: Like a dashboard that lets you control and monitor all your Kubernetes clusters from one place.

---

## Deployment & Automation Terms

### Terraform
An infrastructure-as-code tool that lets you define and create cloud resources using configuration files instead of clicking buttons in a web interface.

**Why it matters**: Terraform automates the creation of AWS resources (VPCs, servers, databases) needed for MOSIP.

**Example**: Instead of manually clicking 50 buttons to create a server, you write a config file and Terraform creates everything automatically.

### Infrastructure as Code (IaC)
Managing and provisioning infrastructure through code files instead of manual configuration.

**Benefits**: Version control, repeatability, documentation, automation.

### Helmsman
A tool that manages Kubernetes deployments using Helm charts. It reads configuration files (DSF) and ensures your desired applications are installed correctly.

**Why it matters**: Helmsman automates MOSIP service deployment on Kubernetes.

### DSF (Desired State File)
A configuration file that tells Helmsman what applications to install, what versions to use, and how to configure them.

**Example**: Like a shopping list that tells Helmsman: "Install PostgreSQL version 15, MinIO with 100GB storage, Kafka with 3 replicas."

### GitHub Actions
An automation platform built into GitHub that runs workflows (automated tasks) based on triggers like pushing code or clicking buttons.

**Why it matters**: MOSIP uses GitHub Actions to automate Terraform and Helmsman deployments.

### Workflow
An automated process defined in GitHub Actions that performs tasks like deploying infrastructure or running tests.

**Example**: A workflow might: 1) Connect to AWS, 2) Run Terraform to create servers, 3) Send you a notification when done.

### CI/CD (Continuous Integration/Continuous Deployment)
A method of frequently deploying code changes through automated testing and deployment pipelines.

---

## Security & Networking Terms

### SSH (Secure Shell)
A secure protocol for connecting to remote servers over a network. SSH keys are cryptographic keys used for authentication.

**Example**: Like a secure tunnel between your computer and a server, where only you have the key.

### SSH Key Pair
Two related keys: a private key (kept secret) and a public key (shared with servers). Used for secure server access without passwords.

**Example**: Private key is like your house key, public key is like your door lock. Only your key opens your lock.

### GPG (GNU Privacy Guard)
A tool for encrypting and signing data to keep it secure.

**Why it matters**: MOSIP uses GPG to encrypt Terraform state files containing sensitive information.

### WireGuard
A modern, fast, and secure VPN (Virtual Private Network) protocol.

**Why it matters**: MOSIP uses WireGuard to create secure connections to private infrastructure that isn't exposed to the internet.

### Jump Server (Bastion Host)
A special server that acts as a gateway to access other servers in a private network.

**Example**: Like a secure lobby where you check in before accessing the main building.

### VPN (Virtual Private Network)
A secure, encrypted connection over the internet that makes your traffic private.

**Why it matters**: WireGuard VPN lets you securely access MOSIP infrastructure from anywhere.

### SSL/TLS Certificate
Digital certificates that enable encrypted HTTPS connections to websites and services.

**Example**: The padlock icon you see in your browser's address bar.

### Route 53
AWS's DNS (Domain Name System) service that translates domain names into IP addresses.

**Example**: Translates `sandbox.mosip.net` into the actual server IP address like `52.23.45.67`.

### Security Group
A virtual firewall that controls what network traffic is allowed to reach your servers.

**Example**: Like a security guard checking IDs - only allows traffic from approved sources.

### IAM (Identity and Access Management)
AWS's system for managing user permissions and access to cloud resources.

**Example**: Like employee badges in an office - different badges give access to different rooms.

---

## Database & Storage Terms

### PostgreSQL (Postgres)
A powerful, open-source relational database management system.

**Why it matters**: MOSIP stores all identity data, configurations, and transactions in PostgreSQL.

### Database Schema
The structure of a database - defines tables, columns, relationships, and constraints.

**Example**: Like a blueprint that shows how data is organized in the database.

### S3 (Simple Storage Service)
AWS's object storage service for storing files, backups, and static assets.

**Example**: Like an unlimited cloud hard drive for storing files.

### MinIO
An open-source object storage system compatible with AWS S3.

**Why it matters**: MOSIP uses MinIO to store documents, photos, and files.

### NFS (Network File System)
A protocol that allows multiple servers to share and access the same files over a network.

**Example**: Like a shared network drive that multiple computers can access.

### Persistent Volume
Storage in Kubernetes that persists even if containers or pods are deleted.

**Example**: Like saving a file to your hard drive instead of keeping it in RAM - it survives restarts.

---

## MOSIP-Specific Terms

### MOSIP (Modular Open Source Identity Platform)
An open-source platform for building national identity systems. It provides services for enrollment, authentication, and identity management.

### Config Server
A centralized service that provides configuration settings to all MOSIP services.

**Example**: Like a settings manager that tells all applications how to behave.

### Keycloak
An open-source identity and access management solution used by MOSIP for authentication and authorization.

**Example**: The login system that checks usernames and passwords.

### Kafka
A distributed messaging system that handles communication between MOSIP services.

**Example**: Like a post office that delivers messages between different applications.

### ActiveMQ
Another messaging system used by MOSIP for service-to-service communication.

### Istio
A service mesh that manages communication between microservices with features like traffic control, security, and monitoring.

**Why it matters**: Istio provides networking, security, and observability for MOSIP services.

### reCAPTCHA
Google's anti-bot service that verifies users are human (the "I'm not a robot" checkbox).

**Why it matters**: Protects MOSIP web interfaces from automated attacks and spam.

---

## Monitoring & Operations Terms

### Prometheus
An open-source monitoring system that collects and stores metrics from applications and infrastructure.

**Example**: Like a health monitoring system that tracks server CPU, memory, and application performance.

### Grafana
A visualization tool that creates dashboards and charts from monitoring data.

**Example**: Like a dashboard in your car showing speed, fuel, temperature - but for servers and applications.

### Kibana
A visualization tool for searching and analyzing log data from applications and servers.

**Example**: Like a search engine for application logs and error messages.

### Logging
Recording events, errors, and activities that happen in applications and systems.

**Why it matters**: Logs help troubleshoot issues and understand what happened when things go wrong.

---

## Additional Terms

### API (Application Programming Interface)
A way for different software applications to communicate with each other.

**Example**: Like a waiter taking your order (request) to the kitchen (server) and bringing back your food (response).

### Endpoint
A specific URL where an API can be accessed.

**Example**: `https://api.mosip.net/authenticate` is an endpoint for authentication.

### Repository Secret
A secure variable stored in GitHub that workflows can access but are hidden from view.

**Example**: Storing your AWS password securely so GitHub Actions can use it without exposing it.

### Environment Secret
A secret that is specific to a deployment environment (like development, staging, production).

**Example**: Different database passwords for development vs. production environments.

### Dry Run
A test mode where commands are simulated without making actual changes.

**Example**: Like a dress rehearsal before the actual performance - you see what would happen without actually doing it.

### State File (Terraform)
A file that tracks what infrastructure Terraform has created so it knows what to update or delete.

**Example**: Like a inventory list of everything Terraform has built.

---

## Quick Reference

| Term | Simple Explanation | Why It Matters |
|------|-------------------|----------------|
| **AWS** | Amazon's cloud computing platform | Where MOSIP infrastructure runs |
| **Kubernetes** | Container orchestration platform | Manages MOSIP applications |
| **Terraform** | Infrastructure automation tool | Creates AWS resources automatically |
| **Helmsman** | Kubernetes deployment manager | Deploys MOSIP services |
| **VPC** | Private cloud network | Keeps MOSIP secure and isolated |
| **WireGuard** | VPN protocol | Secure access to private infrastructure |
| **PostgreSQL** | Database system | Stores MOSIP data |
| **DSF** | Deployment configuration file | Tells Helmsman what to install |

---

## Need More Help?

- **Read the Documentation**: Each section of the README provides detailed explanations
- **Ask Questions**: Open a GitHub issue if you need clarification
- **Community Support**: Join MOSIP community channels for assistance

---

**Navigation**: [Back to Main README](../README.md)
