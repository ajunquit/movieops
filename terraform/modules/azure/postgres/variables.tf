variable "name" {
  description = "Globally unique server name"
  type        = string
}

variable "location" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "postgres_version" {
  type    = string
  default = "16"
}

variable "administrator_login" {
  type = string
}

variable "administrator_password" {
  type      = string
  sensitive = true
}

variable "sku_name" {
  description = "Cheapest burstable tier by default"
  type        = string
  default     = "B_Standard_B1ms"
}

variable "storage_mb" {
  type    = number
  default = 32768
}

variable "database_name" {
  type    = string
  default = "movieops"
}
