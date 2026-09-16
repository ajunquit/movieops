terraform {
  required_version = ">= 1.5"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "azurerm" {
  features {
    # Each environment lives in its own disposable resource group. Azure can
    # create auxiliary nested resources (for example, the ContainerInsights
    # Solution created by the former AKS oms_agent) that never enter Terraform
    # state. Apocalipsis must still remove the complete environment, so let the
    # Azure Resource Manager group deletion cascade over those resources.
    # The remote state is safe because it lives in rg-movieops-tfstate, which is
    # outside this configuration and is never targeted by this resource group.
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

data "azurerm_client_config" "current" {}
