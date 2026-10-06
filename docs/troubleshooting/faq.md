# FAQ

??? question "Can I deploy without Terraform?"
    Yes. On any pre-created Ubuntu VMs (data centre, Azure, GCP), write a `hosts.yml` and run
    Ansible. See [Quickstart: data centre](../getting-started/quickstart-datacentre.md).

??? question "Can Terraform create servers on Azure or GCP?"
    Not yet — only `base-infra` placeholders exist for them. Create the VMs yourself and use the
    data-centre path.

??? question "How do I change only DNS records?"
    Edit the subdomains in `profiles/<profile>/profile.yml` (or `dns.tfvars` for zones and extra
    records), then run `COMPONENT=dns`. Nothing else changes. See [DNS providers](../guides/dns-providers.md).

??? question "Our domain is at GoDaddy. What do we do?"
    Either delegate a subdomain to Route53 (no code changes), or set `DNS_PROVIDER=godaddy` with
    the GoDaddy API secrets. See [DNS providers](../guides/dns-providers.md).

??? question "Do I have to run all components every time?"
    No. `COMPONENT=all` is for a new environment. For changes, run just the component you changed
    (e.g. `compute` to add nodes, `configure` to re-run Ansible).

??? question "Why is IAM applied before compute?"
    nginx needs its certificate permission when it is created — the same order as the legacy
    setup.

??? question "Where is my Terraform state?"
    One file per component, profile and branch — committed GPG-encrypted to your branch, or in
    your S3/GCS/Azure bucket. See [State & backends](../reference/state-backends.md).

??? question "How do I get the kubeconfig?"
    With Rancher import + `PUBLISH_KUBECONFIG` it is set as the `KUBECONFIG` secret. Otherwise copy
    `/home/ubuntu/.kube/<cluster_name>-CONTROL-PLANE-NODE-1.yaml` from the primary node.

??? question "Can I preview changes before applying?"
    Run a single component with `TERRAFORM_APPLY` unchecked — it only plans. (`all` and
    `configure` need apply, because later steps look up what earlier ones created.)

??? question "Is it safe to re-run the Ansible setup?"
    Yes. Existing RKE2 nodes are skipped, mounted disks aren't re-formatted, an existing
    certificate is kept.

??? question "Do existing environments need migrating?"
    No — this is a new feature release; new environments use the new layout.

??? question "Can I run the docs locally?"
    `pip install -r docs/requirements.txt && mkdocs serve`, then open
    `http://127.0.0.1:8000/infra/`.
