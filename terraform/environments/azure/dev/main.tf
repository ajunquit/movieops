resource "random_string" "suffix" {
  length  = 4
  special = false
  upper   = false
}

resource "azurerm_resource_group" "main" {
  name     = "rg-movieops-${var.environment}"
  location = var.location
}

module "network" {
  source = "../../../modules/azure/network"

  name_prefix         = "movieops-${var.environment}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
}

module "monitoring" {
  source = "../../../modules/azure/monitoring"

  name                = "log-movieops-${var.environment}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
}

module "container_registry" {
  source = "../../../modules/azure/container-registry"

  name                = "acrmovieops${var.environment}${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
}

module "secrets" {
  source = "../../../modules/azure/secrets"

  name                = "kv-movieops-${var.environment}-${random_string.suffix.result}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  admin_object_id     = data.azurerm_client_config.current.object_id
}

resource "random_password" "postgres_admin" {
  length      = 24
  special     = true
  min_upper   = 1
  min_lower   = 1
  min_numeric = 1
  min_special = 1
}

resource "azurerm_key_vault_secret" "postgres_admin_password" {
  name         = "postgres-admin-password"
  value        = random_password.postgres_admin.result
  key_vault_id = module.secrets.vault_id

  depends_on = [module.secrets]
}

module "postgres" {
  source = "../../../modules/azure/postgres"

  name                   = "psql-movieops-${var.environment}-${random_string.suffix.result}"
  location               = azurerm_resource_group.main.location
  resource_group_name    = azurerm_resource_group.main.name
  administrator_login    = var.postgres_admin_login
  administrator_password = random_password.postgres_admin.result
}

module "kubernetes" {
  source = "../../../modules/azure/kubernetes"

  name                       = "aks-movieops-${var.environment}"
  location                   = azurerm_resource_group.main.location
  resource_group_name        = azurerm_resource_group.main.name
  subnet_id                  = module.network.subnet_id
  acr_id                     = module.container_registry.id
  log_analytics_workspace_id = module.monitoring.workspace_id
}
