# MOSIP Onboarding Guide

This guide provides detailed instructions for handling partner onboarding processes in MOSIP deployments, including troubleshooting failed automated onboarding and performing manual re-onboarding.

## Table of Contents

- [Overview](#overview)
- [Understanding MOSIP Onboarding](#understanding-mosip-onboarding)
- [Identifying Failed Onboarding Processes](#identifying-failed-onboarding-processes)
- [Manual Partner Re-onboarding Procedures](#manual-partner-re-onboarding-procedures)
- [Verification Steps](#verification-steps)

## Overview

Partner onboarding is a critical process in MOSIP deployments that configures authentication and integration partners required for the system to function properly. During automated Helmsman deployments, onboarding processes may occasionally fail due to timing issues, resource constraints, or configuration dependencies.

**When manual onboarding is required:**

- Partner-onboarder pod completes successfully, but MinIO reports show onboarding failures
- Onboarding reports indicate some partners failed to register
- Test rig deployment prerequisites fail due to incomplete onboarding
- Partner-related services are not responding correctly

> **Important**: The partner-onboarder pod will typically complete with a "Completed" status, but this does NOT guarantee all partners were onboarded successfully. You MUST check the onboarding reports in MinIO to verify actual onboarding status.

## Understanding MOSIP Onboarding

### What is Partner Onboarding?

Partner onboarding in MOSIP involves:

- Registering authentication partners (IDA, eSignet, etc.)
- Configuring partner policies and certificates
- Setting up partner API access and credentials
- Establishing trust relationships between MOSIP components

## Identifying Failed Onboarding Processes

### Step 1: Verify Partner-Onboarder Pod Completion

```bash
# Check partner-onboarder pod status
kubectl get pod -n onboarder

# Expected output: Status should be "Completed"
# NAME                           READY   STATUS      RESTARTS   AGE
# partner-onboarder-xxxxx        0/1     Completed   0          5m
```

> **Note**: A "Completed" status only means the pod finished execution, NOT that all onboarding succeeded!

### Step 2: Access MinIO to Check Onboarding Reports

Onboarding reports are stored in MinIO and contain detailed success/failure information for each partner.

#### Access MinIO UI

**Option 1: Via MinIO Direct URL**

- Access MinIO at: `https://minio.sandbox.xyz.net` (replace `sandbox.xyz.net` with your domain)

**Option 2: Via Landing Page**

- Access landing page at: `https://sandbox.xyz.net` (replace with your domain)
- Click on MinIO link

#### Get MinIO Credentials

**If using Rancher UI:**

```bash
# Navigate in Rancher UI:
# 1. Go to your cluster
# 2. Navigate to minio namespace
# 3. Go to Storage → Secrets
# 4. Select s3 secret to find credentials
```

**If deployed without observ-infra:**

```bash
# Get MinIO password using kubectl
kubectl get secret minio -n minio -o jsonpath='{.data.root-password}' | base64 -d
```

**Login credentials:**

- Username: `admin`
- Password: Use the secret retrieved above

### Step 3: Check Onboarding Reports in MinIO

1. **Login to MinIO Console** using credentials from above
2. **Navigate to the `onboarder` bucket**
3. **Go to the `reports` folder**
4. **Download all report files:**
   - `abis` report
   - `print` report
   - `ida` report
   - Other partner reports
5. **Check whether all reports show PASSED status**
   - Open each downloaded report
   - Verify that all partners have successfully onboarded
   - Look for any FAILED or ERROR entries

### Step 4: Review Partner-Onboarder Pod Logs (Optional)

While MinIO reports are the primary source of truth, pod logs can provide additional debugging context:

```bash
# Get partner-onboarder pod name
POD_NAME=$(kubectl get pod -n onboarder -o jsonpath='{.items[0].metadata.name}')

# View pod logs
kubectl logs -n onboarder $POD_NAME

# Search for specific errors
kubectl logs -n onboarder $POD_NAME | grep -i "error\|failed\|exception"

# Check if reports were uploaded to MinIO
kubectl logs -n onboarder $POD_NAME | grep -i "minio\|report uploaded"
```

## Manual Partner Re-onboarding Procedures

### Method 1: Rerun Partner-Onboarder Job (Recommended)

This is the primary method to retry failed onboarding after reviewing MinIO reports.

#### Step 1: Delete the Completed Partner-Onboarder Job

**Option 1: If deployed with observ-infra (Rancher UI available)**

1. **Access Rancher UI**
2. **Navigate to your cluster**
3. **Go to the `onboarder` namespace**
4. **Navigate to Workloads → Jobs**
5. **Delete all jobs that have failed reports**
   - Identify jobs related to failed onboarding reports
   - Select the jobs and delete them

**Option 2: If deployed without Rancher UI (kubectl method)**

```bash
# Find the partner-onboarder job
kubectl get jobs -n onboarder

# Example output:
# NAME                        COMPLETIONS   DURATION   AGE
# partner-onboarder-xxxxx     1/1           2m5s       10m

# Delete the job (replace <job-name> with actual job name)
kubectl delete job <job-name> -n onboarder

# Example:
kubectl delete job partner-onboarder -n onboarder

# Verify deletion
kubectl get jobs -n onboarder
# Should show no results or remaining jobs only
```

#### Step 2: Update mosip-dsf.yaml Configuration

After deleting the failed report jobs, you need to update the `mosip-dsf.yaml` file to configure which modules should be re-onboarded:

1. **Navigate to the mosip-dsf.yaml file:**
   - Location: `Helmsman/dsf/mosip-dsf.yaml`

2. **Find the partner-onboarder app section:**
   - Search for `partner-onboarder:` in the file

3. **Update module enabled status based on report results:**
   - **For successful reports (PASSED)**: Set `enabled: false`
   - **For failed reports (FAILED/ERROR)**: Set `enabled: true`

**Example Configuration:**

If your MinIO reports show:
- ✅ `ida` report: SUCCESS → Set `enabled: false`
- ❌ `print` report: FAILED → Set `enabled: true`
- ❌ `abis` report: FAILED → Set `enabled: true`
- ❌ `resident` report: FAILED → Set `enabled: true`

```yaml
partner-onboarder:
  namespace: onboarder
  enabled: true
  version: 12.0.1
  chart: mosip/partner-onboarder
  set:
    onboarding.configmaps.s3.s3-host: "http://minio.minio:9000"
    onboarding.configmaps.s3.s3-user-key: "admin"
    onboarding.configmaps.s3.s3-region: ""
    onboarding.configmaps.s3.s3-bucket-name: "onboarder"
    extraEnvVarsCM[0]: "global"
    extraEnvVarsCM[1]: "keycloak-env-vars"
    extraEnvVarsCM[2]: "keycloak-host"
    onboarding.modules[0].name: "ida"
    onboarding.modules[0].enabled: false      # SUCCESS - skip
    onboarding.modules[1].name: "print"
    onboarding.modules[1].enabled: true       # FAILED - retry
    onboarding.modules[2].name: "abis"
    onboarding.modules[2].enabled: true       # FAILED - retry
    onboarding.modules[3].name: "resident"
    onboarding.modules[3].enabled: true       # FAILED - retry
    onboarding.modules[4].name: "mobileid"
    onboarding.modules[4].enabled: true
    onboarding.modules[5].name: "digitalcard"
    onboarding.modules[5].enabled: true
    onboarding.modules[6].name: "esignet"
    onboarding.modules[6].enabled: false
```

4. **Commit the changes:**
   - Commit the updated `mosip-dsf.yaml` file to your repository
   - This will automatically trigger the Helmsman workflow

5. **The workflow will automatically:**
   - Detect the changes in `mosip-dsf.yaml`
   - Recreate the partner-onboarder job
   - Re-run onboarding only for the modules with `enabled: true`

**Alternative Option: Run Partner-Onboarder Without DSF**

If you prefer to run partner-onboarder directly without using Helmsman DSF, you can use the standalone deployment method:

📖 **Reference Guide:** [Partner-Onboarder Standalone Deployment](https://github.com/mosip/mosip-infra/tree/v1.2.0.2/deployment/v3/mosip/partner-onboarder)

This method allows you to deploy and configure partner-onboarder independently using Helm charts.

#### Step 3: Monitor the Rerun

```bash
# Watch pod status
kubectl get pod -n onboarder -w

# Follow logs in real-time
POD_NAME=$(kubectl get pod -n onboarder -o jsonpath='{.items[0].metadata.name}')
kubectl logs -n onboarder -f $POD_NAME

# Wait for completion
kubectl wait --for=condition=complete job/partner-onboarder -n onboarder --timeout=15m
```

#### Step 4: Verify Success in MinIO Reports

After the rerun completes:

1. **Login to MinIO Console** using credentials from above
2. **Navigate to the `onboarder` bucket**
3. **Go to the `reports` folder**
4. **Download the latest report files and verify all show PASSED status**

## Getting Help

If you continue to experience issues:

1. **Check Logs**: Review all relevant logs thoroughly
2. **Consult Documentation**: Refer to MOSIP official documentation
3. **Community Support**: Reach out to MOSIP community forums
4. **Issue Tracker**: Report persistent issues on the GitHub repository

---

**Note**: This guide is based on MOSIP deployment patterns using Helmsman and Kubernetes. Specific steps may vary based on your environment configuration and MOSIP version.
