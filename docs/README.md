# MOSIP Infrastructure Documentation Index

Welcome to the MOSIP Infrastructure documentation! This index helps you find exactly what you need, whether you're a complete beginner or an experienced DevOps engineer.

## Quick Navigation

### For Complete Beginners

**Start your MOSIP deployment journey here:**

1. **[Glossary](GLOSSARY.md)** - Learn all the technical terms
 - What is AWS? What is Kubernetes? What is Terraform?
 - Plain language explanations for every concept
 - No prior cloud knowledge required

2. **[Secret Generation Guide](SECRET_GENERATION_GUIDE.md)** - Create required credentials
 - Step-by-step SSH key generation
 - How to get AWS credentials
 - Creating passwords and VPN configs
 - Includes links to official documentation

3. **[Workflow Guide](WORKFLOW_GUIDE.md)** - Run deployments through GitHub
 - Visual walkthrough of GitHub Actions interface
 - Where to click and what to select
 - Understanding dry-run vs actual deployment
 - Screenshots and examples

4. **[DSF Configuration Guide](DSF_CONFIGURATION_GUIDE.md)** - Configure MOSIP services
 - What is a DSF file and why you need it
 - How to find and update clusterid
 - Domain configuration explained
 - Examples for each setting

5. **[Environment Destruction Guide](ENVIRONMENT_DESTRUCTION_GUIDE.md)** - Clean up resources
 - Safe teardown procedures
 - How to avoid unexpected costs
 - Backup before destruction
 - Complete cleanup verification

### For Experienced Users

**Jump directly to what you need:**

- **Terraform Infrastructure**: See [terraform/README.md](../terraform/README.md)
- **Helmsman Deployment**: See [Helmsman/README.md](../Helmsman/README.md)
- **WireGuard VPN Setup**: See [terraform/base-infra/WIREGUARD_SETUP.md](../terraform/base-infra/WIREGUARD_SETUP.md)
- **GitHub Actions Workflows**: See [.github/workflows/]../.github/workflows/)

---

## Complete Documentation List

### Core Deployment Guides

| Document | Description | Who Should Read |
|----------|-------------|-----------------|
| **[Main README](../README.md)** | Complete deployment overview and quick start guide | Everyone - start here |
| **[Glossary](GLOSSARY.md)** | Technical terms explained in plain language | Beginners |
| **[Secret Generation Guide](SECRET_GENERATION_GUIDE.md)** | How to create all required secrets and credentials | Everyone before deployment |
| **[Workflow Guide](WORKFLOW_GUIDE.md)** | Visual GitHub Actions workflow navigation | Everyone during deployment |
| **[DSF Configuration Guide](DSF_CONFIGURATION_GUIDE.md)** | Helmsman configuration file explained in detail | Everyone before Helmsman deployment |
| **[Environment Destruction Guide](ENVIRONMENT_DESTRUCTION_GUIDE.md)** | Safe resource cleanup and cost management | Everyone when decommissioning |
| **[Helmsman Destroy Guide](HELMSMAN_DESTROY_GUIDE.md)** | How to safely undeploy MOSIP services from Kubernetes | Everyone when removing services |

### Infrastructure (Terraform + Ansible)

| Document | What It Covers | Who Should Read |
|----------|----------------|-----------------|
| **[Profiles](PROFILES.md)** | `mosip`, `esignet-standalone`, `observ` — sizes, components, `profile.yml` | Everyone before Terraform |
| **[Deployment Sequence](DEPLOYMENT_SEQUENCE.md)** | Component order, day-2 runs, DNS providers, checks | Operators |
| **[Terraform Workflow Guide](TERRAFORM_WORKFLOW_GUIDE.md)** | `terraform plan / apply` and `terraform destroy` inputs | Everyone running Terraform |
| **[Data-centre Deployment](DATACENTRE_DEPLOYMENT.md)** | Pre-created VMs, no Terraform — Ansible only | Data-centre / on-prem teams |
| **[Repository Structure](TREE_STRUCTURE.md)** | Where everything lives | Contributors |

### Helmsman Deployment (in run order)

