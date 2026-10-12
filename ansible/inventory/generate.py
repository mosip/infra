#!/usr/bin/env python3
"""Render the Ansible inventory that ansible/site.yml consumes.

One output contract, two ways to produce it:

  AWS (after the Terraform components are applied):
    generate.py --profile profiles/mosip \
        --from-terraform /tmp/tf-outputs \
        --tfvars profiles/mosip/aws/common.tfvars \
        --set ansible_ssh_private_key_file=/path/key -o inventory.yml

  Data centre (pre-created VMs, no Terraform):
    generate.py --profile profiles/mosip --from-hosts hosts.yml -o inventory.yml

--from-terraform reads <dir>/compute.json (required) and <dir>/storage.json
(optional) — the output of `terraform output -json` for those components.
--from-hosts reads a hosts file shaped like ansible/inventory/hosts.example.yml.

Variable precedence, lowest to highest:
  profile.yml ansible_vars < tfvars identity values < hosts.yml vars < --set

Host naming follows the compute module's convention
(<cluster>-NGINX-NODE, <cluster>-CONTROL-PLANE-NODE-<n>, ...): the rke2 and
nfs roles derive kubeconfig paths from the primary's inventory hostname.
"""

import argparse
import json
import os
import re
import sys

try:
    import yaml
except ImportError:  # pragma: no cover - exercised only on broken setups
    sys.exit("generate.py needs PyYAML (it ships with Ansible: pip install pyyaml)")

VALID_COMPONENTS = [
    "nginx", "rke2", "rancher_import", "nfs",
    "postgresql", "activemq", "rancher_keycloak",
]

# (inventory group, compute-output key prefix, node_role hostvar)
NODE_GROUPS = [
    ("control_plane", "CONTROL-PLANE-NODE", "control-plane"),
    ("etcd", "ETCD-NODE", "etcd"),
    ("workers", "WORKER-NODE", "worker"),
]

# tfvars name -> ansible variable name, for the identity values the AWS path
# reads out of common.tfvars.
TFVARS_TO_ANSIBLE = {
    "cluster_name": "cluster_name",
    "cluster_env_domain": "cluster_env_domain",
    "mosip_email_id": "certbot_email",
}

REQUIRED_VARS = ["cluster_name", "cluster_env_domain", "k8s_infra_repo_url", "k8s_infra_branch"]


class InventoryError(Exception):
    pass


# ---------------------------------------------------------------- inputs --

def load_yaml(path):
    try:
        with open(path) as fh:
            return yaml.safe_load(fh) or {}
    except OSError as exc:
        raise InventoryError(f"cannot read {path}: {exc}") from exc


def load_profile(profile_dir):
    path = os.path.join(profile_dir, "profile.yml")
    profile = load_yaml(path)
    comps = profile.get("configure_components") or []
    unknown = [c for c in comps if c not in VALID_COMPONENTS]
    if unknown:
        raise InventoryError(f"{path}: unknown configure_components {unknown}; valid: {VALID_COMPONENTS}")
    if profile.get("nginx_type") not in ("mosip", "observability"):
        raise InventoryError(f"{path}: nginx_type must be 'mosip' or 'observability'")
    return profile


_TFVAR_LINE = re.compile(r'^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.+?)\s*$')


def strip_comment(line):
    """Drop a trailing # or // comment that isn't inside a quoted string."""
    in_quotes = False
    for i, ch in enumerate(line):
        if ch == '"' and (i == 0 or line[i - 1] != "\\"):
            in_quotes = not in_quotes
        elif not in_quotes and (ch == "#" or line.startswith("//", i)):
            return line[:i]
    return line


