terraform {
  backend "local" {
    path = "aws-infra-ga-terraform.tfstate"
  }
}
