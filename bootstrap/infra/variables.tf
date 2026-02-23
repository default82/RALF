variable "pm_api_url" {
  type = string
}

variable "pm_api_token_id" {
  type = string
  sensitive = true
}

variable "pm_api_token_secret" {
  type = string
  sensitive = true
}

variable "node_name" {
  type = string
  default = "pve-deploy"
}