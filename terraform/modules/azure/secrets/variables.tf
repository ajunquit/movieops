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

variable "admin_object_id" {
  description = "Object ID granted Key Vault Secrets Officer (e.g. the identity running Terraform)"
  type        = string
}
