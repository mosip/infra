terraform {
  backend "local" {
    path = "aws-infra-terraform.tfstate"
  }
}
