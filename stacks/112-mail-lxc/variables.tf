variable "pm_api_url" {
  type      = string
  sensitive = true
}

variable "pm_api_token_id" {
  type      = string
  sensitive = true
}

variable "pm_api_token_secret" {
  type      = string
  sensitive = true
}

variable "node_name" {
  type    = string
  default = "pve-deploy"
}

variable "ssh_public_key" {
  type = string
}

variable "lxc_template_id" {
  type        = string
  description = "Proxmox template volume id, e.g. local:vztmpl/ubuntu-24.04-standard_24.04-2_amd64.tar.zst"
  default     = "local:vztmpl/ubuntu-24.04-standard_24.04-2_amd64.tar.zst"
}
