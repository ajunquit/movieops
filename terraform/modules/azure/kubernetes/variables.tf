variable "name" {
  type = string
}

variable "location" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "subnet_id" {
  type = string
}

variable "acr_id" {
  type = string
}

variable "log_analytics_workspace_id" {
  type = string
}

variable "node_count" {
  description = "Cheapest viable node count for a lab cluster"
  type        = number
  default     = 1
}

variable "vm_size" {
  description = "Cheapest viable VM size"
  type        = string
  default     = "Standard_B2s"
}
