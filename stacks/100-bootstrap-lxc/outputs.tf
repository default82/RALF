output "bootstrap_vm_id" {
  value = proxmox_virtual_environment_container.bootstrap.vm_id
}

output "bootstrap_name" {
  value = proxmox_virtual_environment_container.bootstrap.name
}

output "bootstrap_ipv4" {
  value = "10.10.100.10"
}