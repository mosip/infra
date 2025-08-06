terraform {
  backend "s3" {
    bucket = "mosip-terraform-state-file-infra-testgrid"
    key    = "aws-infra-testgrid-terraform.tfstate"
    region = "ap-south-1"
  }
}
