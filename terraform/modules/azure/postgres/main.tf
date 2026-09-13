resource "azurerm_postgresql_flexible_server" "main" {
  name                   = var.name
  location               = var.location
  resource_group_name    = var.resource_group_name
  version                = var.postgres_version
  administrator_login    = var.administrator_login
  administrator_password = var.administrator_password
  sku_name               = var.sku_name
  storage_mb             = var.storage_mb
  zone                   = "1"

  # Public access with a firewall allow-list, kept private from the open internet.
  # VNet-integrated private access is a hardening item for later, not needed to validate provisioning.
}

resource "azurerm_postgresql_flexible_server_firewall_rule" "allow_azure_services" {
  name             = "AllowAzureServices"
  server_id        = azurerm_postgresql_flexible_server.main.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

resource "azurerm_postgresql_flexible_server_database" "app" {
  name      = var.database_name
  server_id = azurerm_postgresql_flexible_server.main.id
  charset   = "UTF8"
  collation = "en_US.utf8"
}
