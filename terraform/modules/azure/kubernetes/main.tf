resource "azurerm_kubernetes_cluster" "main" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  dns_prefix          = var.name
  sku_tier            = "Free"

  default_node_pool {
    name           = "default"
    node_count     = var.node_count
    vm_size        = var.vm_size
    vnet_subnet_id = var.subnet_id
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    # Must not overlap the VNet address space (10.0.0.0/16) the node subnet lives in.
    service_cidr   = "172.16.0.0/16"
    dns_service_ip = "172.16.0.10"
  }

  oms_agent {
    log_analytics_workspace_id = var.log_analytics_workspace_id
  }

  # Azure's managed NGINX ingress controller. dns_zone_ids = [] means: no
  # custom domain, just the default nip.io-style hostname — enough to
  # exercise Ingress as a concept without provisioning Azure DNS.
  web_app_routing {
    dns_zone_ids = []
  }
}

# Lets AKS pull images from ACR without imagePullSecrets.
resource "azurerm_role_assignment" "aks_acr_pull" {
  scope                = var.acr_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
}
