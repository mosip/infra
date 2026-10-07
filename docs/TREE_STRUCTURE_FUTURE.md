# Future Repository Tree — Decoupling Vision (#273 and beyond)

**Status: proposed design, not implemented.** This is a draft for
discussion, not authorized scope — per AGENTS.md's Guardrails, nothing
here gets built until it's turned into a concrete, approved plan (and,
for anything not already covered by #274–#282, matching GitHub issues).
Companion to `docs/TREE_STRUCTURE.md` (current, as-built state) and
AGENTS.md's "Vision / roadmap" section, which this expands into a
directory-level shape.

## Current vs. future: what's different

| | Current (as-built — `docs/TREE_STRUCTURE.md`) | Proposed (vision — this doc) |
|---|---|---|
| `aws-resource-creation` monolith (security groups, EC2, EBS, Route53, IAM) | Two parallel implementations exist today, same pattern as the Layer 3 row below: the legacy monolith (still the default path whenever `PROVISIONING_COMPONENT` is left `none`) *and* 5 independent Terraform roots, each its own state — `security` (#274), `compute` (#275, EC2), `storage` (#276, EBS), `dns` (#277, Route53), `iam`. `azure`/`gcp` have no split at all yet — still single monolithic modules. | `aws-resource-creation` retires once Layer 3 also has no legacy path left (see row below); `azure`/`gcp` gain the same 5-way split (no issue filed for this part yet) |
| Layer 3 (nginx / rke2 / rancher-import / nfs / postgresql / activemq) | Two parallel implementations exist today: the legacy embedded Terraform provisioners (still the default path) *and* a newer top-level `ansible/<component>/` tree, wired up via a dedicated CI `configure` job | Legacy provisioners retired; `ansible/<component>/` becomes the only implementation, reused unchanged across every compute provider — Ansible runs over SSH and doesn't care who provisioned the host |
| Domain / DNS | Cloud-native only (Route53 for AWS) | A `dns-providers/` abstraction — Route53 / Azure DNS / Cloud DNS / **GoDaddy** — selectable independently of compute provider (#353) |
| Inventory generation (Terraform → Ansible handoff) | One path: CI reads Terraform outputs + `.tfvars`, renders `inventory.yml` | Two paths: the existing CI/Terraform-driven one (unchanged) **plus** a new standalone, env-var-driven script for cases with no Terraform involved at all (e.g. pre-racked data-center hosts) |
| **New: data-center as a provisioning target** | *Doesn't exist.* `ansible/inventory.example.yml` covers configuring already-existing on-prem hosts, but there's no Terraform-equivalent that *provisions* a data center | A new `datacenter` compute-provisioning target, mirroring the `aws` layered split (#352) — this row has no "current" side, it's a net-new addition |

## What changes from current state

1. **Layer 3 already has a working decoupled implementation — it just
   isn't the only path yet.** #274–#277 (security, compute, storage, dns)
   are decoupled at the Terraform layer: independent roots + state.
   #278–#281 (nginx, rke2, rancher-import, nfs, postgresql, activemq) are
   decoupled a different way — not as Terraform roots, but as top-level
   `ansible/<component>/playbook.yml` files, added in the same commit as
   the Layer 1/2 split (`e53feb9a`, #273) and already wired up end-to-end
   by a dedicated CI job (`terraform.yml`'s `configure` job, gated on
   `PROVISIONING_COMPONENT: configure`), independent of Terraform's own
   provisioners. Each playbook's header explicitly documents what it was
   "Ported from," "unwrapped from its `null_resource`."
   What's still outstanding: the legacy embedded provisioners inside
   `nginx-setup/`, `rke2-cluster/` (which has its own module-local
   `ansible/` subdir), `nfs-setup/`, `postgresql-setup/`,
   `activemq-setup/`, and `rancher-keycloak-setup/` (also its own
   module-local `ansible/`) still exist and still run whenever
   `PROVISIONING_COMPONENT` is left as `none` — two parallel
   implementations of the same logic, until the legacy ones are retired
   and their now-redundant module-local scripts/playbooks deleted.
2. **The legacy monolith retires** once every layer has an independent
   equivalent and parity is verified (mirrors what the `tests/*.tftest.hcl`
   suites already do for Layer 1/2 — assert new module output matches old
   monolith behavior).
3. **`azure/` and `gcp/` gain the same layered split as `aws/`.** Right
   now only `aws` has been decoupled; `azure`/`gcp` are still single
   monolithic modules under `terraform/modules/{azure,gcp}/`.
4. **`datacenter` joins `aws`/`azure`/`gcp` as a compute-provisioning
   target** — not just an Ansible configuration target
   (`ansible/inventory.example.yml` already covers that), but something
   with the resource-provisioning-equivalent role `terraform/modules/aws/`
   plays for AWS. What "provisioning" means for a data center still needs
   deciding (pre-racked inventory-only vs. driving something like MAAS/
   libvirt/PXE) — flagged as open, not resolved here.
5. **Domain/DNS decouples from compute provider.** A registrar becomes an
   independent choice from where compute runs — add GoDaddy alongside the
   cloud-native DNS services, selectable regardless of `aws`/`azure`/`gcp`/
   `datacenter`.

## Proposed `terraform/` tree

```
terraform/
├── modules/
│   ├── aws/
│   │   ├── security/         [done — #274]
│   │   ├── compute/          [done — #275]
│   │   ├── storage/          [done — #276]
│   │   ├── dns/              [done — #277; would delegate record creation to dns-providers/ below]
│   │   ├── iam/              [done]
│   │   └── aws-resource-creation/   [RETIRED once Layer 3's legacy embedded provisioners
│   │       # are removed — see "What changes" #1 above. Layer 3 itself (nginx/rke2/
│   │       # rancher-import/nfs/postgresql/activemq) gets NO Terraform module here at
│   │       # all — see "Why Layer 3 doesn't need per-provider Terraform" below.
│   │
│   ├── azure/                 [NEW — mirror the aws/ Layer 1/2 split only; not started]
│   │   └── {security,compute,storage,dns,iam}/
│   │
│   ├── gcp/                   [NEW — same mirror; not started]
│   │   └── {security,compute,storage,dns,iam}/
│   │
│   ├── datacenter/            [NEW — on-prem as a provisioning target, not just a config target]
│   │   ├── compute/           # provisioning model TBD (inventory-only vs. MAAS/libvirt/PXE-driven)
│   │   ├── storage/
│   │   ├── security/          # host firewall / network-ACL equivalent of cloud security groups
│   │   └── iam/                # local user/cert-based equivalent — no cloud IAM to lean on
│   │
│   └── dns-providers/         [NEW — registrar abstraction, independent of compute provider]
│       ├── route53/           # today's aws/dns record-creation logic moves here
│       ├── azure-dns/
│       ├── cloud-dns/         # GCP
│       └── godaddy/           [NEW]
│
├── implementations/
│   ├── aws/infra/
│   │   └── {security,compute,storage,dns,iam}/   # Layer 1/2 only — Layer 3 has no
│   │                                              # Terraform root, see above
│   ├── azure/infra/{security,compute,storage,dns,iam}/       [NEW]
│   ├── gcp/infra/{security,compute,storage,dns,iam}/         [NEW]
│   └── datacenter/infra/{compute,storage,security,iam}/      [NEW]
│
└── base-infra/, observ-infra/
    # get the same datacenter/ + dns-providers/ treatment on a longer horizon —
    # base-infra's VPC/WireGuard concept doesn't map 1:1 to a data center and
    # needs its own design pass, not just a mechanical copy of the infra/ split
```

## Why Layer 3 doesn't need per-provider Terraform

Ansible operates over SSH against hosts that already exist — it has no
concept of "AWS" vs. "a data center," only IP addresses and SSH
credentials. That's why `ansible/<component>/playbook.yml` (nginx, rke2,
rancher-import, nfs, postgresql, activemq, rancher-keycloak-setup) is
already compute-provider-agnostic *today*, with zero changes needed to
support `azure`/`gcp`/`datacenter`: the same playbooks run unchanged
regardless of which provider's Layer 1/2 roots provisioned the
underlying hosts, as long as that provider's outputs get turned into the
same `inventory.yml` shape `ansible/inventory.example.yml` documents.
That reshaping is the one piece of real per-provider work Layer 3 needs
— not new modules, not new playbooks. See "Dual-path inventory
generation" below for exactly how that reshaping happens today
(Terraform-driven) and how a second, Terraform-free path would work
(env-var-driven, for cases like `datacenter` where hosts may already
exist).

## Dual-path inventory generation: Terraform-driven and standalone

Turning a provider's Layer 1/2 outputs into the `inventory.yml` Layer 3's
playbooks consume is the one piece of real per-provider glue code (see
above). Two producers are needed, both targeting the exact same output
contract so `ansible/<component>/playbook.yml` never needs to know or
care which one ran:

```
ansible/
├── inventory.example.yml              # documents the canonical inventory.yml schema —
│                                       # all.vars keys + all.children groups
│                                       # (nginx/control_plane/etcd/workers/rke2_cluster)
│                                       # both producers below must match
├── generate-inventory-from-env.sh     [NEW] # standalone/manual producer — see below
└── <component>/playbook.yml           # unchanged; consumes whichever inventory.yml it's given

.github/scripts/
└── generate-ansible-inventory.sh      # existing, UNCHANGED — Terraform-output + tfvars-driven
```

- **`.github/scripts/generate-ansible-inventory.sh` (existing, unchanged)**
  — the "deploy via Terraform, no manual input" path. Host IPs come from
  `terraform output -json` on the `compute` component; identity values
  (`cluster_name`, `cluster_env_domain`, `k8s_infra_repo_url`/`branch`,
  `subdomain_public`, etc.) are grepped straight out of committed
  `.tfvars` profile files; the SSH key comes from a GitHub secret. Zero
  interactive input beyond picking cloud/component/profile at dispatch
  time — this is the existing architecture and stays exactly as-is.
- **`ansible/generate-inventory-from-env.sh` (new, not yet built)** — the
  "deploy via Ansible directly, no Terraform" path, for cases like a data
  center with pre-existing/pre-racked hosts where there may be no
  Terraform compute step to read outputs from at all. Takes the same
  identity values as env vars instead of CLI flags/tfvars-parsing
  (`CLUSTER_NAME`, `CLUSTER_ENV_DOMAIN`, `K8S_INFRA_REPO_URL`,
  `K8S_INFRA_BRANCH`, `CERTBOT_EMAIL`, `NGINX_TYPE`, `SUBDOMAIN_PUBLIC`,
  `DEPLOYMENT_TYPE`, `SSH_KEY_FILE`), plus `NGINX_PUBLIC_IP`/
  `NGINX_PRIVATE_IP`, plus one structured env var for every cluster node:
  ```
  K8S_NODES="CONTROL-PLANE-NODE-1:10.0.0.5,ETCD-NODE-1:10.0.0.7,WORKER-NODE-1:10.0.0.6"
  ```
  using the same `<ROLE-PREFIX>-<N>` key convention
  `generate-ansible-inventory.sh` already uses to derive node groups, so
  both scripts key nodes identically. Runs standalone, anywhere — no CI,
  no Terraform required — which is what makes it a real Terraform-free
  path rather than just another CI job.

Both scripts render the identical schema, so `ansible/<component>/
playbook.yml` stays the single, unmodified consumer regardless of which
one produced the file. This is the concrete answer to "does the same
ansible script get reused either way" — yes, by construction, because the
playbooks never see which producer ran; they only ever see
`inventory.yml`.

## How `dns-providers/` would plug into `<provider>/dns`

Each provider's `dns` root gains a `domain_provider` variable (default:
that cloud's native DNS — `route53` for AWS, etc.; `godaddy` as an
alternative regardless of compute provider). The `dns` module delegates
actual record creation to the selected `dns-providers/<name>` module,
while zone/health-check resources that only make sense for the native
service stay behind a conditional. This keeps "where compute runs" and
"who manages the domain" as two independent choices instead of one
combined switch.

## CI dispatch changes this implies

`.github/workflows/terraform.yml` would need:
- `CLOUD_PROVIDER` gains a `datacenter` option.
- A new `DOMAIN_PROVIDER` input (`route53` / `azure-dns` / `cloud-dns` /
  `godaddy`), independent of `CLOUD_PROVIDER`.
- Layer 3 doesn't gain new `PROVISIONING_COMPONENT` entries — it's
  already reached via the existing `configure` option, decoupled from
  Terraform entirely (see "Dual-path inventory generation" above).
  Whether `configure` itself should get split into finer-grained,
  individually re-runnable steps is an open question — see "Gaps to
  resolve" below.

## Gaps to resolve before this becomes a real plan

- What "provisioning" concretely means for `datacenter` (inventory-only
  vs. actively driving hardware/hypervisor APIs) — this changes the shape
  of `modules/datacenter/compute/` significantly and needs a decision
  before that module gets designed.
- Whether `azure`/`gcp` layering, `datacenter` support, and the DNS
  registrar split are one initiative or three — they're independent
  enough to ship separately, and probably want separate parent issues
  rather than all hanging off #273.
- Item 4 (`datacenter`) is tracked as **#352** and item 5
  (`dns-providers`/GoDaddy) as **#353**, both linked under #273's
  sub-task checklist alongside #274–#282 — but neither has an
  implementation plan yet, only the design captured in this file. Item 3
  (`azure`/`gcp` mirroring the AWS layered split) still has no issue at
  all. Any of the three needs a concrete, approved plan (per the
  Guardrails) before code changes.
- `generate-ansible-inventory.sh` currently only reads AWS Layer 1/2
  outputs — extending it to azure/gcp/datacenter (once those exist) is
  the actual remaining integration work for Layer 3 reuse, not writing
  new playbooks.
- The legacy embedded provisioners (in `nginx-setup`, `rke2-cluster`,
  `nfs-setup`, `postgresql-setup`, `activemq-setup`,
  `rancher-keycloak-setup`) and their module-local `ansible/`/script
  copies still exist alongside the top-level ones and haven't been
  retired — both paths currently work, which is drift risk (the two
  copies can silently diverge) until one is deleted.
- `configure` currently runs all Layer-3 steps as one job gated by a
  single dispatch choice — rancher-import already has its own
  conditional step (matching #280's "standalone re-runnable" intent), but
  there's no way today to re-run *just* nginx or *just* nfs without
  triggering the whole `configure` job. Whether that's worth splitting
  into more granular dispatch inputs is an open question, not decided
  here.
- `ansible/generate-inventory-from-env.sh` (the new standalone/manual
  producer) is a design, not a script yet — no issue tracks building it.
  It also doesn't validate that a hand-built inventory's SSH
  connectivity/key format matches what the CI path guarantees implicitly
  (secrets written to a known path); a standalone user is responsible for
  that themselves.
