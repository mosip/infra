# Repository Tree Structure

A full directory map of this repo, generated `2026-09-01`. State files
(`*.tfstate*`, `*.gpg`), `.terraform/` caches, and lockfiles are omitted.
For what each top-level directory is *for*, see `AGENTS.md`'s "Repository
layout" section — this doc is the detailed map, that one is the summary.

## Top level

```
.
├── .github/                      # CI workflows + backend/state helper scripts
├── ansible/                      # Configuration playbooks (rke2, nginx, nfs, postgresql, activemq, rancher-import, rancher-keycloak-setup)
├── docs/                         # Deep-dive guides (workflow, DSF, Helmsman, secrets, glossary...)
├── Helmsman/                     # Desired State Files + install-lifecycle hooks + chart values for MOSIP services
├── Rancher-keycloak-integration/ # Standalone Rancher <-> Keycloak automation scripts
├── terraform/                    # All infrastructure-as-code (see below)
├── AGENTS.md                     # Guardrails + conventions for AI agents working in this repo
├── README.md                     # Top-level deployment model + architecture overview
└── .gitignore
```

## `terraform/` — full detail

The core of the repo, and where the #273 decoupling work lives. Layout:

```
terraform/
├── base-infra/                   # One-time-per-cloud: VPC, networking, WireGuard jumpserver
│   ├── aws/
│   │   ├── jumpserver-setup.sh.tpl
│   │   ├── main.tf
│   │   ├── outputs.tf
│   │   └── variables.tf
│   ├── azure/
│   │   ├── main.tf
│   │   ├── outputs.tf
│   │   └── variables.tf
│   ├── gcp/
│   │   ├── main.tf
│   │   ├── outputs.tf
│   │   └── variables.tf
│   ├── main.tf                   # Cloud-agnostic dispatcher (cloud_provider switch)
│   ├── outputs.tf
│   ├── variables.tf
│   └── WIREGUARD_SETUP.md
│
├── infra/                        # Cloud-agnostic wrapper — calls the LEGACY monolith module
│   ├── aws/{main,outputs,variables}.tf
│   ├── azure/{main,outputs,variables}.tf
│   ├── gcp/{main,outputs,variables}.tf
│   └── main.tf, outputs.tf, variables.tf
│
├── observ-infra/                 # Cloud-agnostic wrapper for the observability cluster (Rancher UI + Keycloak)
│   ├── aws/{main,outputs,variables}.tf
│   ├── azure/{main,outputs,variables}.tf
│   ├── gcp/{main,outputs,variables}.tf
│   └── main.tf, outputs.tf, variables.tf
│
├── modules/                      # Reusable modules — where actual resources are defined
│   ├── aws/
│   │   ├── aws-resource-creation/   # LEGACY MONOLITH (pre-#273): EC2+EBS+SG+DNS+RKE2+Rancher+NFS+PG+ActiveMQ in one module
│   │   │   ├── aws-resource-creation-main.tf
│   │   │   ├── certbot-ssl-certgen.tf
│   │   │   ├── outputs.tf, variables.tf
│   │   │   └── README.md
│   │   ├── compute/                 # #273 Layer 2 — decoupled EC2 (own state)
│   │   │   ├── tests/main.tftest.hcl
│   │   │   ├── main.tf, outputs.tf, variables.tf
│   │   │   └── rke-user-data.sh.tpl
│   │   ├── dns/                     # #273 Layer 2 — decoupled Route53 (#277)
│   │   │   ├── tests/main.tftest.hcl
│   │   │   └── main.tf, outputs.tf, variables.tf
│   │   ├── iam/                     # #273 — decoupled IAM (instance profiles etc.)
│   │   │   ├── tests/main.tftest.hcl
│   │   │   └── main.tf, outputs.tf, variables.tf
│   │   ├── security/                # #273 Layer 1 — decoupled security groups (#274)
│   │   │   ├── tests/main.tftest.hcl
│   │   │   └── main.tf, outputs.tf, variables.tf
│   │   ├── storage/                 # #273 Layer 2 — decoupled EBS (#276)
│   │   │   ├── tests/main.tftest.hcl
│   │   │   └── main.tf, outputs.tf, variables.tf
│   │   ├── nfs-setup/                {nfs-csi.sh, nfs-setup-main.tf, README.md}
│   │   ├── nginx-setup/              {nginx-setup.sh, nginx-setup-main.tf, README.md}
│   │   ├── postgresql-setup/         {main.tf, postgresql-setup.sh}
│   │   ├── rancher-keycloak-setup/   {ansible/*.yml, main.tf, outputs.tf, variables.tf}
│   │   ├── rke2-cluster/             {ansible/*, main.tf, README.md}
│   │   ├── aws-main.tf, outputs.tf, variables.tf, README.md
│   ├── azure/  {main.tf, azure.tfvars, README.md}
│   └── gcp/    {main.tf, gcp.tfvars, README.md}
│
├── implementations/               # Per-cloud Terraform ROOTS — what CI actually applies
│   ├── aws/
│   │   ├── base-infra/            {aws.tfvars, main.tf}
│   │   ├── infra/                 # legacy monolith root + the 5 new #273 decoupled roots
│   │   │   ├── compute/  {profiles/, main.tf, outputs.tf, variables.tf}
│   │   │   ├── dns/      {profiles/, main.tf, outputs.tf, variables.tf}
│   │   │   ├── iam/      {profiles/, main.tf, outputs.tf, variables.tf}
│   │   │   ├── security/ {profiles/, main.tf, outputs.tf, variables.tf}
│   │   │   ├── storage/  {profiles/, main.tf, outputs.tf, variables.tf}
│   │   │   ├── profiles/{esignet-standalone/, mosip/}
│   │   │   └── backend.tf, main.tf, outputs.tf, variables.tf   # legacy monolith root
│   │   └── observ-infra/
│   │       ├── compute/ {aws.tfvars, main.tf, outputs.tf, variables.tf}
│   │       ├── dns/     {aws.tfvars, main.tf, outputs.tf, variables.tf}
│   │       ├── iam/     {aws.tfvars, main.tf, outputs.tf, variables.tf}
│   │       ├── security/{aws.tfvars, main.tf, outputs.tf, variables.tf}
│   │       ├── storage/ {aws.tfvars, main.tf, outputs.tf, variables.tf}
│   │       └── aws.tfvars, common.tfvars, main.tf, outputs.tf, variables.tf
│   ├── azure/
│   │   ├── base-infra/  {azure.tfvars, main.tf}
│   │   ├── infra/       {azure.tfvars, main.tf, outputs.tf, variables.tf}
│   │   └── observ-infra/{azure.tfvars}
│   └── gcp/
│       ├── base-infra/  {gcp.tfvars, main.tf}
│       ├── infra/       {gcp.tfvars, main.tf, outputs.tf, variables.tf}
│       └── observ-infra/{gcp.tfvars}
│
└── README.md
```

