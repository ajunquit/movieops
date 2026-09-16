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

variable "node_count" {
  description = "Two nodes minimum: a single B2s cannot fit the managed NGINX ingress controller (1000m) plus the app with headroom for a rolling update surge"
  type        = number
  default     = 2
}

variable "vm_size" {
  description = "Cheapest viable VM size"
  type        = string
  default     = "Standard_B2s"
}
