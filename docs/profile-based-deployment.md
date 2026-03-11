# Profile-Based Deployment Architecture

> **Author:** Bhuminathan  
> **Date:** 12 March 2026  
> **Purpose:** Engineering Review — Summary of all infra changes for profile-based multi-version deployment

---

## 1. Problem Statement

Our existing infra repo had a **single flat set of DSF files and tfvars** that only supported deploying the full MOSIP platform (Java 11 / v1.2.1.0). We needed to:

1. Support **multiple MOSIP platform versions** side-by-side (Java 11 and Java 21)
2. Support **standalone eSignet deployment** (v1.7.1) without the full MOSIP platform
3. Make the deployment pipeline **generic** — adding a new profile in the future should require minimal workflow changes
4. Ensure **Terraform state isolation** — each profile gets its own state file so they don't collide

---

## 2. What Changed (Overview)

| Area | Files Changed | What |
|------|--------------|------|
| **Helmsman DSFs** | 15 files (moved + created) | Profile-based directory structure |
| **GitHub Actions (Helmsman)** | 4 workflows | Profile input + generic push detection |
| **GitHub Actions (Terraform)** | 2 workflows | Profile input + profile-aware tfvars path |
| **Terraform Backend** | 1 script | Profile-aware state file naming |
| **Terraform tfvars** | 2 new files | Per-profile infrastructure sizing |

---

## 3. Helmsman DSF — Profile Directory Structure

### Before (flat):
```
Helmsman/dsf/
├── prereq-dsf.yaml
├── external-dsf.yaml
├── mosip-dsf.yaml
├── esignet-dsf.yaml
└── testrigs-dsf.yaml
```

### After (profile-based):
```
Helmsman/dsf/
├── mosip-platform-java11/          ← MOSIP 1.2.1.0 (Java 11)
│   ├── prereq-dsf.yaml
│   ├── external-dsf.yaml
│   ├── mosip-dsf.yaml
│   ├── esignet-dsf.yaml            (eSignet v1.4.1)
│   └── testrigs-dsf.yaml
├── mosip-platform-java21/          ← MOSIP 1.3.0 (Java 21) — ready for version updates
│   ├── prereq-dsf.yaml
│   ├── external-dsf.yaml
│   ├── mosip-dsf.yaml
│   ├── esignet-dsf.yaml
│   └── testrigs-dsf.yaml
└── esignet/                        ← Standalone eSignet v1.7.1
    ├── prereq-dsf.yaml
    ├── external-dsf.yaml            (simplified: postgres, redis, kafka, softhsm, keycloak, captcha only)
    └── esignet-dsf.yaml             (eSignet v1.7.1 + OIDC UI v1.7.1)
```

### Key Differences Between Profiles

| Aspect | mosip-platform-java11 | mosip-platform-java21 | esignet |
|--------|----------------------|----------------------|---------|
| eSignet version | v1.4.1 | v1.4.1 (update pending) | **v1.7.1** |
| OIDC UI version | 1.4.1 | 1.4.1 (update pending) | **1.7.1** |
| DB branch | v1.4.1 | v1.4.1 (update pending) | **v1.7.1** |
| External services | Full (minio, clamav, activemq, etc.) | Full | **Minimal** (postgres, redis, kafka, softhsm, keycloak, captcha) |
| MOSIP platform | ✅ Full (IDA, IDRepo, PMS, etc.) | ✅ Full | ❌ None |
| Test rigs | ✅ | ✅ | ❌ |
| Mock services | Enabled | Enabled | Disabled by default |

---

## 4. Helmsman Workflows — Profile Input + Generic Push

### 4.1 Changes Applied to All 4 Workflows

| Workflow | Profile Dropdown Options | DSF File Used |
|----------|------------------------|---------------|
| `helmsman_external.yml` | mosip-platform-java11, mosip-platform-java21, esignet | `dsf/{profile}/prereq-dsf.yaml` + `dsf/{profile}/external-dsf.yaml` |
| `helmsman_esignet.yml` | mosip-platform-java11, mosip-platform-java21, esignet | `dsf/{profile}/esignet-dsf.yaml` |
| `helmsman_mosip.yml` | mosip-platform-java11, mosip-platform-java21 | `dsf/{profile}/mosip-dsf.yaml` |
| `helmsman_testrigs.yml` | mosip-platform-java11, mosip-platform-java21 | `dsf/{profile}/testrigs-dsf.yaml` |

