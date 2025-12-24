terraform {
  backend "local" {
    path = "aws-infra-gatest-terraform.tfstate"
  }
}
