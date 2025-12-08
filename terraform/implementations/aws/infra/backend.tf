terraform {
  backend "local" {
    path = "aws-infra-dev-int-ga-terraform.tfstate"
  }
}
