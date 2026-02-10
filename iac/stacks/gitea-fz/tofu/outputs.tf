output "ct_id" {
  description = "Container ID"
  value       = proxmox_virtual_environment_container.gitea.vm_id
}

output "hostname" {
  description = "Container hostname"
  value       = var.hostname
}

output "ip_address" {
  description = "Container IP"
  value       = var.ip_address
}

output "fqdn" {
  description = "Fully qualified domain name"
  value       = "${var.hostname}.${var.search_domain}"
}

output "gitea_http_url" {
  description = "Gitea Web UI URL (intern)"
  value       = "http://${replace(var.ip_address, "/\\/.*/", "")}:${var.gitea_http_port}"
}

output "gitea_ssh" {
  description = "Gitea SSH clone URL"
  value       = "ssh://git@${replace(var.ip_address, "/\\/.*/", "")}:${var.gitea_ssh_port}"
}
