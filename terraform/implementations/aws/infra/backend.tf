terraform {
  backend "s3" {
    bucket = "mosip-terraform-state1-infra-testgrid"
    key    = "aws-infra-testgrid-terraform.tfstate"
    region = "ap-south-1"
  }
}
