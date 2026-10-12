# Plan: Enterprise-style documentation site for MOSIP infra

## Context
The infra work (#273, PRs #406–#411, #415) changed how MOSIP is deployed, and the docs now exist as ~28 separate Markdown files (~11k lines) spread over `docs/`, `index.md`, `terraform/`, `.github/`, `Rancher-keycloak-integration/`. They're accurate but hard to navigate: no single entry point, no search, mixed audiences (operators, DevOps, country teams), overlapping content (README 1,080 lines; WORKFLOW_GUIDE, TERRAFORM_WORKFLOW_GUIDE and DEPLOYMENT_SEQUENCE repeat each other).

**Goal:** a user-friendly, enterprise-product-style documentation site — clear navigation, search, "choose your path" landing page, task-based guides, reference and troubleshooting — built from the repo's Markdown so it stays reviewable in PRs and readable on GitHub.

**User's direction:** docs site in the repo; sections = Overview & architecture, Getting started, How-to + day-2 ops, Reference + troubleshooting + FAQ. **Plan first, then a prototype for review, then implement.**

## Approach
**MkDocs + Material for MkDocs**, `mkdocs.yml` at repo root, `docs_dir: docs`.
- Material features: top tabs + left nav + right TOC, instant search, dark/light toggle, admonitions (note/warning/tip), content tabs (AWS ↔ Data centre side by side), collapsible details, copy-to-clipboard code blocks, "edit this page" links, MOSIP logo (`docs/_images/MOSIP_Black.svg`).
- Mermaid diagrams render natively (`pymdownx.superfences` custom fence) — the README/architecture Mermaid blocks reuse as-is.
- `mkdocs-redirects` so old file paths keep working after pages move.
- Pinned build deps in `docs/requirements.txt`.
- Plain Markdown stays readable on GitHub; nothing generated is committed.

### Information architecture (site nav)
```
Home (index.md)                    "What is it" + 3 cards: Deploy on AWS · Deploy on your VMs · Day-2 operations
Overview
  Introduction                     problem, what you get, who it's for
  Architecture                     layers, diagrams, how the AWS and DC paths meet
  Concepts                         components, profiles, environments = branches, state, inventory, site.yml order
  Supported platforms              matrix: AWS full / DC + Azure + GCP via Ansible / DNS + TLS providers
Getting started
  Prerequisites                    tools, accounts, VM requirements
  Secrets & configuration          (from SECRET_GENERATION_GUIDE + README secrets)
  Quickstart: AWS                  base-infra → fill profile → COMPONENT=all → verify
  Quickstart: Data centre          hosts.yml → generate.py → site.yml (from DATACENTRE_DEPLOYMENT)
  Deploy MOSIP services            Helmsman flow (links existing HELMSMAN_* guides)
How-to guides
  Choose / add a profile           (PROFILES)
  DNS: providers & multi-zone      (DEPLOYMENT_SEQUENCE DNS sections, #409/#415)
  TLS certificates                 byo / http01 / dns01
  Add or remove nodes
  Standalone VM (bastion etc.)     COMPONENT=vm
  Observability cluster + Rancher import
  WireGuard access                 (terraform/base-infra/WIREGUARD_SETUP)
  Destroy an environment           (ENVIRONMENT_DESTRUCTION_GUIDE, HELMSMAN_DESTROY_GUIDE)
  Helmsman: external / MOSIP / eSignet / testrigs / DSF   (existing guides, moved under here)
Reference
  Workflow inputs                  terraform.yml / terraform-destroy.yml tables
  Terraform components             per root: creates, inputs (tfvars), outputs, depends on
  Ansible roles                    per role: what it does, key variables, defaults
  profile.yml & hosts.yml schema
  State & backends                 naming, local/GPG, remote, branch isolation
  Repository layout                (TREE_STRUCTURE)
  Scripts                          (.github/scripts/README)
Troubleshooting
  Error catalogue                  symptom → cause → fix (preflight messages, DCO, TLS, DNS, RKE2 join, disks)
  FAQ
Glossary                           (GLOSSARY)
Release notes                      v-next: decoupling, profiles, DC path, DNS providers (PR list)
```

### Page template (every page)
Title → one-line purpose → "Before you begin" (admonition) → numbered steps (AWS / Data centre tabs where they differ) → "Verify" → "Next steps" / related links. Plain English, second person, short sentences.

### Content strategy
- **Reuse, don't rewrite:** move existing guides into the tree (`git mv`, content kept), split oversized ones (README, WORKFLOW_GUIDE) into task pages, remove duplication.
- **index.md** shrinks to a short product overview + "Read the docs" link + quickstart summary (keeps GitHub landing useful).
- **New pages:** home, introduction, concepts, supported platforms, quickstart AWS, reference (workflow inputs, components, roles, schema), error catalogue, FAQ, release notes.
- Reference tables derived from the code (workflow `inputs:`, `variables.tf`, role `defaults/main.yml`) so they're accurate.

### Publishing & CI
- `.github/workflows/docs.yml`: on PR → `mkdocs build --strict` (fails on broken links/nav); on push to `develop` → deploy to GitHub Pages (`mkdocs gh-deploy` or `actions/deploy-pages`).
- **Dependency:** GitHub Pages must be enabled on `mosip/infra` by a repo admin — flag in the PR.
- Add a `docs` job to `infra-checks.yml` (strict build).

## Steps

**Branch:** `273-v2/08-docs-site` — created on origin from the stack tip `a154cdf4` (tracks `origin/273-v2/08-docs-site`). All docs work (prototype and implementation) happens here; pushes go to origin only.

### Phase 1 — Prototype (for review, nothing merged)
1. Check out `273-v2/08-docs-site`; prototype commits pushed to origin for review (no PR yet).
2. Add `mkdocs.yml` (theme, palette, logo, features, Mermaid, nav for the full IA above), `docs/requirements.txt`.
3. Write 5 representative pages fully: **Home**, **Architecture**, **Quickstart: AWS**, **DNS providers** (how-to with tabs), **Workflow inputs** (reference), **Error catalogue** (troubleshooting). Other nav entries point to existing files as-is or "coming soon" stubs.
4. Build locally (`mkdocs build --strict` in a scratch venv).
5. Share the preview: publish the built static site as a **private Artifact** (link to click through) + `mkdocs serve` instructions. Mermaid served from jsdelivr so it renders in the preview.
6. Collect feedback on look, navigation, page style before writing the rest.

### Phase 2 — Implement (after prototype approval)
1. New sub-issue under #273 ("docs: enterprise documentation site").
2. Restructure `docs/` per the IA; move/split existing guides; write remaining new pages; `mkdocs-redirects` for moved paths; fix all repo links (README, workflow READMEs, hosts.example.yml, code comments).
3. Slim index.md to overview + links.
4. `docs.yml` workflow + `docs` job in `infra-checks.yml`.
5. Commit (`-s`) on `273-v2/08-docs-site`, push to origin, draft PR "Stack 8 of 8" into upstream `GH-issue-273-v2`; update stack numbering in #406–#415 bodies.

## Critical files
- New: `mkdocs.yml`, `docs/requirements.txt`, `docs/index.md`, `docs/{overview,getting-started,guides,reference,troubleshooting}/…`, `docs/release-notes.md`, `.github/workflows/docs.yml`
- Moved/split: `docs/*.md` (all 20), `index.md`, `docs/guides/wireguard.md` (copied/linked), `.github/scripts/index.md`
- Edited: `.github/workflows/infra-checks.yml`, links in `index.md`, `.github/workflows/index.md`, `ansible/inventory/hosts.example.yml`
- Reused as sources: `.github/workflows/terraform*.yml` (inputs), `terraform/implementations/aws/*/variables.tf`, `ansible/roles/*/defaults/main.yml`, existing Mermaid diagrams in `index.md` / `docs/overview/architecture.md`

## Verification
- `mkdocs build --strict` passes (no broken links, every page in nav).
- Prototype: preview link opens; nav, search, dark mode, tabs, admonitions, Mermaid diagrams all work; one page per section reviewed.
- Implementation: link check across repo (no references to moved paths), old URLs redirect, GitHub rendering of moved Markdown still fine, `docs` job green in CI, all existing checks still green.

## Open points
- GitHub Pages on `mosip/infra` needs admin enablement (or publish elsewhere, e.g. Read the Docs).
- Versioned docs (per release, via `mike`) — not in scope now; can add later.
