output "resource_group_name" {
  value = azurerm_resource_group.main.name
}

output "acr_login_server" {
  value = module.container_registry.login_server
}

output "postgres_fqdn" {
  value = module.postgres.server_fqdn
}

output "key_vault_uri" {
  value = module.secrets.vault_uri
}

output "aks_cluster_name" {
  value = module.kubernetes.cluster_name
}

output "log_analytics_workspace_id" {
  value = module.monitoring.workspace_id
}
