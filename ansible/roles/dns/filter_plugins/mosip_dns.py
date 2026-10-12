"""Filters that turn the deployment's identity into the MOSIP DNS record set.

Same records as terraform/modules/aws/dns, so the Terraform (Route53) path
and the Ansible path (any provider) always agree:

  api.<domain>            A      nginx public IP
  api-internal.<domain>   A      nginx private IP
  <domain>                CNAME  api-internal.<domain>
  <public sub>.<domain>   CNAME  api.<domain>
  <internal sub>.<domain> CNAME  api-internal.<domain>
  + any extra records
"""

from ansible.errors import AnsibleFilterError


def relative_name(fqdn, zone):
    """Record name relative to the zone apex ('@' for the apex itself)."""
    fqdn = fqdn.rstrip(".").lower()
    zone = zone.rstrip(".").lower()
    if fqdn == zone:
        return "@"
    if fqdn.endswith("." + zone):
        return fqdn[: -(len(zone) + 1)]
    raise AnsibleFilterError(f"record {fqdn} is not inside zone {zone} — set dns_zone to the zone apex")


def mosip_dns_records(domain, public_ip, private_ip, subdomain_public=None,
                      subdomain_internal=None, extra=None, ttl=300, zone=None):
    if not domain:
        raise AnsibleFilterError("cluster_env_domain is required")
    if not public_ip or not private_ip:
        raise AnsibleFilterError("nginx public and private IPs are required (dns_public_ip / dns_private_ip)")
    zone = zone or domain
    api = f"api.{domain}"
    api_internal = f"api-internal.{domain}"

    records = [
        {"fqdn": api, "type": "A", "value": public_ip},
        {"fqdn": api_internal, "type": "A", "value": private_ip},
        {"fqdn": domain, "type": "CNAME", "value": api_internal},
    ]
    records += [{"fqdn": f"{s}.{domain}", "type": "CNAME", "value": api} for s in (subdomain_public or [])]
    records += [{"fqdn": f"{s}.{domain}", "type": "CNAME", "value": api_internal} for s in (subdomain_internal or [])]

    for r in extra or []:
        missing = [k for k in ("name", "type", "value") if k not in r]
        if missing:
            raise AnsibleFilterError(f"dns_extra_records entry {r} is missing {missing}")
        records.append({"fqdn": r["name"].rstrip("."), "type": r["type"].upper(),
                        "value": str(r["value"]), "ttl": int(r.get("ttl", ttl))})

    seen = set()
    for r in records:
        r.setdefault("ttl", int(ttl))
        r["name"] = relative_name(r["fqdn"], zone)
        key = (r["fqdn"].lower(), r["type"])
        if key in seen:
            raise AnsibleFilterError(f"duplicate DNS record {r['fqdn']} {r['type']}")
        seen.add(key)
    return records


class FilterModule:
    def filters(self):
        return {"mosip_dns_records": mosip_dns_records, "mosip_dns_relative_name": relative_name}
