# Rancher Import Feature

This module now supports optional Rancher cluster import functionality.

## Usage

### Enable Rancher Import

To enable Rancher import, set the following variables in your `.tfvars` file:

```hcl
# Enable Rancher import
IMPORT_RANCHER = true

# Rancher server URL
RANCHER_URL = "https://your-rancher-server.example.com"

# Rancher access token (should be stored as a secret)
RANCHER_TOKEN = "token-xxxxx:xxxxxxxxxxxxxxxxxx"
```

### Disable Rancher Import (Default)

```hcl
# Disable Rancher import (default behavior)
IMPORT_RANCHER = false
```

## Variables

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `IMPORT_RANCHER` | bool | `false` | Whether to import the cluster into Rancher |
| `RANCHER_URL` | string | `""` | Rancher server URL for cluster import |
| `RANCHER_TOKEN` | string | `""` | Rancher access token for cluster import (sensitive) |

## How it Works

1. **When `IMPORT_RANCHER = true`:**
   - The user data script includes Rancher configuration
   - Control plane nodes will attempt to import the cluster to Rancher
   - A systemd service is created to handle the import after cluster initialization

2. **When `IMPORT_RANCHER = false` (default):**
   - No Rancher-related configuration is added
   - Cluster operates independently without Rancher integration

## Security Considerations

- The `RANCHER_TOKEN` variable is marked as sensitive
- Store the Rancher token in a secure secret management system
- Use HTTPS for the Rancher URL to ensure secure communication

## Requirements

- Rancher server must be accessible from the Kubernetes cluster
- Valid Rancher access token with cluster creation permissions
- Network connectivity between cluster nodes and Rancher server

## Troubleshooting

Check the Rancher import service status on control plane nodes:
```bash
sudo systemctl status rancher-import.service
sudo journalctl -u rancher-import.service
```

The import script logs are available at `/tmp/k8s-*.log` on the control plane nodes.
