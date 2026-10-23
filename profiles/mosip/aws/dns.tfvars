# dns-specific values. zone_id / cluster_env_domain come from ./common.tfvars.
#
# Subdomains live in ../profile.yml (subdomain_public / subdomain_internal) —
# the single source for both this component and the data-centre path. Set
# subdomain_public / subdomain_internal here only to override them.
#
# Everything below is optional.

# ── Add a subdomain to THIS environment (optional) ────────────────────────────
# Default (commented out): the subdomains in ../profile.yml.
# Uncomment to add names without repeating the profile's list — only the new
# names are written, everything else stays as it is:
# additional_subdomain_internal = ["grafana"]   # CNAME -> api-internal.<domain> (VPN only)
# additional_subdomain_public   = ["portal"]    # CNAME -> api.<domain> (internet)
# Then run COMPONENT=dns (non-Route53 providers: COMPONENT=configure). Expect
# "1 to add" per new name; the wildcard certificate already covers it, but
# the app needs an istio Gateway/VirtualService for the new host.
#   - A name that's already listed is ignored (no duplicate record).
#   - A record that exists in Route53 but was made by hand is taken over with
#     the planned value (allow_overwrite = true); set allow_overwrite = false
#     to make the apply fail instead.
#   - Back to default: remove the name and apply — only that record is deleted.
# Careful: subdomain_public / subdomain_internal (below) REPLACE the profile's
# list — a name left out of them is deleted.

# Several hosted zones (same AWS account), by ID or by name. Without `zones`,
# every record goes to zone_id from common.tfvars.
# zones = {
#   public   = { name = "mosip.example.org" }                  # public zone
#   internal = { name = "mosip.example.org", private = true }  # private zone, same name (split-horizon)
#   partner  = { zone_id = "Z0123456789ABCDEFGHI" }            # another domain
# }
# public_zone   = "public"     # api.<domain> + public subdomains
# internal_zone = "internal"   # api-internal.<domain>, bare domain, internal subdomains

# Any other record, in any zone above (default: the "default" zone).
# extra_records = {
#   verify = { name = "_verify.partner.org", type = "TXT", records = ["token"], zone = "partner" }
#   mail   = { name = "mosip.example.org", type = "MX", records = ["10 mx.example.org"] }
# }

# Point the records at a host that isn't the tagged nginx instance, e.g. a
# data-centre nginx whose domain is in Route53:
# nginx_public_ip  = "203.0.113.10"
# nginx_private_ip = "10.10.0.10"
