# PostgreSQL – Functional Zone
# Werte ohne Secrets (Secrets kommen via Runner-Variablen)

proxmox_node = "pve-deploy"
ct_id        = 2010
hostname     = "svc-postgres"

cores     = 2
memory    = 2048
disk_size = 16

ip_address    = "10.10.20.10/16"
gateway       = "10.10.0.1"
dns_server    = "10.10.0.1"
search_domain = "homelab.lan"
bridge        = "vmbr0"

zone       = "functional"
pg_version = 16
