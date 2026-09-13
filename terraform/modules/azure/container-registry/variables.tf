variable "name" {
  description = "Globally unique registry name (alphanumeric only)"
  type        = string
}

variable "location" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "sku" {
  type    = string
  default = "Basic"
}
