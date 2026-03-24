terraform {
  backend "local" {
    path = "azure-infra-testgrid-terraform.tfstate"
  }
}
