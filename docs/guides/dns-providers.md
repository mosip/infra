# DNS providers

MOSIP needs a set of DNS names pointing at the nginx host before nginx is configured. This guide
shows how to create them with the provider you use — with or without Terraform.

## The records

Whatever the provider, the same records are created (example: domain `soil38.mosip.net`):

| Record | Type | Points to |
|---|---|---|
| `api.soil38.mosip.net` | A | nginx **public** IP |
| `api-internal.soil38.mosip.net` | A | nginx **private** IP |
| `soil38.mosip.net` | CNAME | `api-internal.soil38.mosip.net` |
| each public subdomain (`resident`, `prereg`, …) | CNAME | `api.soil38.mosip.net` |
| each internal subdomain (`admin`, `postgres`, …) | CNAME | `api-internal.soil38.mosip.net` |

The subdomain lists live in `profiles/<profile>/profile.yml` (`subdomain_public`,
`subdomain_internal`) — one source for every provider.

## Choose a provider

One setting decides who creates the records: **`DNS_PROVIDER`** in the GitHub workflow, or
**`dns_provider`** for Ansible (in `hosts.yml`, the profile, or `-e`).

=== "Route53 (Terraform)"

    **Default on AWS.** The Terraform `dns` component creates the records; nothing else to set.

    - Zone: `zone_id` in `profiles/<profile>/aws/common.tfvars`.
    - Change records later: edit `profile.yml`, then run `COMPONENT=dns` — only Route53 changes.
    - Several zones (e.g. a private zone for internal names) or extra records: set `zones`,
      `public_zone`, `internal_zone`, `extra_records` in `profiles/<profile>/aws/dns.tfvars`.

    ```hcl
    zones = {
      public   = { name = "mosip.example.org" }
      internal = { name = "mosip.example.org", private = true }   # split-horizon
    }
    public_zone   = "public"
    internal_zone = "internal"
    ```

=== "GoDaddy"

    Records created through the GoDaddy API by the Ansible `dns` role.

    **GitHub workflow:** `DNS_PROVIDER = godaddy`, secrets `GODADDY_API_KEY` and
    `GODADDY_API_SECRET`. The certificate is issued through GoDaddy too.

    **Data centre (`hosts.yml`):**

    ```yaml
    vars:
      dns_provider: godaddy
      dns_zone: mosip.gov.example        # zone apex, if the domain is a sub-domain of it
      dns_godaddy_key: "<key>"           # better: -e @secrets.yml (Ansible Vault)
      dns_godaddy_secret: "<secret>"
    ```

    !!! warning "Check API access first"
        GoDaddy has restricted production API access for some accounts. Confirm your account can
        call the API before relying on it — or use the
        [subdomain delegation](#alternative-delegate-a-subdomain-to-route53) alternative.

=== "BIND / PowerDNS / Windows DNS"

    Uses dynamic updates (RFC 2136) — supported by most enterprise and government DNS servers.

    **GitHub workflow:** `DNS_PROVIDER = rfc2136`, secrets `DNS_RFC2136_SERVER` (IP of the primary
    server), `DNS_RFC2136_KEY_NAME`, `DNS_RFC2136_KEY_SECRET` (TSIG key).

    **Data centre:**

    ```yaml
    vars:
      dns_provider: rfc2136
      dns_rfc2136_server: 10.10.0.53
      dns_rfc2136_key_name: mosip-update
      dns_rfc2136_key_secret: "<base64 secret>"
    ```

    Needs `dnspython` on the machine running Ansible (`pip install dnspython`).

=== "Cloudflare"

    **GitHub workflow:** `DNS_PROVIDER = cloudflare`, secret `CLOUDFLARE_API_TOKEN` (Zone → DNS →
    Edit permission).

    **Data centre:**

    ```yaml
    vars:
      dns_provider: cloudflare
      dns_cloudflare_api_token: "<token>"
    ```

    Records are created **DNS-only** (not proxied) — nginx terminates TLS itself.

=== "Manual"

    No API access? Set `dns_provider: manual` (or `DNS_PROVIDER = manual`). The run prints the exact
    table for your DNS team, then pre-flight **waits** for the records before configuring nginx.

    !!! note
        With `manual`, set `tls_mode` to `byo` or `http01` in the profile — DNS-01 certificates
        need an API.

## Alternative: delegate a subdomain to Route53

Keep the domain at its registrar, but let Route53 manage just the MOSIP part:

1. Create a Route53 hosted zone for e.g. `sandbox.mosip.gov.example`.
2. At the registrar, add **NS** records for `sandbox` pointing to the four Route53 name servers.
3. Use that zone's ID as `zone_id`. Everything else works with the default — no code changes.

## Verify

```bash
dig +short api.soil38.mosip.net             # nginx public IP
dig +short admin.soil38.mosip.net           # api-internal.soil38.mosip.net → private IP
```

Pre-flight runs the same check automatically before nginx and stops (HTTP-01) or warns (other
TLS modes) if the record is missing.

## Remove records

| Provider | How |
|---|---|
| Route53 (Terraform) | **terraform destroy** with `COMPONENT=dns` (or `all`) |
| Others | `ansible-playbook -i inventory.yml ansible/playbooks/dns.yml -e dns_state=absent` |

!!! danger "Internal names in public DNS"
    By default, internal names (`admin`, `postgres`, …) and `api-internal` are published in the
    same zone, so anyone can look up the private IP. For production, put them in a private zone
    (Route53 split-horizon above) or an internal DNS server.

**Related:** [TLS certificates](tls-certificates.md) · [Workflow inputs](../reference/workflow-inputs.md)
