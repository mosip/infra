"""Tests for the dns role's record filter.

Run from the repo root:  python3 -m unittest discover -s ansible/roles/dns/tests
"""

import os
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "filter_plugins"))

from ansible.errors import AnsibleFilterError  # noqa: E402
from mosip_dns import mosip_dns_records, relative_name  # noqa: E402

DOMAIN = "soil38.mosip.net"


def by_fqdn(records):
    return {r["fqdn"]: r for r in records}


class RecordSet(unittest.TestCase):
    def test_same_records_as_the_terraform_module(self):
        recs = by_fqdn(mosip_dns_records(DOMAIN, "203.0.113.10", "10.0.0.10",
                                         ["resident", "prereg"], ["admin", "postgres"]))
        self.assertEqual(recs["api.soil38.mosip.net"], {
            "fqdn": "api.soil38.mosip.net", "type": "A", "value": "203.0.113.10", "ttl": 300, "name": "api"})
        self.assertEqual(recs["api-internal.soil38.mosip.net"]["value"], "10.0.0.10")
        self.assertEqual(recs[DOMAIN]["type"], "CNAME")
        self.assertEqual(recs[DOMAIN]["value"], "api-internal.soil38.mosip.net")
        self.assertEqual(recs["resident.soil38.mosip.net"]["value"], "api.soil38.mosip.net")
        self.assertEqual(recs["postgres.soil38.mosip.net"]["value"], "api-internal.soil38.mosip.net")
        self.assertEqual(len(recs), 3 + 2 + 2)

    def test_names_are_relative_to_the_zone(self):
        recs = by_fqdn(mosip_dns_records(DOMAIN, "1.1.1.1", "10.0.0.1", ["resident"], [], zone="mosip.net"))
        self.assertEqual(recs[DOMAIN]["name"], "soil38")
        self.assertEqual(recs["api.soil38.mosip.net"]["name"], "api.soil38")
        self.assertEqual(recs["resident.soil38.mosip.net"]["name"], "resident.soil38")

    def test_apex_is_at_sign_when_zone_equals_domain(self):
        recs = by_fqdn(mosip_dns_records(DOMAIN, "1.1.1.1", "10.0.0.1"))
        self.assertEqual(recs[DOMAIN]["name"], "@")

    def test_extra_records_and_ttl(self):
        recs = by_fqdn(mosip_dns_records(DOMAIN, "1.1.1.1", "10.0.0.1", ttl=600, extra=[
            {"name": "_verify.soil38.mosip.net.", "type": "txt", "value": "token-1"},
            {"name": "mail.soil38.mosip.net", "type": "A", "value": "198.51.100.5", "ttl": 3600},
        ]))
        self.assertEqual(recs["_verify.soil38.mosip.net"]["type"], "TXT")
        self.assertEqual(recs["_verify.soil38.mosip.net"]["ttl"], 600)
        self.assertEqual(recs["mail.soil38.mosip.net"]["ttl"], 3600)
        self.assertEqual(recs["api.soil38.mosip.net"]["ttl"], 600)


class Validation(unittest.TestCase):
    def test_record_outside_zone_rejected(self):
        with self.assertRaises(AnsibleFilterError):
            mosip_dns_records(DOMAIN, "1.1.1.1", "10.0.0.1", zone="other.org")

    def test_missing_ip_rejected(self):
        with self.assertRaises(AnsibleFilterError):
            mosip_dns_records(DOMAIN, "", "10.0.0.1")

    def test_duplicate_rejected(self):
        with self.assertRaises(AnsibleFilterError):
            mosip_dns_records(DOMAIN, "1.1.1.1", "10.0.0.1", ["admin"], ["admin"])

    def test_incomplete_extra_rejected(self):
        with self.assertRaises(AnsibleFilterError):
            mosip_dns_records(DOMAIN, "1.1.1.1", "10.0.0.1", extra=[{"name": "x.soil38.mosip.net"}])

    def test_relative_name_is_case_and_dot_insensitive(self):
        self.assertEqual(relative_name("API.Soil38.mosip.net.", "mosip.NET"), "api.soil38")


if __name__ == "__main__":
    unittest.main()
