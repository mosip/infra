# Deploy External Services of MOSIP using Helmsman

This repository contains a GitHub Actions workflow to deploy external services and mosip services of MOSIP using Helmsman. we have two workflow's i,e `helmsman_external.yml` and `helmsman_mosip.yml`.

> **Important**: Always use `apply` mode for MOSIP deployments. The `dry-run` mode will fail because MOSIP services depend on shared configmaps and secrets from other namespaces that are not available during dry-run validation.

## helmsman_external.yml 

This GitHub Actions workflow automates the deployment of external services for the [MOSIP](https://www.mosip.io/) platform using [Helmsman](https://github.com/Praqma/helmsman) and [Helm](https://helm.sh/).
This workflow supports multiple modes (`dry-run` and `apply`) and handles essential setup tasks like configuring WireGuard, installing Helm and Helmsman, and applying configurations of DSF files.

### Workflow Overview

The workflow is triggered by:
- **Manual Dispatch**: Allowing users to select the mode (`dry-run` or `apply`).
- **Push Events**: Monitoring changes in the `deployment/v3/helmsman/dsf/prereq-dsf.yaml` and `deployment/v3/helmsman/dsf/external-dsf.yaml`.

The deployment is done in a matrix strategy to handle multiple configuration files for WireGuard and DSF (Deployment Specification Files).

### Inputs to be provided to run workflow.

### Prerequisites

- Ensure the necessary secrets (`CLUSTER_WIREGUARD_WG0`, `CLUSTER_WIREGUARD_WG1`, `KUBECONFIG`, `PAT_TOKEN`) are configured in the repository settings.
- The target Kubernetes cluster should be accessible via the provided `KUBECONFIG`.

### Mode
- **Description**: Choose the mode in which Helmsman runs.
- **Required**: Yes
- **Default**: `dry-run`
- **Recommended**: `apply` (dry-run will fail due to namespace dependencies)
- **Options**:
 - `dry-run`: Simulates the deployment without making changes (will fail for MOSIP).
 - `apply`: Applies the deployment changes.

### Secrets

The following secrets are required to run this workflow:
- `CLUSTER_WIREGUARD_WG0`: WireGuard configuration for `wg0`.
- `CLUSTER_WIREGUARD_WG1`: WireGuard configuration for `wg1`.
- `KUBECONFIG`: The Kubernetes configuration file for cluster access.
- `PAT_TOKEN`: GitHub PAT token used for API-based workflow dispatch.

### Steps Performed:

1. **Repository Checkout**
- Fetches the repository to work with the required configuration files.

2. **Set Default Mode**
- Sets the deployment mode based on the user input or defaults to `apply`.

3. **Setup UFW Firewall**
- Enables the firewall.
- Allows SSH and WireGuard (UDP port 51820).

4. **Install WireGuard**
- Installs WireGuard to enable secure communication with clusters.

5. **Configure WireGuard**
- Configures WireGuard using the provided secret configuration files.

6. **Start WireGuard**
- Starts the WireGuard service for secure network communication.

7. **Setup Helm**
- Installs Helm, a Kubernetes package manager.

8. **Install Helmsman**
- Installs Helmsman, a tool for managing Helm charts.

9. **Apply Helmsman Configurations**
- Prepares the Kubernetes environment (kubectl, Istio CLI).
- Uses Helmsman to deploy DSF configurations in the specified mode.

10. **Trigger helmsman mosip workflow via API**
- Sets the current default branch to the one triggering the workflow via Manual Dispatch.
- Dispatches the `helmsman_mosip.yml` workflow using the GitHub REST API.
- **Automatic Flow**: Upon successful completion of prerequisites and external dependencies, the MOSIP services workflow is automatically triggered.
- **Error Handling**: If the automatic trigger fails, the MOSIP deployment can be manually triggered from the Actions tab.

### Deployment Flow & Error Handling

**Parallel Deployment Strategy:**
- Prerequisites (`prereq-dsf.yaml`) and External Dependencies (`external-dsf.yaml`) are deployed in parallel for optimal deployment time
- Both must complete successfully before MOSIP services deployment is triggered

**Automatic Trigger Mechanism:**
- Upon successful completion of both prerequisite and external dependency deployments, the workflow automatically triggers `helmsman_mosip.yml`
- This ensures proper sequencing and reduces manual intervention

**Error Recovery:**
- If automatic trigger fails: Manually run "Deploy MOSIP services using Helmsman" from Actions tab
- If onboarding processes fail: Manual re-onboarding is required (see limitations in main README)
- Monitor deployment logs for any failures requiring intervention 

### Triggering the Workflow Manually
1. Navigate to the "Actions" tab in your repository.
2. Select the `Deploy External Services` workflow.
3. Click on "Run workflow."
4. Choose the mode (`apply` recommended - avoid `dry-run` as it will fail) and start the workflow.

### Triggering on Push
- Commit and push changes to `deployment/v3/helmsman/dsf/prereq-dsf.yaml` and `deployment/v3/helmsman/dsf/external-dsf.yaml` to automatically trigger the workflow.

---

## Complete Deployment Sequence Overview

### Phase 1: Prerequisites & External Dependencies (Parallel)
1. **Prerequisites Deployment** (`prereq-dsf.yaml`):
 - Monitoring stack (Rancher monitoring, Grafana, AlertManager)
 - Logging infrastructure (Cattle logging system)
 - Service mesh (Istio) and networking components

2. **External Dependencies Deployment** (`external-dsf.yaml`):
 - Databases (PostgreSQL with initialization)
 - Identity & Access (Keycloak)
 - Security (SoftHSM, ClamAV antivirus)
 - Object Storage (MinIO)
 - Message Queues (ActiveMQ, Kafka with UI)

### Phase 2: MOSIP Services (Automatic Trigger)
- **Trigger Condition**: Both prerequisites and external dependencies complete successfully
- **Deployment**: MOSIP core services (`mosip-dsf.yaml`)
- **Fallback**: Manual trigger available if automatic fails

### Phase 3: Pre-Test Verification (Manual)
Before deploying test rigs, verify:
```bash
# Check all pods are running
kubectl get pods --all-namespaces | grep -v Running | grep -v Completed

# Verify specific namespaces
kubectl get pods -A
kubectl get pods -n keycloak
kubectl get pods -n postgres
```

### Phase 4: Test Rigs Deployment (Manual)
- **Prerequisites**: All core services pods in `Running` state
- **Action**: Manual trigger of test rigs workflow
- **Important**: Handle any failed onboarding processes before test rig deployment

---

## helmsman_mosip.yml

This GitHub Actions workflow automates the deployment of mosip services for the [MOSIP](https://www.mosip.io/) platform using [Helmsman](https://github.com/Praqma/helmsman) and [Helm](https://helm.sh/). This workflow supports multiple modes (`dry-run` and `apply`) and handles essential setup tasks like configuring WireGuard, installing Helm and Helmsman, and applying configurations of DSF files.

### Workflow Overview

The workflow is triggered by:
- **Automatic Trigger**: Automatically initiated by the successful completion of `helmsman_external.yml` workflow
- **Manual Dispatch**: Allowing users to select the mode (`dry-run` or `apply`) as a fallback option
- **Push Events**: Monitoring changes in the `deployment/v3/helmsman/dsf/mosip-dsf.yaml`.

> **Note**: The preferred trigger method is automatic via the external dependencies workflow to ensure proper deployment sequencing.

### Inputs to be provided to run workflow.

### Prerequisites

- Ensure the necessary secrets (`CLUSTER_WIREGUARD_WG0`, `KUBECONFIG`) are configured in the repository settings.
- The target Kubernetes cluster should be accessible via the provided `KUBECONFIG`.

### Mode
- **Description**: Choose the mode in which Helmsman runs.
- **Required**: Yes
- **Default**: `dry-run`
- **Recommended**: `apply` (dry-run will fail due to namespace dependencies)
- **Options**:
 - `dry-run`: Simulates the deployment without making changes (will fail for MOSIP).
 - `apply`: Applies the deployment changes.

### Secrets

The following secrets are required to run this workflow:
- `CLUSTER_WIREGUARD_WG0`: WireGuard configuration for `wg0`.
- `KUBECONFIG`: The Kubernetes configuration file for cluster access.

### Steps Performed:

1. **Repository Checkout**
- Fetches the repository to work with the required configuration files.

2. **Set Default Mode**
- Sets the deployment mode based on the user input or defaults to `apply`.

3. **Setup UFW Firewall**
- Enables the firewall.
- Allows SSH and WireGuard (UDP port 51820).

4. **Install WireGuard**
- Installs WireGuard to enable secure communication with clusters.

5. **Configure WireGuard**
- Configures WireGuard using the provided secret configuration files.

6. **Start WireGuard**
- Starts the WireGuard service for secure network communication.

7. **Setup Helm**
- Installs Helm, a Kubernetes package manager.

8. **Install Helmsman**
- Installs Helmsman, a tool for managing Helm charts.

9. **Apply Helmsman Configurations**
- Prepares the Kubernetes environment (kubectl, Istio CLI).
- Uses Helmsman to deploy DSF configurations in the specified mode.

### Triggering the Workflow Manually
1. Navigate to the "Actions" tab in your repository.
2. Select the `Deploy External Services` workflow.
3. Click on "Run workflow."
4. Choose the mode (`dry-run` or `apply`) and start the workflow.

### Triggering on Push
- Commit and push changes to `deployment/v3/helmsman/dsf/prereq-dsf.yaml` and `deployment/v3/helmsman/dsf/external-dsf.yaml` to automatically trigger the workflow.

### Triggering the MOSIP Workflow

**Automatic Trigger (Recommended):**
- The MOSIP services workflow is automatically triggered upon successful completion of the `helmsman_external.yml` workflow
- No manual intervention required if external dependencies deploy successfully

**Manual Trigger (Fallback):**
1. Navigate to the "Actions" tab in your repository
2. Select the `Deploy MOSIP Services` workflow
3. Click on "Run workflow"
4. Choose the mode (`apply` recommended - avoid `dry-run` as it will fail) and start the workflow

**Push Trigger:**
- Commit and push changes to `deployment/v3/helmsman/dsf/mosip-dsf.yaml` to automatically trigger the workflow

---

## Logs

- The workflow runs Helmsman in standard mode for clean output and better performance.
- Logs can be viewed in the "Actions" tab of the repository under the respective workflow run.

---
