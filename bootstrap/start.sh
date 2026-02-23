#!/usr/bin/env bash
set -euo pipefail

# === RALF Bootstrap Seed ===

# -------- Pretty Progress --------
STEP=0
step() {
  STEP=$((STEP+1))
  echo -e "\n\033[1;34m[STEP ${STEP}] $1\033[0m"
}
ok() {
  echo -e "\033[1;32m✔ $1\033[0m"
}

# -------- Config --------
CT_HOSTNAME="${CT_HOSTNAME:-ralf-bootstrap}"
IP_CIDR="${IP_CIDR:-10.10.100.10/16}"
GW="${GW:-10.10.0.1}"
BRIDGE="${BRIDGE:-vmbr0}"
MEM_MB="${MEM_MB:-2048}"
CORES="${CORES:-1}"
DISK_GB="${DISK_GB:-32}"
STORAGE="${STORAGE:-local-lvm}"
TEMPLATE_STORAGE="${TEMPLATE_STORAGE:-local}"
SSH_PUBKEY_FILE="${SSH_PUBKEY_FILE:-/root/.ssh/ralf_ed25519.pub}"
DIST="${DIST:-ubuntu}"
SERIES="${SERIES:-24.04}"
FLAVOR="${FLAVOR:-standard}"

[[ -f "$SSH_PUBKEY_FILE" ]] || { echo "Missing SSH key"; exit 1; }

IP="${IP_CIDR%%/*}"
O3="$(awk -F. '{print $3}' <<<"$IP")"
O4="$(awk -F. '{print $4}' <<<"$IP")"
CTID="${CTID:-${O3}${O4}}"

step "Resolving template"
pveam update >/dev/null

CANDIDATES="$(
  pveam available -section system \
  | awk '{print $NF}' \
  | grep -E "^${DIST}-${SERIES}-${FLAVOR}_[0-9]+\.[0-9]+-[0-9]+_amd64\.tar\.(xz|zst)$" \
  || true
)"

[[ -n "$CANDIDATES" ]] || { echo "No template found"; exit 1; }

TEMPLATE="$(printf "%s\n" "$CANDIDATES" | sort -V | tail -n 1)"
CACHE="/var/lib/vz/template/cache/${TEMPLATE}"
[[ -f "$CACHE" ]] || pveam download "$TEMPLATE_STORAGE" "$TEMPLATE"
OSTEMPLATE="${TEMPLATE_STORAGE}:vztmpl/${TEMPLATE}"
ok "Template: $TEMPLATE"

CREATED=0

if ! pct status "$CTID" >/dev/null 2>&1; then
  step "Creating container $CTID"
  pct create "$CTID" "$OSTEMPLATE" \
    --hostname "$CT_HOSTNAME" \
    --memory "$MEM_MB" \
    --cores "$CORES" \
    --rootfs "${STORAGE}:${DISK_GB}" \
    --net0 "name=eth0,bridge=${BRIDGE},ip=${IP_CIDR},gw=${GW}" \
    --unprivileged 1 \
    --features nesting=1 \
    --start 0
  CREATED=1
  ok "Container created"
else
  step "Container exists — adjusting mutable settings"
  pct set "$CTID" \
    --hostname "$CT_HOSTNAME" \
    --memory "$MEM_MB" \
    --cores "$CORES" >/dev/null
  ok "Config ensured"
fi

step "Starting container"
pct start "$CTID" >/dev/null 2>&1 || true
ok "Container running"

step "Injecting SSH key"
PUBKEY="$(cat "$SSH_PUBKEY_FILE")"
pct exec "$CTID" -- bash -lc "
install -d -m 0700 /root/.ssh
touch /root/.ssh/authorized_keys
chmod 0600 /root/.ssh/authorized_keys
grep -qxF '$PUBKEY' /root/.ssh/authorized_keys || echo '$PUBKEY' >> /root/.ssh/authorized_keys
"
ok "SSH key ready"

step "Installing toolchain inside container"

pct exec "$CTID" -- bash -lc '
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

apt-get update -qq
apt-get install -y --no-install-recommends \
  ca-certificates curl git gnupg jq unzip \
  python3 python3-venv python3-pip >/dev/null

# OpenTofu
if ! command -v tofu >/dev/null 2>&1; then
  install -d -m 0755 /etc/apt/keyrings
  curl -fsSL https://packages.opentofu.org/opentofu.gpg \
    | gpg --dearmor -o /etc/apt/keyrings/opentofu.gpg
  chmod 0644 /etc/apt/keyrings/opentofu.gpg
  echo "deb [signed-by=/etc/apt/keyrings/opentofu.gpg] https://packages.opentofu.org/opentofu/tofu/any/ any main" \
    > /etc/apt/sources.list.d/opentofu.list
  apt-get update -qq
  apt-get install -y tofu >/dev/null
fi

# Terragrunt
if ! command -v terragrunt >/dev/null 2>&1; then
  TG_VER="v0.84.0"
  curl -fsSL -o /usr/local/bin/terragrunt \
    "https://github.com/gruntwork-io/terragrunt/releases/download/${TG_VER}/terragrunt_linux_amd64"
  chmod 0755 /usr/local/bin/terragrunt
fi

# Ansible
if ! command -v ansible >/dev/null 2>&1; then
  python3 -m venv /opt/ralf-venv
  /opt/ralf-venv/bin/pip install --upgrade pip wheel >/dev/null
  /opt/ralf-venv/bin/pip install ansible-core >/dev/null
  ln -sf /opt/ralf-venv/bin/ansible /usr/local/bin/ansible
  ln -sf /opt/ralf-venv/bin/ansible-playbook /usr/local/bin/ansible-playbook
fi
'

ok "Toolchain installed"

step "Bootstrap complete"
echo "Use: pct exec $CTID -- bash"
