variable "environment" {
  type    = string
  default = "dev"
}

variable "location" {
  type    = string
  default = "eastus2"
}

variable "postgres_admin_login" {
  type    = string
  default = "movieopsadmin"
}

variable "automation_principal_object_ids" {
  description = "Stable Microsoft Entra object IDs allowed to manage application secrets in Key Vault"
  type        = map(string)

  default = {
    github_actions = "36edcd2d-3ad8-4aa7-ad5e-e5998f17da2f"
    azure_devops   = "4fbfb3ed-ea64-4c58-85b2-eec87d5f21fb"
  }

  validation {
    condition = (
      contains(keys(var.automation_principal_object_ids), "github_actions") &&
      contains(keys(var.automation_principal_object_ids), "azure_devops") &&
      alltrue([
        for object_id in values(var.automation_principal_object_ids) :
        can(regex("^[0-9a-fA-F-]{36}$", object_id))
      ])
    )
    error_message = "automation_principal_object_ids must include valid github_actions and azure_devops Object IDs."
  }
}
