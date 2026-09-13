resource "azurerm_container_registry" "main" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = var.sku
  admin_enabled       = true # dev convenience; prefer AcrPull role assignments (see kubernetes module) for real pulls
}
