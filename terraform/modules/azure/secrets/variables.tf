variable "name" {
  description = "Globally unique vault name"
  type        = string
}

variable "location" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "tenant_id" {
  type = string
}

variable "automation_principal_object_ids" {
  description = "Stable map of automation principal Object IDs granted Key Vault Secrets Officer"
  type        = map(string)

  validation {
    condition = (
      length(var.automation_principal_object_ids) > 0 &&
      alltrue([
        for object_id in values(var.automation_principal_object_ids) :
        can(regex("^[0-9a-fA-F-]{36}$", object_id))
      ])
    )
    error_message = "Every automation principal Object ID must be a GUID."
  }
}
