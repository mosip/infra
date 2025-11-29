terraform {
  backend "local" {
    path = "aws-infra-devupgrade-terraform.tfstate"
  }
}