*(azure/ and gcp/ under `implementations/` and `modules/` don't yet have
the #273 layered split or a `datacenter/` counterpart — see AGENTS.md's
"Vision / roadmap" section.)*

## `ansible/` — full detail

```
ansible/
├── activemq/            {defaults/main.yml, tasks/main.yml, playbook.yml}
├── nfs/                 {defaults/main.yml, tasks/main.yml, playbook.yml}
├── nginx/               {defaults/main.yml, tasks/main.yml, playbook.yml}
├── postgresql/          {defaults/main.yml, handlers/main.yml, tasks/main.yml, playbook.yml}
├── rancher-import/      {defaults/main.yml, tasks/main.yml, playbook.yml}
├── rancher-keycloak-setup/  {vars/defaults.yml, get-keycloak-info.yml, get-rancher-info.yml, install-keycloak.yml, install-rancher.yml, playbook.yml}
├── rke2/                {defaults/main.yml, tasks/{check_cluster,kubeconfig,primary,subsequent,token}.yml, playbook.yml}
└── inventory.example.yml   # includes a sample on-prem/data-center inventory (docs commit fb0c8ca8)
```

## `.github/` — full detail

```
.github/
├── scripts/              # Backend/state management shell scripts invoked by terraform.yml
│   ├── cleanup-state-locking.sh, configure-backend.sh
│   ├── decrypt-state.sh, encrypt-state.sh, setup-gpg.sh
│   ├── generate-ansible-inventory.sh, generate-pg-secrets.sh
│   ├── rancher-fetch-kubeconfig.sh, rancher-grant-cluster-access.sh, rancher-register-cluster.sh
│   ├── setup-cloud-storage.sh, setup-remote-storage.sh, setup-s3-backend.sh
│   ├── test-cleanup-state-locking.sh, test-infrastructure.sh, test-state-locking.sh
│   ├── test-workflow-e2e.sh, validate-workflow-integration.sh, wg-env.sh
│   ├── README.md, WORKFLOW_TESTING_GUIDE.md
└── workflows/
    ├── terraform.yml               # Main provisioning entrypoint (manual dispatch)
    ├── terraform-destroy.yml
    ├── destroy-resources.yml
    ├── k8s_health_check.yml
    ├── keycloak-rancher-integration.yml
    ├── wg-onboard.yml
    ├── helmsman_mosip.yml, helmsman_mosip_destroy.yml
    ├── helmsman_external.yml, helmsman_external_destroy_external.yml, helmsman_external_destroy_prereq.yml
    ├── helmsman_esignet.yml
    ├── helmsman_signup.yml
    ├── helmsman_testrigs.yml, helmsman_testrigs_destroy.yml
    └── README.md
```