### 4.2 Generic Push Triggers (Glob Patterns)

Push paths now use `**` globs so new profiles are auto-detected:

```yaml
# Before (had to list every profile):
paths:
  - Helmsman/dsf/mosip-platform-java11/mosip-dsf.yaml
  - Helmsman/dsf/mosip-platform-java21/mosip-dsf.yaml

# After (generic):
paths:
  - Helmsman/dsf/**/mosip-dsf.yaml
```

### 4.3 Generic Push Profile Detection

On push, the profile is **dynamically extracted** from the changed file path:

```bash
# Extracts "mosip-platform-java21" from "Helmsman/dsf/mosip-platform-java21/mosip-dsf.yaml"
PROFILE=$(echo "$CHANGED_FILES" | grep 'mosip-dsf.yaml' | head -1 | sed 's|Helmsman/dsf/\([^/]*\)/.*|\1|')
```

No hardcoded profile names in detection logic — adding a new profile directory just works.

### 4.4 Workflow Chaining Logic

```
helmsman_external (esignet profile)
  └── STOPS here (no MOSIP platform needed)

helmsman_external (mosip-platform-* profile)
  └── chains to → helmsman_mosip (auto-detected via startsWith('mosip-platform-'))
      └── chains to → helmsman_testrigs (commented out, pending stabilization)
```

The chaining condition uses `startsWith(github.event.inputs.profile, 'mosip-platform-')` — any future `mosip-platform-*` profile auto-chains.

---

## 5. Deployment Flows

### Flow A: Full MOSIP Platform (mosip-platform-java11 or mosip-platform-java21)

```
1. helmsman_external.yml  →  prereq-dsf.yaml + external-dsf.yaml
                                (istio, monitoring, postgres, kafka, minio, clamav, etc.)
2. helmsman_mosip.yml     →  mosip-dsf.yaml
                                (IDA, IDRepo, PMS, PreReg, Kernel, Resident)
3. helmsman_esignet.yml   →  esignet-dsf.yaml
                                (eSignet v1.4.1, OIDC UI, partner onboarding)
4. helmsman_testrigs.yml  →  testrigs-dsf.yaml
                                (API test rigs)
```

### Flow B: Standalone eSignet (esignet profile)

```
1. helmsman_external.yml  →  prereq-dsf.yaml + external-dsf.yaml
                                (istio, monitoring, postgres, redis, kafka, softhsm, keycloak, captcha)
2. helmsman_esignet.yml   →  esignet-dsf.yaml
                                (eSignet v1.7.1, OIDC UI v1.7.1)
                                (MOSIP DSF check SKIPPED automatically)
```

No `helmsman_mosip` or `helmsman_testrigs` — the `esignet` profile has no `mosip-dsf.yaml` or `testrigs-dsf.yaml`.

---

## 6. Terraform — Profile-Based Infrastructure

### 6.1 Directory Structure

```
terraform/implementations/aws/infra/
├── aws.tfvars                         ← original (used by base-infra / observ-infra)
├── main.tf
├── variables.tf
├── outputs.tf
└── profiles/
    ├── mosip/
    │   └── aws.tfvars                 ← full MOSIP platform sizing
    └── esignet/
        └── aws.tfvars                 ← lightweight standalone eSignet sizing
```

### 6.2 Infrastructure Sizing Differences

| Resource | mosip profile | esignet profile |
|----------|:------------:|:--------------:|
| Instance type (K8s nodes) | t3a.2xlarge | t3a.xlarge |
| Instance type (Nginx) | t3a.2xlarge | t3a.xlarge |
| Control plane nodes | 3 | 2 |
| ETCD nodes | 3 | 2 |
| Worker nodes | 2 | 1 |
| EBS volume 1 | 300 GB | 200 GB |
| EBS volume 2 | 200 GB | 0 (disabled) |
| Public subdomains | 5 (resident, prereg, esignet, healthservices, signup) | 2 (esignet, signup) |
| Internal subdomains | 11 | 4 (iam, kafka, postgres, keycloak) |

### 6.3 Workflow Changes (terraform.yml + terraform-destroy.yml)

Both workflows now have an **INFRA_PROFILE** input:

