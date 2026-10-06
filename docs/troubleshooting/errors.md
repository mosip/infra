# Error catalogue

Find the message you see, then follow the fix. Messages in `code` are quoted from this repository's
checks; others describe the symptom, since cloud-provider wording can change.

## Workflow and Terraform

??? failure "`COMPONENT=all needs TERRAFORM_APPLY=true`"
    **Cause:** `all` and `configure` look up resources created by earlier steps, so they can't run
    as plan-only.

    **Fix:** tick `TERRAFORM_APPLY`, or preview a single component (e.g. `COMPONENT=security`) first.

??? failure "`only base-infra exists for azure` / `gcp`"
    **Cause:** Terraform components are AWS-only today.

    **Fix:** for Azure/GCP, create the VMs yourself and follow the
    [data-centre quickstart](../getting-started/quickstart-datacentre.md).

??? failure "`var file not found: …/profiles/<profile>/aws/<component>.tfvars`"
    **Cause:** wrong `PROFILE`, or the profile directory isn't on your branch.

    **Fix:** check the profile name and that `profiles/<profile>/aws/` exists on the branch you ran.

??? failure "compute fails: security group not found"
    **Cause:** `security` hasn't been applied for this `cluster_name`.

    **Fix:** run `COMPONENT=security` (or `all`). Check `cluster_name` is the same in every run.

??? failure "compute fails: IAM instance profile not found"
    **Cause:** `iam` hasn't been applied, or you use a non-Route53 DNS provider.

    **Fix:** run `COMPONENT=iam`, or set `attach_certbot_profile = false` in `compute.tfvars`.
    (The workflow does this automatically when `DNS_PROVIDER` isn't `terraform-route53`.)

??? failure "storage / dns fail: nginx instance not found (query returned no results)"
    **Cause:** the nginx instance doesn't exist or is stopped — these components look up the
    *running* instance by tag.

    **Fix:** apply `compute`, or start the instance.

??? failure "`InvalidAMIID.NotFound`"
    **Cause:** the AMI in `common.tfvars` belongs to another region.

    **Fix:** use the Ubuntu 24.04 AMI ID for `aws_provider_region`.

??? failure "`Key pair 'x' does not exist`"
    **Cause:** `ssh_key_name` doesn't match an EC2 key pair in that region.

    **Fix:** create the key pair, or correct `ssh_key_name`. The `SSH_PRIVATE_KEY` input must name
    the secret holding its private key.

## Pre-flight (Ansible)

??? failure "`Data disk(s) not found on <host>: /dev/nvme2n1`"
    **Cause:** the disk isn't attached, or it has a different device name (common in data centres).

    **Fix:** AWS — apply `storage`. Data centre — run `lsblk` on the nginx VM and set
    `nfs_storage_device`, `storage_device` (PostgreSQL), `activemq_storage_device`.

    !!! danger "Get this right"
        Data disks that aren't mounted yet are **formatted**. A wrong device path wipes that disk.

??? failure "`api.<domain> resolves to [], expected …`"
    **Cause:** DNS records don't exist yet, haven't propagated, or point elsewhere.

    **Fix:** create the records ([DNS providers](../guides/dns-providers.md)). Behind NAT, set
    `dns_expected_ip` to the public address. With HTTP-01 this blocks the run; with other TLS modes
    it's a warning.

??? failure "`Required variable 'cluster_name' is missing or empty`"
    **Fix:** set it under `vars:` in `hosts.yml` (data centre) or in `common.tfvars` (AWS).

??? failure "`profile runs rancher_keycloak but rancher_password is not set`"
    **Fix:** set the `RANCHER_BOOTSTRAP_PASSWORD` secret (CI) or pass `-e rancher_password=…`.

## TLS and DNS providers

??? failure "`Invalid TLS settings …`"
    **Cause:** missing value for the chosen `tls_mode`.

    **Fix:** `byo` needs `tls_cert_file` + `tls_key_file`; `http01`/`dns01` need `certbot_email`;
    `dns01` with a provider other than route53 needs `dns01_credentials_file`.

??? failure "certbot HTTP-01: timeout / connection refused during validation"
    **Fix:** open port 80 to the internet on nginx, and make sure every public name resolves to it.

??? failure "`Invalid DNS settings …`"
    **Fix:** set the provider's credentials — GoDaddy key + secret, Cloudflare token, or RFC 2136
    server (+ TSIG key).

??? failure "GoDaddy: HTTP 401 / 403 from the API"
    **Cause:** the account has no production API access.

    **Fix:** request access from GoDaddy, or [delegate a subdomain to Route53](../guides/dns-providers.md#alternative-delegate-a-subdomain-to-route53).

## Cluster

??? failure "RKE2 nodes don't join"
    **Fix:** open ports **9345** and **6443** between nodes; the first `control_plane` entry must be
    reachable. On a re-run, existing nodes are skipped — only new nodes join.

??? failure "Rancher cluster stays `Unavailable`"
    **Fix:** check `kubectl get pods -n cattle-system` and that nodes can reach the Rancher URL.

## CI checks on pull requests

??? failure "DCO: `The sign-off is missing`"
    **Fix:** commit with `git commit -s`. For existing commits: `git rebase --signoff <base>` and
    force-push with lease.

??? failure "ansible: `couldn't resolve module/action 'community.general…'`"
    **Fix:** `ansible-galaxy collection install -r ansible/requirements.yml`.

---

Not listed? Search these docs (++slash++), or open an issue with the failing job's log.
