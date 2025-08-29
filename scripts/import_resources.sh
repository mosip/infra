#!/bin/bash

set -e

echo "=================================================="
echo "🔄 Starting Terraform Resource Import Process"
echo "This will import all orphaned resources from the failed GitHub Actions run"
echo "=================================================="

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

import_resource() {
    local tf_address="$1"
    local aws_id="$2"
    local description="$3"
    
    echo -e "${YELLOW}Importing: $description${NC}"
    echo "  Terraform Address: $tf_address"
    echo "  AWS Resource ID: $aws_id"
    
    if terraform import "$tf_address" "$aws_id" 2>/dev/null; then
        echo -e "${GREEN}✅ Successfully imported: $description${NC}"
    else
        echo -e "${RED}❌ Failed to import: $description${NC}"
        echo "  This might be expected if the resource doesn't exist or is already imported"
    fi
    echo ""
}

echo ""
echo "=================================================="
echo "🖥️  Importing EC2 Instances"
echo "=================================================="

import_resource \
    "module.mosip_infra.module.aws_infra[0].module.aws_infrastructure.module.aws-resource-creation.aws_instance.NGINX_INSTANCE" \
    "i-02768d47788b669c4" \
    "NGINX Server (IP: 15.206.88.253)"

import_resource \
    "module.mosip_infra.module.aws_infra[0].module.aws_infrastructure.module.aws-resource-creation.aws_instance.K8S_CLUSTER_EC2_INSTANCE[\"CONTROL-PLANE-NODE-1\"]" \
    "i-0557c2c98a70f7e4d" \
    "Control Plane Node 1"

import_resource \
    "module.mosip_infra.module.aws_infra[0].module.aws_infrastructure.module.aws-resource-creation.aws_instance.K8S_CLUSTER_EC2_INSTANCE[\"CONTROL-PLANE-NODE-2\"]" \
    "i-08a7381073d54fd47" \
    "Control Plane Node 2"

import_resource \
    "module.mosip_infra.module.aws_infra[0].module.aws_infrastructure.module.aws-resource-creation.aws_instance.K8S_CLUSTER_EC2_INSTANCE[\"CONTROL-PLANE-NODE-3\"]" \
    "i-02781844a1039c8bb" \
    "Control Plane Node 3"

import_resource \
    "module.mosip_infra.module.aws_infra[0].module.aws_infrastructure.module.aws-resource-creation.aws_instance.K8S_CLUSTER_EC2_INSTANCE[\"ETCD-NODE-1\"]" \
    "i-0387db56ed0486a2b" \
    "ETCD Node 1"

import_resource \
    "module.mosip_infra.module.aws_infra[0].module.aws_infrastructure.module.aws-resource-creation.aws_instance.K8S_CLUSTER_EC2_INSTANCE[\"ETCD-NODE-2\"]" \
    "i-0563d079a8e111dc0" \
    "ETCD Node 2"

import_resource \
    "module.mosip_infra.module.aws_infra[0].module.aws_infrastructure.module.aws-resource-creation.aws_instance.K8S_CLUSTER_EC2_INSTANCE[\"ETCD-NODE-3\"]" \
    "i-0904d0ea61c0c88cc" \
    "ETCD Node 3"

import_resource \
    "module.mosip_infra.module.aws_infra[0].module.aws_infrastructure.module.aws-resource-creation.aws_instance.K8S_CLUSTER_EC2_INSTANCE[\"WORKER-NODE-1\"]" \
    "i-07e6088ab24c3bf3d" \
    "Worker Node 1"

import_resource \
    "module.mosip_infra.module.aws_infra[0].module.aws_infrastructure.module.aws-resource-creation.aws_instance.K8S_CLUSTER_EC2_INSTANCE[\"WORKER-NODE-2\"]" \
    "i-08f0ae8a10216c780" \
    "Worker Node 2"

echo ""
echo "=================================================="
echo "🔒 Importing Security Groups"
echo "=================================================="

import_resource \
    "module.mosip_infra.module.aws_infra[0].module.aws_infrastructure.module.aws-resource-creation.aws_security_group.security-group[\"NGINX_SECURITY_GROUP\"]" \
    "sg-0374655bb59ac983c" \
    "NGINX Security Group"

import_resource \
    "module.mosip_infra.module.aws_infra[0].module.aws_infrastructure.module.aws-resource-creation.aws_security_group.security-group[\"K8S_CONTROL_PLANE_SECURITY_GROUP\"]" \
    "sg-0115235fa4d50760b" \
    "K8s Control Plane Security Group"

