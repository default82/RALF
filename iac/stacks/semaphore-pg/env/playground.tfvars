# Semaphore – Playground Zone
# Werte ohne Secrets (Secrets kommen via Runner-Variablen)

proxmox_node = "pve-deploy"
ct_id        = 10015
hostname     = "ops-semaphore"

cores     = 2
memory    = 2048
disk_size = 16

ip_address    = "10.10.100.15/16"
gateway       = "10.10.0.1"
dns_server    = "10.10.0.1"
search_domain = "homelab.lan"
bridge        = "vmbr0"

zone              = "playground"
semaphore_version = "2.10.36"
semaphore_port    = 3000
