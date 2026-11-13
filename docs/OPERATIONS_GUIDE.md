# Day-2 Operations Guide

How to change an environment after it is deployed: add or remove nodes, resize,
stop/start, add subdomains or firewall rules, and more. Every recipe below is
**one or two runs of an existing workflow** — no manual changes on the servers.

All Terraform runs use **Actions → terraform plan / apply** (inputs as in the
[Workflow Guide](WORKFLOW_GUIDE.md#workflow-1-base-infrastructure)), on your
deployment branch, with the same `PROFILE`, `BACKEND_TYPE` and `SSH_PRIVATE_KEY`
as the original deployment. Values live in `profiles/<profile>/aws/*.tfvars`;
commit the tfvars change to the branch first.

| I want to … | Change | Run |
|---|---|---|
| [Preview a change](#preview-before-you-change-anything) | — | `COMPONENT=all`, apply ☐ |
| [Add worker nodes](#add-worker-nodes) | `k8s_worker_node_count` | `compute`, then `configure` |
| [Add control-plane nodes](#add-control-plane-nodes) | `k8s_control_plane_node_count` | `compute`, then `configure` |
| [Remove nodes](#remove-nodes-scale-in) | lower a count | drain, `compute`, `configure` |
| [Resize nodes](#resize-nodes) | `k8s_instance_type` / `k8s_node_instance_type` | `compute` |
| [Resize nginx](#resize-the-nginx-node) | `nginx_instance_type` | `compute`, then `dns` |
| [Stop / start nodes](#stop-and-start-nodes) | — | `instance-power.yml` |
| [Add a subdomain](#add-a-subdomain) | `additional_subdomain_*` | `dns` (+ `configure` for public) |
| [Open a port](#open-a-port-security-group-rule) | `security.tfvars` | `security` |
| [Add a standalone VM](#add-a-standalone-vm) | `vm.tfvars` | `vm` |
| [Set up DNS later](#deploy-now-dns-later) | — | `DNS_PROVIDER=manual`, later a provider |
| [Re-run the configuration](#re-run-configure) | — | `configure` |
| [(Re)import into Rancher](#rancher-import-and-kubeconfig) | — | `configure` + `ENABLE_RANCHER_IMPORT` |

---

## Preview before you change anything

Run **terraform plan / apply** with `COMPONENT=all` and **TERRAFORM_APPLY ☐**
(unchecked). Every component is planned in order (security → iam → compute →
storage → dns); nothing is applied or committed and `configure` is skipped.
Read each component's plan; then run the real change.

- This previews an **existing** environment. A brand-new one can't be planned
  this way: compute, storage and dns look up what the earlier components
  created in AWS.
- For a single component, run it with apply ☐ (e.g. `COMPONENT=compute`).

## Add worker nodes

1. In `profiles/<profile>/aws/compute.tfvars`, raise the count, e.g.
   `k8s_worker_node_count = 4` → `5`.
2. **`COMPONENT=compute`**, apply ✅. The plan adds only the new instance(s) —
   named after the next free number (`WORKER-NODE-5`) — and changes nothing
   else.
3. **`COMPONENT=configure`**, apply ✅. Existing nodes are skipped (RKE2
   already running); the new node installs RKE2 and joins with the token read
   from the primary control-plane node; nginx is regenerated with the new
   node's IP.
4. Check: `kubectl get nodes` shows the new node `Ready`.

Data centre (no Terraform): add the VM to `hosts.yml`, regenerate the
inventory and run `ansible-playbook -i inventory.yml ansible/site.yml` — see
[Data-centre deployment](DATACENTRE_DEPLOYMENT.md).

## Add control-plane nodes

Same as [adding workers](#add-worker-nodes), with
`k8s_control_plane_node_count`. Control-plane nodes are etcd members: keep the
count **odd** (3 tolerates one failure, 5 tolerates two) and add them one or
two at a time.

> `k8s_etcd_node_count` nodes are started as RKE2 agents with the k8s-infra
> templates — they join as **workers**, not etcd members. To add etcd capacity,
> add control-plane nodes.

## Remove nodes (scale in)

Lowering a count removes the **highest-numbered** nodes of that kind (e.g.
`k8s_worker_node_count = 5` → `4` removes `WORKER-NODE-5`).

1. Move the workloads off the node(s) first:
   ```bash
   kubectl drain <node> --ignore-daemonsets --delete-emptydir-data
   kubectl delete node <node>
   ```
2. Lower the count in `compute.tfvars`.
3. **`COMPONENT=compute`**, apply ✅. The plan must show **only** the node(s)
   you drained being destroyed — stop if it shows anything else.
4. **`COMPONENT=configure`**, apply ✅ — nginx is regenerated without the
   removed IP(s).

Control-plane nodes: remove **one at a time**, keep the count odd, and never
remove `CONTROL-PLANE-NODE-1` (the primary — the other nodes read the join
token from it).

## Resize nodes

Instance type changes are **in place**: the instance is stopped, resized and
started — same instance, private IP and disk. RKE2 rejoins on boot; no
`configure` needed. Keep the AMI's CPU architecture (x86: `t3a` / `m6a` /
`m7a`).

- **All cluster nodes at once:** set `k8s_instance_type`, run
  **`COMPONENT=compute`**. The whole cluster is down for a few minutes.
- **One node at a time (rolling):** in the "Optional settings" of
  `compute.tfvars`, set e.g.
  `k8s_node_instance_type = { "WORKER-NODE-1" = "m6a.2xlarge" }`, drain the
  node, run **`COMPONENT=compute`**, uncordon it, repeat for the next node.
  Control-plane nodes one at a time. Back to default: remove the entry.

## Resize the nginx node

Set `nginx_instance_type`, run **`COMPONENT=compute`**, then
**`COMPONENT=dns`**. nginx has no Elastic IP, so its **public IP changes** when
it is stopped and started; the dns run points `api.<domain>` and the public
subdomains at the new IP. While nginx is stopped, ingress, NFS, PostgreSQL and
ActiveMQ are unavailable.

## Stop and start nodes

- **Ad hoc:** **Actions → instances start / stop** (`instance-power.yml`) with
  the private IPs, `ACTION=stop|start|status` and `MODE=dry-run` first, then
  `apply`. Instances are stopped workers → control-plane → nginx and started
  in the reverse order; instances that are still starting are waited for
  before a stop.
- **Recorded in git and enforced:** `k8s_instance_state`, `k8s_node_state` or
  `nginx_instance_state` in `compute.tfvars`, then **`COMPONENT=compute`**.
  These override ad-hoc stops/starts on every compute run.
- After **starting nginx**, run **`COMPONENT=dns`** (new public IP).
- A stopped environment can still be destroyed (`terraform destroy`).

Details: [workflow README — instances start / stop](../.github/workflows/README.md#instances-start--stop-instance-poweryml).

## Add a subdomain

In `profiles/<profile>/aws/dns.tfvars` (this environment only):

```hcl
additional_subdomain_internal = ["reports"]   # → api-internal.<domain>
additional_subdomain_public   = ["portal"]    # → api.<domain>
```

1. **`COMPONENT=dns`** — adds one record per new name, nothing else changes.
   With another DNS provider (GoDaddy, Cloudflare, RFC 2136) use
   **`COMPONENT=configure`** instead.
2. For a **public** subdomain, also run **`COMPONENT=configure`**: nginx's list
   of public domains is regenerated.
3. The wildcard certificate already covers the new name; the application still
   needs an Istio Gateway / VirtualService for the host.

A name must be either public or internal — listing it in both is rejected.
Don't use `subdomain_public` / `subdomain_internal` for this: they replace the
profile's whole list.

## Open a port (security-group rule)

Edit `profiles/<profile>/aws/security.tfvars`: `ingress_rules` per group
(`nginx`, `control_plane`, `etcd`, `worker`) and `egress_rules` for all groups.
`"network_cidr"` / `"wireguard_cidr"` in `cidr_blocks` are filled in from
`common.tfvars` (private ranges only). Run **`COMPONENT=security`** — the
groups are updated in place, instances are untouched.

## Add a standalone VM

Describe it per group in `profiles/<profile>/aws/vm.tfvars` (instance type,
AMI, subnet, disks, inbound/outbound rules, VPC) and run **`COMPONENT=vm`**.
SSH from `0.0.0.0/0` — including an all-protocol rule — is rejected unless
`allow_ssh_from_anywhere = true`. Details: [workflow README — standalone
instance](../.github/workflows/README.md#standalone-instance--any-type-ami-vpc-disks-componentvm).

## Deploy now, DNS later

1. `COMPONENT=all`, apply ✅, **`DNS_PROVIDER=manual`** — builds the VMs,
   storage, RKE2, NFS, PostgreSQL and ActiveMQ; skips TLS, the nginx reverse
   proxy and the Rancher import; prints the DNS records to create.
2. When the records exist: `COMPONENT=all` (or `configure`) with a DNS provider
   (`terraform-route53`, `godaddy`, `cloudflare`, `rfc2136`) — TLS and nginx
   are configured now; the rest is already in place.

Details: [workflow README — no DNS yet](../.github/workflows/README.md#no-dns-yet-dns_providermanual).

## Re-run configure

**`COMPONENT=configure`**, apply ✅ — safe to repeat. On an existing cluster
the RKE2 install is skipped ("cluster already exists"), nodes that already run
RKE2 are skipped, and the remaining roles (nginx, NFS, PostgreSQL, ActiveMQ) are
re-applied idempotently. Use it after adding/removing nodes, adding a public
subdomain, or to repair drift.

## Rancher import and kubeconfig

**`COMPONENT=configure`** (or `all`) with **`ENABLE_RANCHER_IMPORT`** ✅
(`RANCHER_API_URL` + `RANCHER_API_TOKEN` secrets). The cluster is registered
in the observ Rancher, the import is applied, team access is granted and —
with **`PUBLISH_KUBECONFIG`** — the kubeconfig is stored as the `KUBECONFIG`
environment secret for the Helmsman workflows.

## Remove an environment

See the [Environment Destruction Guide](ENVIRONMENT_DESTRUCTION_GUIDE.md):
Helmsman releases first, then **terraform destroy** (`COMPONENT=all`), and
`base-infra` last.

---

**Navigation**: [Back to Main README](../README.md) | [View All Docs](README.md)
