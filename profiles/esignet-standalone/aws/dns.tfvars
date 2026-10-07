# dns-specific values — eSignet standalone profile — only eSignet-relevant subdomains
# Shared by the esignet-standalone and esignet-standalone-2.0.0 Helmsman
# profiles — only one is live on a given cluster/domain at a time.

subdomain_public   = ["esignet", "healthservices", "signup", "esignet-sunbird", "healthservices-sunbird", "healthservices-mosipid", "esignet-mosipid", "pms-mosipid", "signup-mosipid"]
subdomain_internal = ["iam", "activemq", "kafka", "kibana", "postgres", "smtp", "pmp", "minio"]
