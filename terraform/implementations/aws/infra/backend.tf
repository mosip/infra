terraform {
  backend "local" {
    path = "aws-infra-minio-terraform.tfstate"
  }
}
