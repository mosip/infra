terraform {
  backend "local" {
    path = "aws-infra-chaos-terraform.tfstate"
  }
}