def parse_tfvars(path):
    """Parse the simple subset of HCL our tfvars use: `key = "string"`,
    numbers, booleans and single-line lists of strings. Anything else is
    ignored (it's Terraform-only and never needed by Ansible)."""
    values = {}
    try:
        with open(path) as fh:
            lines = fh.readlines()
    except OSError as exc:
        raise InventoryError(f"cannot read {path}: {exc}") from exc
    for raw in lines:
        m = _TFVAR_LINE.match(strip_comment(raw))
        if not m:
            continue
        key, val = m.group(1), m.group(2).strip()
        if val.startswith('"') and val.endswith('"'):
            values[key] = val[1:-1]
        elif val.startswith("[") and val.endswith("]"):
            values[key] = re.findall(r'"([^"]*)"', val)
        elif val in ("true", "false"):
            values[key] = val == "true"
        elif re.fullmatch(r"-?\d+", val):
            values[key] = int(val)
    return values


def _output(outputs, name, required=True):
    entry = outputs.get(name)
    if entry is None or entry.get("value") is None:
        if required:
            raise InventoryError(f"terraform output '{name}' is missing — has the component been applied?")
        return None
    return entry["value"]


def hosts_from_terraform(tf_dir):
    """Return (nginx, nodes, storage outputs or None) from terraform output JSON."""
    compute_path = os.path.join(tf_dir, "compute.json")
    if not os.path.isfile(compute_path):
        raise InventoryError(f"{compute_path} not found — apply the compute component first")
    with open(compute_path) as fh:
        compute = json.load(fh)

    nginx = {
        "address": _output(compute, "nginx_private_ip"),
        "public_ip": _output(compute, "nginx_public_ip"),
    }
    node_ips = _output(compute, "k8s_node_ips")  # {"CONTROL-PLANE-NODE-1": ip, ...}
    nodes = {group: [] for group, _, _ in NODE_GROUPS}
    for group, prefix, _ in NODE_GROUPS:
        keys = sorted((k for k in node_ips if k.startswith(prefix + "-")),
                      key=lambda k: int(k.rsplit("-", 1)[1]))
        nodes[group] = [node_ips[k] for k in keys]

    storage = None
    storage_path = os.path.join(tf_dir, "storage.json")
    if os.path.isfile(storage_path):
        with open(storage_path) as fh:
            storage = json.load(fh)
    return nginx, nodes, storage


def hosts_from_file(path):
    """Return (nginx, nodes, vars) from an operator-written hosts.yml."""
    doc = load_yaml(path)
    nginx = doc.get("nginx") or {}
    if isinstance(nginx, str):
        nginx = {"address": nginx}
    if not nginx.get("address"):
        raise InventoryError(f"{path}: nginx.address is required")
    nodes = {}
    for group, _, _ in NODE_GROUPS:
        entries = doc.get(group) or []
        if not isinstance(entries, list):
            raise InventoryError(f"{path}: '{group}' must be a list of addresses")
        nodes[group] = [str(e) for e in entries]
    return nginx, nodes, doc.get("vars") or {}


# ---------------------------------------------------------------- render --

def gate_components_on_storage(components, storage):
    """On AWS, postgresql/activemq only run when the storage component
    actually created their volume (volume size > 0) — same gate the legacy
    monolith and the old configure job used."""
    if storage is None:
        return components
    gated = list(components)
    for comp, output in (("postgresql", "postgresql_volume_id"), ("activemq", "activemq_volume_id")):
        if comp in gated and _output(storage, output, required=False) is None:
            gated.remove(comp)
    return gated


def validate(nginx, nodes, all_vars):
    missing = [v for v in REQUIRED_VARS if not all_vars.get(v)]
    if missing:
        raise InventoryError(f"missing required variables: {missing}")
    if not nodes.get("control_plane"):
        raise InventoryError("at least one control_plane node is required")
    addresses = [nginx["address"]] + [a for group in nodes.values() for a in group]
    duplicates = sorted({a for a in addresses if addresses.count(a) > 1})
    if duplicates:
        raise InventoryError(f"addresses listed more than once: {duplicates}")
    tls_mode = all_vars.get("tls_mode", "dns01")
    if tls_mode not in ("dns01", "http01", "byo"):
        raise InventoryError(f"tls_mode must be dns01|http01|byo, got {tls_mode!r}")
    if tls_mode == "byo" and not (all_vars.get("tls_cert_file") and all_vars.get("tls_key_file")):
        raise InventoryError("tls_mode=byo needs tls_cert_file and tls_key_file")
    if tls_mode != "byo" and not all_vars.get("certbot_email"):
        raise InventoryError(f"tls_mode={tls_mode} needs certbot_email")