import_resource \
    "module.mosip_infra.module.aws_infra[0].module.aws_infrastructure.module.aws-resource-creation.aws_security_group.security-group[\"K8S_ETCD_SECURITY_GROUP\"]" \
    "sg-0053ca87c65528e81" \
    "K8s ETCD Security Group"

import_resource \
    "module.mosip_infra.module.aws_infra[0].module.aws_infrastructure.module.aws-resource-creation.aws_security_group.security-group[\"K8S_WORKER_SECURITY_GROUP\"]" \
    "sg-0c2e9fb72afd673e1" \
    "K8s Worker Security Group"

echo ""
echo "=================================================="
echo "👤 Importing IAM Resources"
echo "=================================================="

import_resource \
    "module.mosip_infra.module.aws_infra[0].module.aws_infrastructure.module.aws-resource-creation.aws_iam_role.certbot_role" \
    "soil0-certbot-route53-role" \
    "Certbot IAM Role"

import_resource \
    "module.mosip_infra.module.aws_infra[0].module.aws_infrastructure.module.aws-resource-creation.aws_iam_policy.certbot_policy" \
    "arn:aws:iam::931337674770:policy/soil0-certbot-route53-policy" \
    "Certbot IAM Policy"

import_resource \
    "module.mosip_infra.module.aws_infra[0].module.aws_infrastructure.module.aws-resource-creation.aws_iam_instance_profile.certbot_profile" \
    "soil0-certbot-instance-profile" \
    "Certbot Instance Profile"

import_resource \
    "module.mosip_infra.module.aws_infra[0].module.aws_infrastructure.module.aws-resource-creation.aws_iam_role_policy_attachment.certbot_policy_attachment" \
    "soil0-certbot-route53-role/arn:aws:iam::931337674770:policy/soil0-certbot-route53-policy" \
    "Certbot Policy Attachment"

echo ""
echo "=================================================="
echo "🌐 Importing Route53 DNS Records"
echo "=================================================="

import_resource \
    "module.mosip_infra.module.aws_infra[0].module.aws_infrastructure.module.aws-resource-creation.aws_route53_record.DNS_RECORDS[\"API_DNS\"]" \
    "Z090954828SJIEL6P5406_api.soil0.mosip.net_A" \
    "API DNS Record"

import_resource \
    "module.mosip_infra.module.aws_infra[0].module.aws_infrastructure.module.aws-resource-creation.aws_route53_record.DNS_RECORDS[\"API_INTERNAL_DNS\"]" \
    "Z090954828SJIEL6P5406_api-internal.soil0.mosip.net_A" \
    "API Internal DNS Record"

import_resource \
    "module.mosip_infra.module.aws_infra[0].module.aws_infrastructure.module.aws-resource-creation.aws_route53_record.DNS_RECORDS[\"esignet\"]" \
    "Z090954828SJIEL6P5406_esignet.soil0.mosip.net_CNAME" \
    "Esignet DNS Record"

import_resource \
    "module.mosip_infra.module.aws_infra[0].module.aws_infrastructure.module.aws-resource-creation.aws_route53_record.DNS_RECORDS[\"healthservices\"]" \
    "Z090954828SJIEL6P5406_healthservices.soil0.mosip.net_CNAME" \
    "Health Services DNS Record"

import_resource \
    "module.mosip_infra.module.aws_infra[0].module.aws_infrastructure.module.aws-resource-creation.aws_route53_record.DNS_RECORDS[\"prereg\"]" \
    "Z090954828SJIEL6P5406_prereg.soil0.mosip.net_CNAME" \
    "Pre-registration DNS Record"

import_resource \
    "module.mosip_infra.module.aws_infra[0].module.aws_infrastructure.module.aws-resource-creation.aws_route53_record.DNS_RECORDS[\"resident\"]" \
    "Z090954828SJIEL6P5406_resident.soil0.mosip.net_CNAME" \
    "Resident DNS Record"

import_resource \
    "module.mosip_infra.module.aws_infra[0].module.aws_infrastructure.module.aws-resource-creation.aws_route53_record.DNS_RECORDS[\"signup\"]" \
    "Z090954828SJIEL6P5406_signup.soil0.mosip.net_CNAME" \
    "Signup DNS Record"

import_resource \
    "module.mosip_infra.module.aws_infra[0].module.aws_infrastructure.module.aws-resource-creation.aws_route53_record.DNS_RECORDS[\"activemq\"]" \
    "Z090954828SJIEL6P5406_activemq.soil0.mosip.net_CNAME" \
    "ActiveMQ DNS Record"

