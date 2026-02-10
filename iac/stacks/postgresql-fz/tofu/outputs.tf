output "ct_id" {
  description = "Container ID"
  value       = proxmox_virtual_environment_container.postgresql.vm_id
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

output "pg_port" {
  description = "PostgreSQL port"
  value       = 5432
}
