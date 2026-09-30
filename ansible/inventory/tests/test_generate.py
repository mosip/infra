"""Tests for ansible/inventory/generate.py.

Run from the repo root:  python3 -m unittest discover -s ansible/inventory/tests
"""

import json
import os
import sys
import tempfile
import textwrap
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
sys.path.insert(0, os.path.join(REPO, "ansible", "inventory"))

import generate  # noqa: E402
import yaml  # noqa: E402

PROFILES = os.path.join(REPO, "profiles")


def write(path, content):
    with open(path, "w") as fh:
        fh.write(textwrap.dedent(content))
    return path


class Fixture(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = self.tmp.name
        self.tf_dir = os.path.join(self.dir, "tf")
        os.mkdir(self.tf_dir)
        self.tfvars = write(os.path.join(self.dir, "common.tfvars"), '''
            # identity
            cluster_name       = "dev1"          # trailing comment
            cluster_env_domain = "dev1.example.org"
            mosip_email_id     = "ops@example.org"
            ami                = "ami-123"
            vpc_name           = "vpc # not a comment"
        ''')

    def tearDown(self):
        self.tmp.cleanup()

    def compute(self, cp=3, etcd=3, workers=1):
        nodes = {}
        for i in range(cp):
            nodes[f"CONTROL-PLANE-NODE-{i + 1}"] = f"10.0.1.{10 + i}"
        for i in range(etcd):
            nodes[f"ETCD-NODE-{i + 1}"] = f"10.0.2.{10 + i}"
        for i in range(workers):
            nodes[f"WORKER-NODE-{i + 1}"] = f"10.0.3.{10 + i}"
        with open(os.path.join(self.tf_dir, "compute.json"), "w") as fh:
            json.dump({
                "nginx_public_ip": {"value": "203.0.113.10"},
                "nginx_private_ip": {"value": "10.0.0.10"},
                "k8s_node_ips": {"value": nodes},
            }, fh)

    def storage(self, pg=True, amq=True):
        with open(os.path.join(self.tf_dir, "storage.json"), "w") as fh:
            json.dump({
                "postgresql_volume_id": {"value": "vol-pg" if pg else None},
                "activemq_volume_id": {"value": "vol-amq" if amq else None},
            }, fh)

    def run_gen(self, *extra, profile="mosip"):
        out = os.path.join(self.dir, "inventory.yml")
        rc = generate.main(["--profile", os.path.join(PROFILES, profile), "-o", out, *extra])
        if rc != 0:
            return rc, None
        with open(out) as fh:
            return rc, yaml.safe_load(fh)

    def from_terraform(self, *extra, profile="mosip"):
        return self.run_gen("--from-terraform", self.tf_dir, "--tfvars", self.tfvars, *extra, profile=profile)


class TerraformMode(Fixture):
    def test_hosts_groups_and_names_follow_compute_convention(self):
        self.compute()
        rc, inv = self.from_terraform()
        self.assertEqual(rc, 0)
        children = inv["all"]["children"]
        self.assertEqual(children["nginx"]["hosts"], {"dev1-NGINX-NODE": {"ansible_host": "10.0.0.10"}})
        self.assertEqual(list(children["control_plane"]["hosts"]),
                         ["dev1-CONTROL-PLANE-NODE-1", "dev1-CONTROL-PLANE-NODE-2", "dev1-CONTROL-PLANE-NODE-3"])
        self.assertEqual(children["etcd"]["hosts"]["dev1-ETCD-NODE-2"],
                         {"ansible_host": "10.0.2.11", "node_role": "etcd"})
        self.assertEqual(children["workers"]["hosts"]["dev1-WORKER-NODE-1"]["node_role"], "worker")
        self.assertEqual(set(children["rke2_cluster"]["children"]), {"control_plane", "etcd", "workers"})

    def test_identity_and_derived_vars(self):
        self.compute()
        _, inv = self.from_terraform()
        v = inv["all"]["vars"]
        self.assertEqual(v["cluster_name"], "dev1")
        self.assertEqual(v["certbot_email"], "ops@example.org")
        self.assertEqual(v["nginx_public_ip"], "203.0.113.10")
        self.assertEqual(v["k8s_primary_control_plane_ip"], "10.0.1.10")
        self.assertTrue(v["public_domain_list"].startswith("api.dev1.example.org,resident.dev1.example.org"))
        self.assertEqual(v["nginx_type"], "mosip")
        self.assertEqual(v["configure_components"],
                         ["nginx", "rke2", "rancher_import", "nfs", "postgresql", "activemq"])

    def test_node_numbering_sorts_numerically(self):
        self.compute(cp=11, etcd=0, workers=0)
        _, inv = self.from_terraform()
        names = list(inv["all"]["children"]["control_plane"]["hosts"])
        self.assertEqual(names[1], "dev1-CONTROL-PLANE-NODE-2")
        self.assertEqual(names[10], "dev1-CONTROL-PLANE-NODE-11")

    def test_storage_gates_postgresql_and_activemq(self):
        self.compute()
        self.storage(pg=False, amq=True)
        _, inv = self.from_terraform()
        comps = inv["all"]["vars"]["configure_components"]
        self.assertNotIn("postgresql", comps)
        self.assertIn("activemq", comps)

    def test_observ_single_node_shape(self):
        self.compute(cp=1, etcd=0, workers=0)
        _, inv = self.from_terraform(profile="observ")
        children = inv["all"]["children"]
        self.assertNotIn("etcd", children)
        self.assertNotIn("workers", children)
        self.assertEqual(list(children["rke2_cluster"]["children"]), ["control_plane"])
        self.assertEqual(inv["all"]["vars"]["nginx_type"], "observability")
        self.assertIn("rancher_keycloak", inv["all"]["vars"]["configure_components"])

    def test_missing_compute_output_fails(self):
        rc, _ = self.from_terraform()
        self.assertEqual(rc, 1)


class HostsMode(Fixture):
    HOSTS = '''
        vars:
          cluster_name: dev1
          cluster_env_domain: dev1.example.org
          certbot_email: ops@example.org
        nginx:
          address: 10.0.0.10
          public_ip: 203.0.113.10
        control_plane: [10.0.1.10, 10.0.1.11, 10.0.1.12]
        etcd: [10.0.2.10, 10.0.2.11, 10.0.2.12]
        workers: [10.0.3.10]
    '''

    def test_same_hosts_render_same_inventory_as_terraform_mode(self):
        self.compute()
        _, tf_inv = self.from_terraform()
        hosts = write(os.path.join(self.dir, "hosts.yml"), self.HOSTS)
        _, dc_inv = self.run_gen("--from-hosts", hosts)
        self.assertEqual(dc_inv["all"]["children"], tf_inv["all"]["children"])
        for key in ("public_domain_list", "k8s_node_ips_joined", "k8s_primary_control_plane_ip",
                    "configure_components", "nginx_type", "nginx_public_ip", "cluster_name"):
            self.assertEqual(dc_inv["all"]["vars"][key], tf_inv["all"]["vars"][key], key)

    def test_hosts_vars_override_profile_defaults_and_set_overrides_everything(self):
        hosts = write(os.path.join(self.dir, "hosts.yml"), self.HOSTS)
        with open(hosts) as fh:
            doc = yaml.safe_load(fh)
        doc["vars"]["k8s_infra_branch"] = "my-branch"
        doc["vars"]["tls_mode"] = "http01"
        with open(hosts, "w") as fh:
            yaml.safe_dump(doc, fh)
        _, inv = self.run_gen("--from-hosts", hosts, "--set", "tls_mode=byo",
                              "--set", "tls_cert_file=/c.pem", "--set", "tls_key_file=/k.pem")
        v = inv["all"]["vars"]
        self.assertEqual(v["k8s_infra_branch"], "my-branch")
        self.assertEqual(v["tls_mode"], "byo")

    def test_no_terraform_outputs_needed(self):
        hosts = write(os.path.join(self.dir, "hosts.yml"), self.HOSTS)
        rc, inv = self.run_gen("--from-hosts", hosts)
        self.assertEqual(rc, 0)
        # hosts mode never gates on storage outputs
        self.assertIn("postgresql", inv["all"]["vars"]["configure_components"])


class Validation(Fixture):
    def hosts(self, body):
        return write(os.path.join(self.dir, "hosts.yml"), body)

    def test_missing_identity_fails(self):
        path = self.hosts('''
            vars: {cluster_env_domain: d.example.org, certbot_email: a@b.c}
            nginx: {address: 10.0.0.10}
            control_plane: [10.0.1.10]
        ''')
        self.assertEqual(self.run_gen("--from-hosts", path)[0], 1)

    def test_byo_without_cert_files_fails(self):
        path = self.hosts('''
            vars: {cluster_name: c, cluster_env_domain: d.example.org, tls_mode: byo}
            nginx: {address: 10.0.0.10}
            control_plane: [10.0.1.10]
        ''')
        self.assertEqual(self.run_gen("--from-hosts", path)[0], 1)

    def test_duplicate_address_fails(self):
        path = self.hosts('''
            vars: {cluster_name: c, cluster_env_domain: d.example.org, certbot_email: a@b.c}
            nginx: {address: 10.0.0.10}
            control_plane: [10.0.0.10]
        ''')
        self.assertEqual(self.run_gen("--from-hosts", path)[0], 1)

    def test_no_control_plane_fails(self):
        path = self.hosts('''
            vars: {cluster_name: c, cluster_env_domain: d.example.org, certbot_email: a@b.c}
            nginx: {address: 10.0.0.10}
        ''')
        self.assertEqual(self.run_gen("--from-hosts", path)[0], 1)


class TfvarsParsing(Fixture):
    def test_comments_quotes_and_lists(self):
        path = write(os.path.join(self.dir, "x.tfvars"), '''
            a = "x"   # comment
            b = "has # inside"
            c = ["p", "q"] // comment
            d = 3
            e = true
            f = {
        ''')
        parsed = generate.parse_tfvars(path)
        self.assertEqual(parsed, {"a": "x", "b": "has # inside", "c": ["p", "q"], "d": 3, "e": True})


if __name__ == "__main__":
    unittest.main()
