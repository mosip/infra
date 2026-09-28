terraform {
  backend "local" {
    path = "profiles/mosip/aws-infra-mosip-loki-terraform.tfstate"
  }
}