import_resource \
    "module.mosip_infra.module.aws_infra[0].module.aws_infrastructure.module.aws-resource-creation.aws_route53_record.DNS_RECORDS[\"admin\"]" \
    "Z090954828SJIEL6P5406_admin.soil0.mosip.net_CNAME" \
    "Admin DNS Record"

import_resource \
    "module.mosip_infra.module.aws_infra[0].module.aws_infrastructure.module.aws-resource-creation.aws_route53_record.DNS_RECORDS[\"compliance\"]" \
    "Z090954828SJIEL6P5406_compliance.soil0.mosip.net_CNAME" \
    "Compliance DNS Record"

import_resource \
    "module.mosip_infra.module.aws_infra[0].module.aws_infrastructure.module.aws-resource-creation.aws_route53_record.DNS_RECORDS[\"iam\"]" \
    "Z090954828SJIEL6P5406_iam.soil0.mosip.net_CNAME" \
    "IAM DNS Record"

import_resource \
    "module.mosip_infra.module.aws_infra[0].module.aws_infrastructure.module.aws-resource-creation.aws_route53_record.DNS_RECORDS[\"kafka\"]" \
    "Z090954828SJIEL6P5406_kafka.soil0.mosip.net_CNAME" \
    "Kafka DNS Record"

import_resource \
    "module.mosip_infra.module.aws_infra[0].module.aws_infrastructure.module.aws-resource-creation.aws_route53_record.DNS_RECORDS[\"kibana\"]" \
    "Z090954828SJIEL6P5406_kibana.soil0.mosip.net_CNAME" \
    "Kibana DNS Record"

import_resource \
    "module.mosip_infra.module.aws_infra[0].module.aws_infrastructure.module.aws-resource-creation.aws_route53_record.DNS_RECORDS[\"minio\"]" \
    "Z090954828SJIEL6P5406_minio.soil0.mosip.net_CNAME" \
    "Minio DNS Record"

import_resource \
    "module.mosip_infra.module.aws_infra[0].module.aws_infrastructure.module.aws-resource-creation.aws_route53_record.DNS_RECORDS[\"pmp\"]" \
    "Z090954828SJIEL6P5406_pmp.soil0.mosip.net_CNAME" \
    "PMP DNS Record"

import_resource \
    "module.mosip_infra.module.aws_infra[0].module.aws_infrastructure.module.aws-resource-creation.aws_route53_record.DNS_RECORDS[\"postgres\"]" \
    "Z090954828SJIEL6P5406_postgres.soil0.mosip.net_CNAME" \
    "Postgres DNS Record"

import_resource \
    "module.mosip_infra.module.aws_infra[0].module.aws_infrastructure.module.aws-resource-creation.aws_route53_record.DNS_RECORDS[\"regclient\"]" \
    "Z090954828SJIEL6P5406_regclient.soil0.mosip.net_CNAME" \
    "RegClient DNS Record"

import_resource \
    "module.mosip_infra.module.aws_infra[0].module.aws_infrastructure.module.aws-resource-creation.aws_route53_record.DNS_RECORDS[\"smtp\"]" \
    "Z090954828SJIEL6P5406_smtp.soil0.mosip.net_CNAME" \
    "SMTP DNS Record"

import_resource \
    "module.mosip_infra.module.aws_infra[0].module.aws_infrastructure.module.aws-resource-creation.aws_route53_record.DNS_RECORDS[\"soil0.mosip.net\"]" \
    "Z090954828SJIEL6P5406_soil0.mosip.net_CNAME" \
    "Root Domain DNS Record"

echo ""
echo "=================================================="
echo "🔍 Importing Other Resources"
echo "=================================================="

import_resource \
    "module.mosip_infra.module.aws_infra[0].module.aws_infrastructure.module.rke2-setup.random_string.K8S_TOKEN" \
    "2ZMhKv8xIFdLd6MUBL4np8rNeHQdIcgj" \
    "K8s Token"

import_resource \
    "module.mosip_infra.module.aws_infra[0].module.aws_infrastructure.null_resource.instance_type_validation" \
    "8621947192327935423" \
    "Instance Type Validation"

echo ""
echo "=================================================="
echo "📋 Import Process Summary"
echo "=================================================="

echo -e "${GREEN}✅ Import process completed!${NC}"
echo ""
echo "Resources imported into state:"
terraform state list | wc -l
echo ""
echo "State file created: terraform.tfstate"
