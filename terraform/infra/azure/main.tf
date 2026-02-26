terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

# Azure Infrastructure Module (placeholder)
# TODO: Implement Azure-specific infrastructure

# For now, return placeholder outputs to maintain compatibility
locals {
  placeholder_message = "Azure infrastructure module not yet implemented"
}