## `docs/`

```
docs/
├── _images/                              # Architecture diagrams (referenced from README.md)
├── ONBOARDING_GUIDE.md
├── WORKFLOW_GUIDE.md
├── TERRAFORM_WORKFLOW_GUIDE.md            # terraform.yml dispatch inputs, explained
├── DSF_CONFIGURATION_GUIDE.md
├── HELMSMAN_MOSIP_GUIDE.md, HELMSMAN_EXTERNAL_GUIDE.md, HELMSMAN_TESTRIGS_GUIDE.md, HELMSMAN_DESTROY_GUIDE.md
├── ESIGNET_STANDALONE_DEPLOYMENT_GUIDE.md, esignet_README.md
├── ENVIRONMENT_DESTRUCTION_GUIDE.md
├── k8s-health-checker.md
├── RECAPTCHA_SETUP_GUIDE.md
├── SECRET_GENERATION_GUIDE.md
├── GLOSSARY.md
├── profile-based-deployment.drawio
├── TREE_STRUCTURE.md                      # this file
└── README.md
```

## `Helmsman/` — summarized (171 files total; full listing not useful here)

```
Helmsman/
├── dsf/                           # Desired State Files, one set per platform profile
│   ├── mosip-platform-1.2.0.x/    {mosip,esignet,external,prereq,testrigs}-dsf.yaml
│   ├── mosip-platform-1.2.1.x/    {mosip,esignet,external,prereq,testrigs}-dsf.yaml
│   ├── esignet-standalone/        {esignet,external,prereq,signup,testrigs}-dsf.yaml
│   └── README.md
├── hooks/                         # ~90 pre/postinstall shell hooks, one per MOSIP service + an
│   │                               esignet-standalone/ subset — see Helmsman/README.md for the
│   │                               DSF hook-lifecycle model before adding new ones
│   └── esignet-standalone/
├── utils/                         # Shared Helm values.yaml files + supporting charts/manifests
│   ├── alerting/, ansible/, copy-cm-and-secrets/, httpbin/,
│   │   istio-addons/, istio-gateway/, istio-mesh/, logging/
│   └── *.yaml  (~30 chart values files: config-server, esignet, kafka,
│                keycloak, postgres, softhsm, monitoring, ...)
├── helmsman-workflow-guide.md
└── README.md
```

## `Rancher-keycloak-integration/`

```
Rancher-keycloak-integration/
├── automation_script.py
├── rancher_diagnostic.py
├── README.md
└── WORKFLOW_USAGE.md
```