| Document | What It Covers | Who Should Read |
|----------|----------------|-----------------|
| **[External + Prereqs](HELMSMAN_EXTERNAL_GUIDE.md)** | Monitoring/logging stack, PostgreSQL, Keycloak, Kafka, MinIO … | All profiles |
| **[MOSIP Services](HELMSMAN_MOSIP_GUIDE.md)** | MOSIP core services (auto-triggered) | MOSIP platform |
| **[eSignet (with MOSIP)](esignet_README.md)** | eSignet on a MOSIP platform cluster | MOSIP platform |
| **[eSignet Standalone](ESIGNET_STANDALONE_DEPLOYMENT_GUIDE.md)** | eSignet standalone (incl. `esignet-standalone-2.0.0`) end to end | eSignet standalone |
| **[Testrigs](HELMSMAN_TESTRIGS_GUIDE.md)** | API, UI and DSL testrigs | All profiles |
| **[reCAPTCHA Setup](RECAPTCHA_SETUP_GUIDE.md)** | reCAPTCHA keys as environment secrets | MOSIP platform, eSignet |

### Operations

| Document | What It Covers | Who Should Read |
|----------|----------------|-----------------|
| **[Day-2 Operations](OPERATIONS_GUIDE.md)** | Add / remove / resize nodes, stop/start, subdomains, firewall rules, standalone VMs, DNS later | Operators |
| **[Partner Onboarding](ONBOARDING_GUIDE.md)** | Diagnose and re-run partner onboarding (e.g. `IDA-MPA-009`) | Operators |
| **[Kubernetes Health Checker](k8s-health-checker.md)** | Scheduled cluster health check workflow | Operators |

### Component-Specific Documentation

| Component | Document | What It Covers |
|-----------|----------|----------------|
| **Terraform** | [terraform/README.md](../terraform/README.md) | Infrastructure as code, tfvars, modules, state management |
| **Helmsman** | [Helmsman/README.md](../Helmsman/README.md) | Application deployment, DSF files, hooks, troubleshooting |
| **Helmsman Destroy** | [HELMSMAN_DESTROY_GUIDE.md](HELMSMAN_DESTROY_GUIDE.md) | Undeploying services, data backup, cleanup procedures |
| **WireGuard** | [terraform/base-infra/WIREGUARD_SETUP.md](../terraform/base-infra/WIREGUARD_SETUP.md) | VPN setup, peer configuration, client installation |
| **Workflows** | [Helmsman/helmsman-workflow-guide.md](../Helmsman/helmsman-workflow-guide.md) | Helmsman workflow details |

---

## Learning Paths

### Path 1: "I'm New to Cloud/DevOps"

**Time required:** 2-3 days for first deployment

1. **Day 1: Learning & Setup**
 - [ ] Read [Glossary](GLOSSARY.md) - Understand all terms (2 hours)
 - [ ] Read [Main README](../README.md) - Get deployment overview (1 hour)
 - [ ] Follow [Secret Generation Guide](SECRET_GENERATION_GUIDE.md) - Create all secrets (2 hours)
 - [ ] Set up AWS account and configure IAM permissions

2. **Day 2: Infrastructure Deployment**
 - [ ] Follow [Workflow Guide](WORKFLOW_GUIDE.md) - Deploy base-infra (1 hour)
 - [ ] Follow [WireGuard Setup](../terraform/base-infra/WIREGUARD_SETUP.md) - Configure VPN (1 hour)
 - [ ] Deploy main infrastructure (1 hour)
 - [ ] Verify all components working

3. **Day 3: Application Deployment**
 - [ ] Follow [DSF Configuration Guide](DSF_CONFIGURATION_GUIDE.md) - Update configs (2 hours)
 - [ ] Deploy prerequisites and external services (1 hour)
 - [ ] Deploy MOSIP core services (2 hours)
 - [ ] Verify deployment and test access

### Path 2: "I Know Cloud but New to MOSIP"

**Time required:** 4-6 hours for first deployment

1. **Planning (30 minutes)**
 - [ ] Skim [Main README](../README.md) - Understand MOSIP architecture
 - [ ] Review [Glossary](GLOSSARY.md) - MOSIP-specific terms only
 - [ ] Check [Secret Generation Guide](SECRET_GENERATION_GUIDE.md) - What secrets are needed

2. **Infrastructure (2 hours)**
 - [ ] Fill in `profiles/<profile>/aws/*.tfvars` (and `base-infra/aws.tfvars`)
 - [ ] Run Terraform workflows
 - [ ] Set up WireGuard VPN

3. **Applications (2-3 hours)**
 - [ ] Set Helmsman environment variables/secrets ([DSF Configuration Guide](DSF_CONFIGURATION_GUIDE.md))
 - [ ] Run Helmsman workflows
 - [ ] Verify deployment

### Path 3: "I've Deployed MOSIP Before"

