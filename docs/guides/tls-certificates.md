# TLS certificates

nginx needs a certificate for your domain. Choose how it gets one with `tls_mode` — in the
profile's `ansible_vars`, in `hosts.yml`, or with `-e`. The certificate always ends up in
`/etc/letsencrypt/live/<domain>/`, so nothing else changes between modes.

| Mode | Use when | Wildcard |
|---|---|:-:|
| `dns01` *(default)* | You have API access to your DNS provider | ✅ |
| `http01` | nginx is reachable from the internet on port 80 | — |
| `byo` | You already have a certificate (national CA, purchased, internal) | as issued |

=== "dns01 — DNS challenge"

    Let's Encrypt checks a TXT record the run creates through your DNS provider. Gives a wildcard
    certificate (`*.<domain>` + `<domain>`), so internal names are covered too.

    **Route53 on AWS** (default) — nothing to set; nginx uses the certbot instance profile from
    the `iam` component.

    **Any other provider:**

    ```yaml
    tls_mode: dns01
    certbot_email: ops@example.org
    dns01_provider: cloudflare            # any certbot dns-<provider> plugin
    dns01_credentials_file: /secure/cloudflare.ini
    # GoDaddy is not packaged by Ubuntu:
    # dns01_provider: godaddy
    # dns01_plugin_install: pip
    ```

    In the GitHub workflow, choosing a `DNS_PROVIDER` other than `terraform-route53` sets this up
    from the provider's secrets automatically.

=== "http01 — HTTP challenge"

    Let's Encrypt connects to each public name on port 80.

    ```yaml
    tls_mode: http01
    certbot_email: ops@example.org
    ```

    - Every name in the profile's `subdomain_public` (plus `api`) must already resolve to nginx —
      pre-flight **blocks** the run otherwise.
    - No wildcard; internal names are not covered.

=== "byo — your own certificate"

    ```yaml
    tls_mode: byo
    tls_cert_file: /secure/fullchain.pem    # certificate + intermediates
    tls_key_file: /secure/privkey.pem
    ```

    Files are read from the machine running Ansible and copied with mode `0600` for the key.

## Renewal

| Mode | Renewal |
|---|---|
| `dns01`, `http01` | Automatic — certbot's system timer on the nginx host |
| `byo` | Replace the files and re-run `ansible-playbook -i inventory.yml ansible/playbooks/nginx.yml` (byo always re-copies) |

## Verify

```bash
echo | openssl s_client -connect api.<domain>:443 -servername api.<domain> 2>/dev/null \
  | openssl x509 -noout -subject -issuer -dates
```

**Related:** [DNS providers](dns-providers.md) · [Error catalogue](../troubleshooting/errors.md#tls-and-dns-providers)
