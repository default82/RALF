#!/usr/bin/env bash
set -euo pipefail

px_log() { printf '[proxmox-lxc] %s\n' "$*"; }
px_warn() { printf '[proxmox-lxc][warn] %s\n' "$*" >&2; }
px_err() { printf '[proxmox-lxc][error] %s\n' "$*" >&2; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { px_err "fehlender Befehl: $1"; return 1; }
}

ensure_template() {
  local storage="$1"
  local template="$2"

  require_cmd pveam || return 1

  if pveam list "$storage" 2>/dev/null | awk '{print $1}' | grep -qx "$template"; then
    px_log "Template vorhanden: ${storage}:vztmpl/${template}"
    return 0
  fi

  px_log "Template fehlt, lade herunter: ${template}"
  pveam update >/dev/null
  pveam download "$storage" "$template"
}

install_ssh_key_fallback() {
  local vmid="$1"
  local key_file="$2"

  if [[ ! -f "$key_file" ]]; then
    px_warn "SSH-Key-Datei fehlt: $key_file"
    return 0
  fi

  if pct set "$vmid" --ssh-public-keys "$key_file" >/dev/null 2>&1; then
    px_log "SSH-Key via pct --ssh-public-keys gesetzt"
    return 0
  fi

  px_warn "pct --ssh-public-keys nicht verfügbar, fallback in CT"
  pct start "$vmid" >/dev/null 2>&1 || true
  local key_content
  key_content="$(tr -d '\r' < "$key_file")"
  pct exec "$vmid" -- bash -lc "install -d -m 700 /root/.ssh && touch /root/.ssh/authorized_keys && chmod 600 /root/.ssh/authorized_keys && grep -qxF '${key_content}' /root/.ssh/authorized_keys || echo '${key_content}' >> /root/.ssh/authorized_keys"
}

ensure_lxc() {
  local vmid="$1"
  local hostname="$2"
  local ip_cidr="$3"
  local gateway="$4"
  local bridge="$5"
  local cores="$6"
  local mem_mb="$7"
  local disk_gb="$8"
  local storage="$9"
  local template_storage="${10}"
  local template_name="${11}"
  local ssh_pubkey_file="${12}"

  require_cmd pct || return 1

  ensure_template "$template_storage" "$template_name"

  if pct status "$vmid" >/dev/null 2>&1; then
    px_log "CT ${vmid} existiert bereits, aktualisiere Kernparameter"
    pct set "$vmid" \
      --hostname "$hostname" \
      --memory "$mem_mb" \
      --cores "$cores" \
      --net0 "name=eth0,bridge=${bridge},ip=${ip_cidr},gw=${gateway}" \
      --features "nesting=1" >/dev/null
  else
    px_log "Erstelle CT ${vmid} (${hostname} @ ${ip_cidr})"
    pct create "$vmid" "${template_storage}:vztmpl/${template_name}" \
      --hostname "$hostname" \
      --memory "$mem_mb" \
      --cores "$cores" \
      --rootfs "${storage}:${disk_gb}" \
      --net0 "name=eth0,bridge=${bridge},ip=${ip_cidr},gw=${gateway}" \
      --unprivileged 1 \
      --features "nesting=1" \
      --start 0
  fi

  install_ssh_key_fallback "$vmid" "$ssh_pubkey_file"

  px_log "Starte CT ${vmid}"
  pct start "$vmid" >/dev/null 2>&1 || true

  if ! pct status "$vmid" >/dev/null 2>&1; then
    px_err "CT ${vmid} konnte nicht gestartet/verifiziert werden"
    return 1
  fi
}
