# GitHub Actions Tool Setup - Environment Variables

## Overview

This document explains how the GitHub Actions workflows for MOSIP deployment have been configured to ensure `kubectl` and `KUBECONFIG` are available as environment variables throughout the entire workflow execution.

## Workflows Updated

The following workflows have been enhanced with consistent tool environment setup:

1. **helmsman_external.yml** - External services deployment (includes `kubectl`, `istioctl`, `KUBECONFIG`)
2. **helmsman_mosip.yml** - MOSIP core services deployment (includes `kubectl`, `KUBECONFIG`)
3. **helmsman_testrigs.yml** - Test rigs deployment (includes `kubectl`, `KUBECONFIG`)

## Key Changes Made

### 1. Enhanced Job-Level Environment Variables

All workflows now include consistent job-level environment variables:

```yaml
env:
  KUBECONFIG: ${{ github.workspace }}/.kube/config
  PATH: ${{ github.workspace }}/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
  KUBECTL_PATH: ${{ github.workspace }}/.local/bin/kubectl
  # For helmsman_external.yml only:
  ISTIOCTL_PATH: ${{ github.workspace }}/istio-1.22.0/bin/istioctl
```

These environment variables are available to all steps in the job.

### 2. Improved Tool Setup Step

All workflows now have a dedicated "Setup kubectl and kubeconfig" step that:

- **Creates necessary directories** first to ensure proper file structure
- **Downloads and installs kubectl** to a dedicated local bin directory
- **Sets up kubeconfig** with proper permissions from secrets
- **Adds tools to GitHub PATH** using `$GITHUB_PATH` for subsequent steps
- **Exports additional environment variables** for immediate use
- **Verifies installations** using full paths to ensure tools work correctly

**For helmsman_external.yml only**, the step also includes istioctl installation:
- **Downloads and installs istioctl** using the official Istio installer

### 3. Dynamic PATH Updates

The workflow uses GitHub's `$GITHUB_PATH` environment file to dynamically add tool directories:

```bash
echo "${{ github.workspace }}/.local/bin" >> $GITHUB_PATH
echo "${{ github.workspace }}/istio-1.22.0/bin" >> $GITHUB_PATH
```

This ensures that `kubectl` and `istioctl` are available in the PATH for all subsequent steps.

### 4. Environment Variable Exports

Additional environment variables are exported for specific tool paths:

```bash
# All workflows:
echo "KUBECTL_PATH=${{ github.workspace }}/.local/bin/kubectl" >> $GITHUB_ENV

# helmsman_external.yml only:
echo "ISTIOCTL_PATH=${{ github.workspace }}/istio-1.22.0/bin/istioctl" >> $GITHUB_ENV
```

### 5. Comprehensive Verification Steps

Multiple verification points ensure tools are working:

1. **Initial verification** in the setup step using full paths
2. **Tools availability check** in the Helmsman installation step
3. **Cluster access verification** step that tests kubectl functionality (and istioctl for external workflow)
4. **Pre-deployment verification** in the Helmsman execution step

### 6. Fixed Mode Environment Variable

The workflow mode is now properly handled:

```yaml
- name: Set Default Mode
  run: |
    if [ -z "${{ github.event.inputs.mode }}" ]; then
      echo "HELMSMAN_MODE=apply" >> $GITHUB_ENV
    else
      echo "HELMSMAN_MODE=${{ github.event.inputs.mode }}" >> $GITHUB_ENV
    fi
```

And used correctly in the Helmsman command:

```bash
helmsman --debug --${HELMSMAN_MODE} -f $WORKDIR/dsf/${{ matrix.dsf_files }}
```

## How It Works

1. **Job-level environment**: Sets up global environment variables including `KUBECONFIG` and enhanced `PATH`

2. **Tool installation**: Downloads and installs tools to predictable locations within the GitHub workspace

3. **PATH management**: Uses GitHub's built-in mechanism to add tool directories to PATH for all subsequent steps

4. **Verification**: Multiple checkpoints ensure tools are accessible and functional

5. **Usage**: All subsequent steps can use `kubectl` (and `istioctl` for external workflow) and access `KUBECONFIG` without additional setup

## Benefits

- **Consistency**: Tools are available in the same way across all workflow steps and all MOSIP workflows
- **Reliability**: Multiple verification points catch setup issues early
- **Maintainability**: Clear separation of tool setup from business logic
- **Debugging**: Extensive logging shows exactly where tools are located and their versions
- **Security**: Proper file permissions on kubeconfig and tool binaries

## Verification

All workflows include verification steps that will output:

**For helmsman_mosip.yml and helmsman_testrigs.yml:**
```
Verifying tool availability:
kubectl path: /home/runner/work/infra-priv/infra-priv/.local/bin/kubectl
KUBECONFIG: /home/runner/work/infra-priv/infra-priv/.kube/config
```

**For helmsman_external.yml:**
```
Verifying tool availability:
kubectl path: /home/runner/work/infra-priv/infra-priv/.local/bin/kubectl
istioctl path: /home/runner/work/infra-priv/infra-priv/istio-1.22.0/bin/istioctl
KUBECONFIG: /home/runner/work/infra-priv/infra-priv/.kube/config
```

This ensures that all required tools are properly set up and accessible throughout the workflow execution.