**Quick reference for common tasks:**

- **New deployment**: Follow Quick Start in [Main README](../README.md)
- **Updating configurations**: [DSF Configuration Guide](DSF_CONFIGURATION_GUIDE.md)
- **Troubleshooting**: Check component-specific READMEs
- **Cleanup**: [Environment Destruction Guide](ENVIRONMENT_DESTRUCTION_GUIDE.md)

---

## Find What You Need

### By Task

| I Want To... | Read This |
|--------------|-----------|
| Understand what "Kubernetes" means | [Glossary](GLOSSARY.md#kubernetes-k8s) |
| Generate SSH keys | [Secret Generation Guide - SSH Keys](SECRET_GENERATION_GUIDE.md#1-ssh-keys) |
| Get AWS credentials | [Secret Generation Guide - AWS Credentials](SECRET_GENERATION_GUIDE.md#3-aws-credentials) |
| Run my first workflow | [Workflow Guide - Base Infrastructure](WORKFLOW_GUIDE.md#workflow-1-base-infrastructure) |
| Understand dry-run vs apply | [Workflow Guide - Parameters](WORKFLOW_GUIDE.md#terraform-apply-checkbox) |
| Fix "clusterid not found" error | [DSF Configuration Guide - clusterid](DSF_CONFIGURATION_GUIDE.md#clusterid-monitoring_stackrancher-only) |
| Configure PostgreSQL | [DSF Configuration Guide - PostgreSQL](DSF_CONFIGURATION_GUIDE.md#2-postgresql-configuration) |
| Add reCAPTCHA keys | [DSF Configuration Guide - reCAPTCHA](DSF_CONFIGURATION_GUIDE.md#3-recaptcha-configuration) |
| Delete my environment | [Environment Destruction Guide](ENVIRONMENT_DESTRUCTION_GUIDE.md) |
| Check costs after deletion | [Environment Destruction Guide - Cost Monitoring](ENVIRONMENT_DESTRUCTION_GUIDE.md#cost-monitoring) |
| Understand workflows | [Workflow Guide - Understanding Workflow Basics](WORKFLOW_GUIDE.md#understanding-workflow-basics) |

### By Technology

| Technology | Learn About It | Use It |
|------------|----------------|--------|
| **AWS** | [Glossary - AWS](GLOSSARY.md#aws-amazon-web-services) | [Main README - AWS Setup](../README.md#prerequisites) |
| **Terraform** | [Glossary - Terraform](GLOSSARY.md#terraform) | [Terraform README](../terraform/README.md) |
| **Kubernetes** | [Glossary - Kubernetes](GLOSSARY.md#kubernetes-k8s) | All deployment guides |
| **Helmsman** | [Glossary - Helmsman](GLOSSARY.md#helmsman) | [DSF Configuration Guide](DSF_CONFIGURATION_GUIDE.md) |
| **WireGuard** | [Glossary - WireGuard](GLOSSARY.md#wireguard) | [WireGuard Setup Guide](../terraform/base-infra/WIREGUARD_SETUP.md) |
| **GitHub Actions** | [Glossary - GitHub Actions](GLOSSARY.md#github-actions) | [Workflow Guide](WORKFLOW_GUIDE.md) |

### By Error Message

| Error | Solution |
|-------|----------|
| "clusterid not found" | [DSF Configuration Guide - clusterid](DSF_CONFIGURATION_GUIDE.md#clusterid-monitoring_stackrancher-only) |
| "Authentication failed" | [Secret Generation Guide - AWS Credentials](SECRET_GENERATION_GUIDE.md#3-aws-credentials) |
| "InsufficientInstanceCapacity" | [Main README - AWS Capacity Issues](../README.md#aws-capacity-issues) |
| "Namespace stuck in Terminating" | [Environment Destruction Guide - Troubleshooting](ENVIRONMENT_DESTRUCTION_GUIDE.md#issue-2-namespace-stuck-in-terminating-state) |
| "Can't find workflow" | [Workflow Guide - Issue 1](WORKFLOW_GUIDE.md#issue-1-workflow-not-found) |
| "Helmsman dry-run fails" | [Workflow Guide - Issue 5](WORKFLOW_GUIDE.md#issue-5-helmsman-dry-run-fails) |

---

## Documentation Features

### What Makes Our Docs Beginner-Friendly?

✅ **Plain Language**
- Every technical term explained
- No assumptions about prior knowledge
- Real-world analogies and examples

✅ **Step-by-Step Instructions**
- Numbered steps you can follow exactly
- "What you should see" at each step
- Clear success/failure indicators

✅ **Visual Guidance**
- Where to click in GitHub interface
- What buttons to press
- Expected output examples

✅ **Comprehensive Examples**
- Real configuration examples
- Before/after comparisons
- Common patterns explained

✅ **Links to Official Docs**
- Every tool linked to official documentation
- Additional learning resources
- Community support channels

✅ **Troubleshooting Sections**
- Common errors and solutions
- "What went wrong" explanations
- Recovery procedures

---

## Getting Help

### When You're Stuck

1. **Check the relevant guide** - Use the tables above to find what you need
2. **Search for error messages** - Use Ctrl+F in documentation
3. **Review troubleshooting sections** - Each guide has a troubleshooting section
4. **Check official documentation** - Follow links to tool-specific docs
5. **Ask the community** - Open a GitHub issue with details

### What to Include When Asking for Help

- **What you're trying to do**: "Deploy base infrastructure"
- **What guide you're following**: "Step 3a in Main README"
- **What happened**: Error message or unexpected behavior
- **What you expected**: What you thought would happen
- **What you've tried**: Steps you took to fix it

---

## Documentation Conventions

### Symbols Used

| Symbol | Meaning |
|--------|---------|
| | Important for beginners |
| | Helpful tip or explanation |
| | Warning - pay attention! |
| ✅ | Recommended action |
| ❌ | Action to avoid |
| | Link to external documentation |
| | Link to our documentation |
| | Step-by-step guide available |
| | Security-related |
| | Deletion/cleanup related |

### Text Formatting

- **Bold**: Important terms, action items
- `Code`: Commands, file names, values to copy
- > Blockquotes: Important notes, warnings
- ```code blocks```: Multi-line commands, configuration examples

---

## Contributing to Documentation

Found something unclear? Want to add more examples? Contributions welcome!

1. **Report issues**: Open a GitHub issue describing what's confusing
2. **Suggest improvements**: What would make docs clearer?
3. **Share your experience**: What worked? What didn't?
4. **Preview the docs site locally** before opening a PR (the `docs` check runs the same strict build):

```bash
pip install -r docs/requirements.txt
mkdocs serve                 # http://127.0.0.1:8000
mkdocs build --strict        # fails on broken links or anchors
```

New pages must be added to `nav:` in `mkdocs.yml`.

**Preview the site on your fork:** Settings → Pages → Source **GitHub Actions**; Settings → Environments → `github-pages` → allow your branch; then **Actions → docs → Run workflow** on that branch. The site is published to `https://<your-user>.github.io/infra/`.

The "Run workflow" form pictures (`_images/workflows/*.svg`) are generated from the workflow files — after changing a workflow's inputs run `python .github/mkdocs/render_workflow_forms.py` and commit the result ([details](../.github/workflows/README.md#workflow-form-images-docs)).

---

## Quick Reference Cards

### Essential Commands Cheat Sheet

```bash
# Check Kubernetes cluster
kubectl get nodes
kubectl get namespaces
kubectl get pods --all-namespaces

# Check specific services
kubectl get pods -A
kubectl get pods -n postgres
kubectl get svc -n istio-system

# View logs
kubectl logs <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace> --follow

# Describe resources
kubectl describe pod <pod-name> -n <namespace>
kubectl describe svc <service-name> -n <namespace>
```

### Deployment Checklist

- [ ] Read [Glossary](GLOSSARY.md) if new to cloud
- [ ] Generate all secrets ([Guide](SECRET_GENERATION_GUIDE.md))
- [ ] Fill in `profiles/<profile>/aws/*.tfvars` (and `base-infra/aws.tfvars`)
- [ ] Deploy base infrastructure ([Workflow Guide](WORKFLOW_GUIDE.md))
- [ ] Set up WireGuard VPN ([Setup Guide](../terraform/base-infra/WIREGUARD_SETUP.md))
- [ ] Deploy main infrastructure ([Workflow Guide](WORKFLOW_GUIDE.md))
- [ ] Set Helmsman environment variables/secrets ([DSF Guide](DSF_CONFIGURATION_GUIDE.md))
- [ ] Deploy prerequisites & external services
- [ ] Deploy MOSIP core services
- [ ] Deploy test rigs (optional)
- [ ] Verify deployment
- [ ] Document your deployment

---

**Need to go back?** [Return to Main README](../README.md)

**Have questions?** Open an issue on GitHub!
