terraform {
  backend "local" {
    path = "aws-infra-dev-terraform.tfstate"
  }
}
