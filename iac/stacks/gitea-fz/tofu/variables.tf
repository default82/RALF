# --- Proxmox Connection ---
variable "proxmox_api_url" {
  description = "Proxmox API URL (z.B. https://10.10.10.10:8006)"
  type        = string
}

variable "proxmox_api_token" {
  description = "Proxmox API Token (format: user@realm!tokenid=secret)"
  type        = string
  sensitive   = true
}

variable "proxmox_insecure" {
  description = "Skip TLS verification"
  type        = bool
  default     = true
}

# --- Node ---
variable "proxmox_node" {
  description = "Proxmox node name"
  type        = string
  default     = "pve-deploy"
}

# --- Container ---
variable "ct_id" {
  description = "Container ID (Convention: 2012 = Bereich 20, Host 12)"
  type        = number
  default     = 2012
}

variable "hostname" {
  description = "Container hostname"
  type        = string
  default     = "svc-gitea"
}

variable "template" {
  description = "OS template (Proxmox storage:vztmpl/name)"
  type        = string
  default     = "local:vztmpl/ubuntu-24.04-standard_24.04-2_amd64.tar.zst"
}

# --- Resources ---
variable "cores" {
  description = "CPU cores"
  type        = number
  default     = 2
}

variable "memory" {
  description = "Memory in MB"
  type        = number
  default     = 2048
}

variable "disk_size" {
  description = "Root disk size in GB"
  type        = number
  default     = 16
}

variable "disk_storage" {
  description = "Proxmox storage pool for root disk"
  type        = string
  default     = "local-lvm"
}

# --- Network ---
variable "ip_address" {
  description = "Static IP with CIDR (z.B. 10.10.20.12/16)"
  type        = string
  default     = "10.10.20.12/16"
}

variable "gateway" {
  description = "Default gateway"
  type        = string
  default     = "10.10.0.1"
}

variable "dns_server" {
  description = "DNS server"
  type        = string
  default     = "10.10.0.1"
}

variable "search_domain" {
  description = "DNS search domain"
  type        = string
  default     = "homelab.lan"
}

variable "bridge" {
  description = "Proxmox network bridge"
  type        = string
  default     = "vmbr0"
}

# --- Zone ---
variable "zone" {
  description = "RALF zone (playground / functional)"
  type        = string
  default     = "functional"
}

# --- Gitea ---
variable "gitea_version" {
  description = "Gitea release version"
  type        = string
  default     = "1.22.6"
}

variable "gitea_http_port" {
  description = "Gitea HTTP port"
  type        = number
  default     = 3000
}

variable "gitea_ssh_port" {
  description = "Gitea SSH port"
  type        = number
  default     = 2222
}
