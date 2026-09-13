terraform {
  backend "azurerm" {
    resource_group_name  = "rg-movieops-tfstate"
    storage_account_name = "stmovieopstfstate"
    container_name       = "tfstate"
    key                  = "dev.terraform.tfstate"
  }
}
