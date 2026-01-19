# 🎯 eSignet DSF Demo Guide

> **Demo Date:** January 19, 2026  
> **Presenter:** Bhuminathan  
> **Duration:** ~30 minutes

---

## 📋 Table of Contents

1. [Overview](#overview)
2. [Architecture Flow Diagram](#architecture-flow-diagram)
3. [GitHub Actions Workflow Flow](#github-actions-workflow-flow)
4. [Component Deployment Order](#component-deployment-order)
5. [Key Demo Points](#key-demo-points)
6. [Live Demo Steps](#live-demo-steps)
7. [Troubleshooting](#troubleshooting)

---

## 🎯 Overview

### What is eSignet DSF?

**eSignet DSF (Desired State File)** is a Helmsman configuration that automates the deployment of the complete eSignet identity authentication stack on Kubernetes.

### What does it deploy?

| Component | Purpose | Namespace |
|-----------|---------|-----------|
| PostgreSQL Init | Database schema for eSignet & Mock Identity System | `esignet` |
| Redis | Session caching and token storage | `redis` |
| SoftHSM (eSignet) | Hardware Security Module for key management | `softhsm` |
| Keycloak Init | IAM configuration for eSignet | `esignet` |
| Artifactory | Artifact storage | `artifactory-1202` |
| eSignet | Core identity authentication service | `esignet` |
| OIDC UI | User interface for authentication | `esignet` |
| Mock Identity System | Test identity provider | `esignet` |
| Mock Relying Party | Demo application consuming eSignet | `esignet` |
| Partner Onboarder | OIDC partner registration | `esignet` |

---

## 🏗️ Architecture Flow Diagram

```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                              eSignet DSF Architecture                                │
└─────────────────────────────────────────────────────────────────────────────────────┘

                                    ┌─────────────┐
                                    │   GitHub    │
                                    │  Actions    │
                                    └──────┬──────┘
                                           │
                            ┌──────────────┼──────────────┐
                            │              │              │
                            ▼              ▼              ▼
                    ┌───────────┐  ┌───────────┐  ┌───────────┐
                    │  Push to  │  │  Manual   │  │ Scheduled │
                    │  Branch   │  │  Trigger  │  │    Run    │
                    └─────┬─────┘  └─────┬─────┘  └─────┬─────┘
                          │              │              │
                          └──────────────┼──────────────┘
                                         │
                                         ▼
                              ┌─────────────────────┐
                              │    helmsman_       │
                              │    esignet.yml     │
                              │    Workflow        │
                              └──────────┬─────────┘
                                         │
                    ┌────────────────────┼────────────────────┐
                    │                    │                    │
                    ▼                    ▼                    ▼
           ┌──────────────┐    ┌──────────────┐    ┌──────────────┐
           │   Setup      │    │   Validate   │    │    VPN       │
           │   kubectl    │    │   Secrets    │    │  WireGuard   │
           └──────┬───────┘    └──────┬───────┘    └──────┬───────┘
                  │                   │                    │
                  └───────────────────┼────────────────────┘
                                      │
                                      ▼
                           ┌─────────────────────┐
                           │      Helmsman       │
                           │   --keep-untracked  │
                           │   --apply           │
                           └──────────┬──────────┘
                                      │
                                      ▼
                           ┌─────────────────────┐
                           │   esignet-dsf.yaml  │
                           │   (Desired State)   │
                           └──────────┬──────────┘
                                      │
          ┌───────────────────────────┼───────────────────────────┐
          │                           │                           │
          ▼                           ▼                           ▼
┌─────────────────┐         ┌─────────────────┐         ┌─────────────────┐
│   PRIORITY: -18 │         │   PRIORITY: -14 │         │   PRIORITY: -7  │
│   to -16        │         │   to -10        │         │   to -3         │
│                 │         │                 │         │                 │
│  ┌───────────┐  │         │  ┌───────────┐  │         │  ┌───────────┐  │
│  │ PostgreSQL│  │         │  │ SoftHSM   │  │         │  │ Mock ID   │  │
│  │   Init    │  │         │  │ (eSignet) │  │         │  │  System   │  │
│  └───────────┘  │         │  └───────────┘  │         │  └───────────┘  │
│  ┌───────────┐  │         │  ┌───────────┐  │         │  ┌───────────┐  │
│  │   Redis   │  │         │  │ Keycloak  │  │         │  │ Mock RP   │  │
│  │           │  │         │  │   Init    │  │         │  │  Service  │  │
│  └───────────┘  │         │  └───────────┘  │         │  └───────────┘  │
│                 │         │  ┌───────────┐  │         │  ┌───────────┐  │
│  Infrastructure │         │  │ eSignet   │  │         │  │ Partner   │  │
│     Layer       │         │  │ + OIDC UI │  │         │  │ Onboarder │  │
└─────────────────┘         │  └───────────┘  │         │  └───────────┘  │
                            │  Core Services  │         │  Demo/Testing   │
                            └─────────────────┘         └─────────────────┘
                                      │
                                      ▼
                           ┌─────────────────────┐
                           │  ☑️ Label namespace  │
                           │  esignet-dsf=       │
                           │  completed          │
                           └─────────────────────┘
```

---

## 🔄 GitHub Actions Workflow Flow

```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                         GitHub Actions Workflow Steps                                │
└─────────────────────────────────────────────────────────────────────────────────────┘

    START
      │
      ▼
┌─────────────────────────────────────────────────────────────────┐
│  TRIGGER                                                        │
│  ├── Push to: Helmsman/dsf/esignet-dsf.yaml                    │
│  ├── Manual: workflow_dispatch (dry-run / apply)               │
│  └── Environment: Based on branch name                         │
└─────────────────────────────────────────────────────────────────┘
      │
      ▼
┌─────────────────────────────────────────────────────────────────┐
│  1️⃣  SETUP PHASE                                                │
│  ├── Checkout repository                                        │
│  ├── Mask sensitive secrets (add-mask)                         │
│  ├── Install kubectl v1.31.3                                   │
│  └── Configure kubeconfig from secrets                         │
└─────────────────────────────────────────────────────────────────┘
      │
      ▼
┌─────────────────────────────────────────────────────────────────┐
│  2️⃣  NETWORK PHASE                                              │
│  ├── Enable UFW firewall                                        │
│  ├── Allow SSH & WireGuard (51820/udp)                         │
│  ├── Install WireGuard                                         │
│  └── Start VPN tunnel (wg0)                                    │
└─────────────────────────────────────────────────────────────────┘
      │
      ▼
┌─────────────────────────────────────────────────────────────────┐
│  3️⃣  TOOLS PHASE                                                │
│  ├── Install Helm v3                                           │
│  ├── Install Helmsman v3.17.1                                  │
│  └── Verify cluster connectivity                               │
└─────────────────────────────────────────────────────────────────┘
      │
      ▼
┌─────────────────────────────────────────────────────────────────┐
│  4️⃣  VALIDATION PHASE                                           │
│  ├── Check mosip-dsf label (unless standalone mode)            │
│  ├── Validate required secrets:                                │
│  │   ├── MOCK_RELYING_PARTY_CLIENT_PRIVATE_KEY                 │
│  │   ├── MOCK_RELYING_PARTY_JWE_PRIVATE_KEY                    │
│  │   ├── ESIGNET_CAPTCHA_SITE_KEY                              │
│  │   └── ESIGNET_CAPTCHA_SECRET_KEY                            │
│  └── Fetch DB_USER_PASSWORD from postgres namespace            │
└─────────────────────────────────────────────────────────────────┘
      │
      ▼
┌─────────────────────────────────────────────────────────────────┐
│  5️⃣  DEPLOYMENT PHASE                                           │
│  │                                                              │
│  │   helmsman --${MODE} --keep-untracked-releases \            │
│  │            -f $WORKDIR/dsf/esignet-dsf.yaml                 │
│  │                                                              │
│  │   --keep-untracked-releases: Prevents deletion of           │
│  │   releases managed by other DSF files (postgres-init)       │
│  │                                                              │
└─────────────────────────────────────────────────────────────────┘
      │
      ▼
┌─────────────────────────────────────────────────────────────────┐
│  6️⃣  POST-DEPLOYMENT                                            │
│  ├── Label namespace: esignet-dsf=completed                    │
│  └── Display deployment summary                                │
└─────────────────────────────────────────────────────────────────┘
      │
      ▼
    END
```

---

## 📦 Component Deployment Order

The DSF uses **priority values** to control deployment order (lower = deployed first):

```
Priority Timeline (Lower deploys first)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

-18 ──► postgres (disabled - external)
   │
-17 ──► istio-addons-psql (disabled)
   │
-16 ──► postgres-init-esignet ✅
   │    └── Creates mosip_esignet & mosip_mockidentitysystem DBs
   │
-15 ──► redis ✅
   │    └── Session cache & token storage
   │
-14 ──► softhsm-esignet ✅
   │    └── HSM for eSignet key management
   │
-13 ──► keycloak (disabled - managed by external-dsf)
   │
-12 ──► istio-addons-iam ✅
   │    └── Istio config for Keycloak
   │
-11 ──► esignet-keycloak-init ✅
   │    └── Configure Keycloak realms for eSignet
   │
-11 ──► artifactory-1202 ✅
   │    └── Artifact storage for configs
   │
-10 ──► esignet ✅ ⭐ CORE SERVICE
   │    └── Main eSignet authentication service
   │
-9  ──► oidc-ui ✅
   │    └── User interface for OIDC authentication
   │
-8  ──► softhsm-mock-identity-system ✅
   │    └── HSM for Mock Identity System
   │
-7  ──► mock-identity-system ✅
   │    └── Test identity provider
   │
-6  ──► mock-relying-party-service ✅
   │    └── Demo service consuming eSignet
   │
-5  ──► mock-relying-party-ui ✅
   │    └── Demo UI for testing eSignet
   │
-4  ──► esignet-resident-oidc-partner-onboarder ✅
   │    └── Register eSignet & resident-oidc partners
   │
-3  ──► esignet-demo-oidc-partner-onboarder ✅
       └── Register demo-oidc partner

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## 🎤 Key Demo Points

### 1. **Multi-DSF Architecture**
```
external-dsf.yaml     ──► postgres, keycloak, minio, config-server
       │
       └── Creates: postgres-init release
       
esignet-dsf.yaml      ──► eSignet stack
       │
       └── Uses: --keep-untracked-releases
           (Prevents deletion of postgres-init)
```

### 2. **Environment-Based Secrets**
```
Repository → Settings → Environments → <branch-name> → Secrets

Required Secrets:
├── KUBECONFIG                          (base64 encoded)
├── CLUSTER_WIREGUARD_WG0               (VPN config)
├── MOCK_RELYING_PARTY_CLIENT_PRIVATE_KEY (base64 PEM)
├── MOCK_RELYING_PARTY_JWE_PRIVATE_KEY    (base64 PEM)
├── ESIGNET_CAPTCHA_SITE_KEY             (plain text)
└── ESIGNET_CAPTCHA_SECRET_KEY           (plain text)
```

### 3. **Dependency Management**
- **mosip-dsf check**: Ensures MOSIP DSF completed before eSignet (unless standalone)
- **DB password**: Fetched dynamically from `postgres` namespace
- **Hooks**: Pre/post install scripts for each component

### 4. **Standalone Mode**
Two ways to enable:
1. **Manual trigger**: Set `skip_mosip_dsf_check: true`
2. **Push trigger**: Set repository variable `ESIGNET_STANDALONE_MODE=true`

---

## 🚀 Live Demo Steps

### Step 1: Show the DSF File
```bash
cat Helmsman/dsf/esignet-dsf.yaml
```
**Point out:**
- Helm repos configuration
- Namespace definitions
- App priorities
- Hooks (pre/post install scripts)

### Step 2: Show the Workflow File
```bash
cat .github/workflows/helmsman_esignet.yml
```
**Point out:**
- Trigger conditions (push + workflow_dispatch)
- Environment secrets setup
- WireGuard VPN configuration
- The `--keep-untracked-releases` flag

### Step 3: Trigger a Dry-Run
1. Go to **Actions** → **Deploy eSignet using Helmsman**
2. Click **Run workflow**
3. Select **dry-run** mode
4. Watch the execution

### Step 4: Show the Helmsman Output
```
2026-01-19 06:50:15 INFO: Parsing DSF...
2026-01-19 06:50:16 INFO: Validating releases...
2026-01-19 06:50:18 NOTICE: -------- PLAN starts here --------------
2026-01-19 06:50:18 INFO: postgres-init-esignet will be installed
2026-01-19 06:50:18 INFO: redis will be installed
...
```

### Step 5: Verify Deployment (if apply mode)
```bash
# Check namespaces
kubectl get ns esignet softhsm keycloak redis

# Check pods
kubectl get pods -n esignet

# Check services
kubectl get svc -n esignet

# Verify label
kubectl get ns default --show-labels | grep esignet-dsf
```

---

## 🔧 Troubleshooting

### Issue: "Untracked release will be deleted"
```
WARNING: Untracked release [ postgres-init ] found and it will be deleted
```
**Solution:** Already fixed! We added `--keep-untracked-releases` flag.

### Issue: "MOSIP DSF not completed"
```
❌ MOSIP DSF not completed. Please run the MOSIP DSF workflow first.
```
**Solution:** Either run MOSIP DSF first, or enable standalone mode.

### Issue: Missing secrets
```
❌ MOCK_RELYING_PARTY_CLIENT_PRIVATE_KEY secret is not configured
```
**Solution:** Add secrets to environment (not repository) secrets.

---

## 📊 Quick Reference Card

| Item | Value |
|------|-------|
| **DSF File** | `Helmsman/dsf/esignet-dsf.yaml` |
| **Workflow** | `.github/workflows/helmsman_esignet.yml` |
| **Helm Repos** | `bitnami`, `mosip` |
| **Namespaces** | `esignet`, `softhsm`, `redis`, `keycloak`, `artifactory-1202` |
| **Total Apps** | 15 (10 enabled) |
| **Deployment Time** | ~30-45 minutes |
| **Label on Success** | `esignet-dsf=completed` |

---

## 📝 Demo Checklist

- [ ] Verify cluster access before demo
- [ ] Ensure all secrets are configured
- [ ] Have external-dsf completed (or use standalone mode)
- [ ] Prepare terminal with kubectl access
- [ ] Have workflow page ready in browser
- [ ] Test WireGuard connection

---

**Good luck with your demo! 🎉**