def render(profile, nginx, nodes, all_vars, components):
    cluster = all_vars["cluster_name"]
    domain = all_vars["cluster_env_domain"]

    public_domains = [f"api.{domain}"] + [f"{s}.{domain}" for s in profile.get("subdomain_public") or []]
    all_node_ips = [a for group, _, _ in NODE_GROUPS for a in nodes.get(group, [])]

    derived = {
        "nginx_type": profile["nginx_type"],
        "configure_components": components,
        "subdomain_public": list(profile.get("subdomain_public") or []),
        "subdomain_internal": list(profile.get("subdomain_internal") or []),
        "public_domain_list": ",".join(public_domains),
        "k8s_node_ips_joined": ",".join(all_node_ips),
        "k8s_primary_control_plane_ip": nodes["control_plane"][0],
    }
    if nginx.get("public_ip"):
        derived["nginx_public_ip"] = nginx["public_ip"]

    inv_vars = dict(all_vars)
    inv_vars.update(derived)

    children = {
        "nginx": {"hosts": {f"{cluster}-NGINX-NODE": {"ansible_host": nginx["address"]}}},
    }
    rke2_children = {}
    for group, prefix, role in NODE_GROUPS:
        addrs = nodes.get(group, [])
        if not addrs:
            continue
        children[group] = {"hosts": {
            f"{cluster}-{prefix}-{i}": {"ansible_host": addr, "node_role": role}
            for i, addr in enumerate(addrs, start=1)
        }}
        rke2_children[group] = None
    children["rke2_cluster"] = {"children": rke2_children}

    return {"all": {"vars": inv_vars, "children": children}}


def parse_set(pairs):
    out = {}
    for pair in pairs or []:
        if "=" not in pair:
            raise InventoryError(f"--set expects key=value, got {pair!r}")
        key, value = pair.split("=", 1)
        out[key.strip()] = value
    return out


def build(args):
    profile = load_profile(args.profile)
    all_vars = dict(profile.get("ansible_vars") or {})
    all_vars.setdefault("ansible_user", "ubuntu")
    all_vars.setdefault("ansible_ssh_common_args", "-o StrictHostKeyChecking=no")
    components = list(profile.get("configure_components") or [])

    if args.from_terraform:
        nginx, nodes, storage = hosts_from_terraform(args.from_terraform)
        for tfvars in args.tfvars or []:
            for tf_key, value in parse_tfvars(tfvars).items():
                if tf_key in TFVARS_TO_ANSIBLE:
                    all_vars[TFVARS_TO_ANSIBLE[tf_key]] = value
        components = gate_components_on_storage(components, storage)
    else:
        nginx, nodes, file_vars = hosts_from_file(args.from_hosts)
        all_vars.update(file_vars)

    all_vars.update(parse_set(args.set))
    validate(nginx, nodes, all_vars)
    return render(profile, nginx, nodes, all_vars, components)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--profile", required=True, help="profile directory containing profile.yml")
    src = parser.add_mutually_exclusive_group(required=True)
    src.add_argument("--from-terraform", metavar="DIR", help="dir with compute.json [+ storage.json]")
    src.add_argument("--from-hosts", metavar="FILE", help="operator hosts file (data centre)")
    parser.add_argument("--tfvars", action="append", help="tfvars to read identity values from (terraform mode)")
    parser.add_argument("--set", action="append", metavar="KEY=VALUE", help="override any inventory variable")
    parser.add_argument("-o", "--output", required=True, help="inventory file to write")
    args = parser.parse_args(argv)

    try:
        inventory = build(args)
    except InventoryError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    with open(args.output, "w") as fh:
        fh.write("---\n# Generated by ansible/inventory/generate.py — do not edit by hand.\n")
        yaml.safe_dump(inventory, fh, sort_keys=False, default_flow_style=False)
    print(f"Wrote {args.output}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
