# Known limitations

## Platform

| Limitation | Workaround |
|---|---|
| Terraform creates servers on **AWS only** (Azure/GCP `base-infra` are placeholders) | Create VMs yourself and use the [data-centre path](../getting-started/quickstart-datacentre.md) |
| **Air-gapped** data centres are not supported — hosts need outbound HTTPS | Provide an internet proxy / mirror |
| Hosts must have a **`ubuntu`** user | Create it with passwordless sudo |
| Terraform DNS records are **Route53 only** | Use the Ansible DNS role for GoDaddy, Cloudflare, RFC 2136 |

## Docker Hub rate limits

Anonymous image pulls are rate-limited, which can stall a deployment.

**Symptoms:** `ErrImagePull`, `429 Too Many Requests … toomanyrequests`, pods in
`ContainerCreating` for minutes.

**Fix:**

1. Configure Docker Hub credentials in the cluster, or use a registry mirror.
2. Re-run the failed Helmsman workflow after a while.
3. Delete a pod stuck for more than ~3 minutes so it is recreated:

    ```bash
    kubectl delete pod <pod> -n <namespace>
    kubectl get pods -n <namespace> -w
    ```

## AWS capacity

**Symptom:** `InsufficientInstanceCapacity … in the Availability Zone you requested`.

**Fix:** leave `specific_availability_zones = []` in `compute.tfvars` so AWS can use any zone with
capacity.

## Partner onboarding

Partner onboarding can fail during the automated MOSIP deployment and then needs a manual
re-run before test rigs. Check that all pods in `mosip`, `keycloak` and `postgres` are running
first. See [Partner onboarding](../mosip/partner-onboarding.md).

## External services

Deployments depend on:

- **GitHub** — Actions and repository access ([status](https://www.githubstatus.com))
- **Let's Encrypt** — certificates for `dns01` / `http01` ([status](https://letsencrypt.status.io))

Wait for "All Systems Operational" before starting a deployment.
