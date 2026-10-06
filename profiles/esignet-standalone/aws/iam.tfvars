# iam — esignet-standalone profile. zone_id comes from ./common.tfvars; certbot may only
# change records in that zone. List every zone it needs when the domain's
# public zone differs, e.g. with a split-horizon dns.tfvars:
# certbot_zone_ids = ["Z0PUBLICZONEID00000"]
