resource "azurerm_key_vault" "main" {
  name                       = var.name
  location                   = var.location
  resource_group_name        = var.resource_group_name
  tenant_id                  = var.tenant_id
  sku_name                   = "standard"
  rbac_authorization_enabled = true
  purge_protection_enabled   = false # dev only: allows immediate purge on destroy
  soft_delete_retention_days = 7
}

resource "azurerm_role_assignment" "automation_secrets_officer" {
  for_each = var.automation_principal_object_ids

  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = each.value
}

moved {
  from = azurerm_role_assignment.current_user_secrets_officer
  to   = azurerm_role_assignment.automation_secrets_officer["github_actions"]
}
