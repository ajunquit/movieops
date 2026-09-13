variable "name_prefix" {
  description = "Prefix used to name network resources (e.g. movieops-dev)"
  type        = string
}

variable "location" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "vnet_address_space" {
  type    = list(string)
  default = ["10.0.0.0/16"]
}

variable "subnet_address_prefix" {
  type    = list(string)
  default = ["10.0.1.0/24"]
}
