# Gitea – Functional Zone
# Werte ohne Secrets (Secrets kommen via Runner-Variablen)

proxmox_node = "pve-deploy"
ct_id        = 2012
hostname     = "svc-gitea"

cores     = 2
memory    = 2048
disk_size = 16

ip_address    = "10.10.20.12/16"
gateway       = "10.10.0.1"
dns_server    = "10.10.0.1"
search_domain = "homelab.lan"
bridge        = "vmbr0"

zone          = "functional"
gitea_version = "1.22.6"
gitea_http_port = 3000
gitea_ssh_port  = 2222
