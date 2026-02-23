#!/usr/bin/env bash
set -euo pipefail

# === RALF Bootstrap Seed (Proxmox Host Script) ===
# Creates LXC + installs IaC toolchain inside it.

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

need() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing command: $1" >&2; exit 1; }; }
need pct
need pveam
need awk
need grep
need sort
need head
need tail

[[ -f "$SSH_PUBKEY_FILE" ]] || { echo "Missing SSH key"; exit 1; }

IP="${IP_CIDR%%/*}"
O3="$(awk -F. '{print $3}' <<<"$IP")"
O4="$(awk -F. '{print $4}' <<<"$IP")"
CTID="${CTID:-${O3}${O4}}"

echo "==> Target CTID=${CTID} Host=${CT_HOSTNAME}"

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

if ! pct status "$CTID" >/dev/null 2>&1; then
  pct create "$CTID" "$OSTEMPLATE" \
    --hostname "$CT_HOSTNAME" \
    --memory "$MEM_MB" \
    --cores "$CORES" \
    --rootfs "${STORAGE}:${DISK_GB}" \
    --net0 "name=eth0,bridge=${BRIDGE},ip=${IP_CIDR},gw=${GW}" \
    --unprivileged 1 \
    --features nesting=1 \
    --start 0
fi

pct start "$CTID" >/dev/null 2>&1 || true

# ---- SSH key inject (always safe fallback) ----
PUBKEY="$(cat "$SSH_PUBKEY_FILE")"
pct exec "$CTID" -- bash -lc "
set -e
install -d -m 0700 /root/.ssh
touch /root/.ssh/authorized_keys
chmod 0600 /root/.ssh/authorized_keys
grep -qxF '$PUBKEY' /root/.ssh/authorized_keys || echo '$PUBKEY' >> /root/.ssh/authorized_keys
"

# ---- Bootstrap Toolchain Installation ----
echo "==> Installing base toolchain inside container"

pct exec "$CTID" -- bash -lc '
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y --no-install-recommends \
  ca-certificates curl git gnupg jq unzip \
  python3 python3-venv python3-pip

# --- OpenTofu ---
if ! command -v tofu >/dev/null 2>&1; then
  install -d -m 0755 /etc/apt/keyrings
  curl -fsSL https://packages.opentofu.org/opentofu.gpg \
    | gpg --dearmor -o /etc/apt/keyrings/opentofu.gpg
  chmod 0644 /etc/apt/keyrings/opentofu.gpg
  echo "deb [signed-by=/etc/apt/keyrings/opentofu.gpg] https://packages.opentofu.org/opentofu/tofu/any/ any main" \
    > /etc/apt/sources.list.d/opentofu.list
  apt-get update
  apt-get install -y tofu
fi

# --- Terragrunt ---
if ! command -v terragrunt >/dev/null 2>&1; then
  TG_VER="v0.84.0"
  curl -fsSL -o /usr/local/bin/terragrunt \
    "https://github.com/gruntwork-io/terragrunt/releases/download/${TG_VER}/terragrunt_linux_amd64"
  chmod 0755 /usr/local/bin/terragrunt
fi

# --- Ansible (venv, sauber) ---
if ! command -v ansible >/dev/null 2>&1; then
  python3 -m venv /opt/ralf-venv
  /opt/ralf-venv/bin/pip install --upgrade pip wheel
  /opt/ralf-venv/bin/pip install "ansible-core==2.18.*"
  ln -sf /opt/ralf-venv/bin/ansible /usr/local/bin/ansible
  ln -sf /opt/ralf-venv/bin/ansible-playbook /usr/local/bin/ansible-playbook
fi

echo "==> Versions:"
tofu version | head -n1
terragrunt --version
ansible --version | head -n1
git --version
'

echo "==> Bootstrap ready."