```yaml
INFRA_PROFILE:
  description: 'Infrastructure profile (only for infra component)'
  type: choice
  options:
    - mosip
    - esignet
  default: mosip
```

- Profile is **only used for `infra` component** — `base-infra` and `observ-infra` are shared (no profiles)
- Tfvars path: `profiles/{profile}/aws.tfvars`
- Concurrency groups include profile — `mosip` and `esignet` runs don't block each other

### 6.4 State File Isolation

The `configure-backend.sh` script now accepts `--profile` and includes it in state file naming:

| Backend | mosip | esignet |
|---------|-------|---------|
| **Local** | `aws-infra-mosip-main-terraform.tfstate` | `aws-infra-esignet-main-terraform.tfstate` |
| **S3** | key: `aws-infra-mosip-main-terraform.tfstate` | key: `aws-infra-esignet-main-terraform.tfstate` |
| **Azure** | key: `azure-infra-mosip-main-terraform.tfstate` | key: `azure-infra-esignet-main-terraform.tfstate` |
| **GCS** | prefix: `terraform/gcp-infra-mosip-main` | prefix: `terraform/gcp-infra-esignet-main` |

**Without this fix**, running terraform apply with `mosip` then `esignet` would have used the **same state file** — destroying mosip infra and recreating esignet infra.

---

## 7. Adding a New Profile in the Future

### Helmsman (e.g., adding `mosip-platform-java25`):

1. Create `Helmsman/dsf/mosip-platform-java25/` with the DSF files
2. Add `mosip-platform-java25` to the `workflow_dispatch` choice options in the relevant workflows
3. **That's it** — push triggers (glob) and profile detection (sed extraction) are generic

### Terraform (e.g., adding `inji`):

1. Create `terraform/implementations/aws/infra/profiles/inji/aws.tfvars`
2. Add `inji` to the `INFRA_PROFILE` choice options in `terraform.yml` and `terraform-destroy.yml`
3. **That's it** — state file naming and backend config auto-include the profile

---

## 8. Files Changed Summary

| # | File | Change Type | Description |
|---|------|-------------|-------------|
| 1 | `Helmsman/dsf/mosip-platform-java11/*` | Renamed (git mv) | Moved from flat `dsf/` to profile dir |
| 2 | `Helmsman/dsf/mosip-platform-java21/*` | Added (copy) | Copy of java11, ready for java21 version updates |
| 3 | `Helmsman/dsf/esignet/prereq-dsf.yaml` | Renamed (git mv) | Same as mosip-platform prereq |
| 4 | `Helmsman/dsf/esignet/external-dsf.yaml` | New | Simplified external services for standalone eSignet |
| 5 | `Helmsman/dsf/esignet/esignet-dsf.yaml` | New | eSignet v1.7.1 standalone DSF |
| 6 | `.github/workflows/helmsman_external.yml` | Modified | Profile input, glob push, generic matrix detection |
| 7 | `.github/workflows/helmsman_esignet.yml` | Modified | Profile input, glob push, generic detection |
| 8 | `.github/workflows/helmsman_mosip.yml` | Modified | Profile input, glob push, generic detection |
| 9 | `.github/workflows/helmsman_testrigs.yml` | Modified | Profile input added, glob push, generic detection |
| 10 | `.github/workflows/terraform.yml` | Modified | INFRA_PROFILE input, profile-aware tfvars path |
| 11 | `.github/workflows/terraform-destroy.yml` | Modified | INFRA_PROFILE input, profile-aware tfvars path |
| 12 | `.github/scripts/configure-backend.sh` | Modified | `--profile` flag, profile in state file names |
| 13 | `terraform/.../profiles/mosip/aws.tfvars` | New | Full MOSIP platform infra sizing |
| 14 | `terraform/.../profiles/esignet/aws.tfvars` | New | Lightweight standalone eSignet sizing |

---

## 9. Pending / Next Steps

- [ ] **Update `mosip-platform-java21` DSFs** — currently identical copies of java11; need to update chart versions, image tags, and DB branches for Java 21 / MOSIP 1.3.0
- [ ] **Hook scripts** — not touched yet (`Helmsman/hooks/*`); will review one by one
- [ ] **Partner onboarding stabilization** — workflow-caller in `helmsman_mosip.yml` is commented out
- [ ] **eSignet profile tfvars** — placeholder values need real values before first deployment
