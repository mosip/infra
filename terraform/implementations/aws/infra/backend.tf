terraform {
  backend "local" {
    path = "aws-infra-testgrid-terraform.tfstate"
  }
}
