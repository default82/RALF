#!/usr/bin/env bash
set -euo pipefail

# === RALF Bootstrap Seed ===
# Runs on the Proxmox host. Creates/updates/starts an LXC CT and bootstraps RALF.
#
# One-liner:
#   curl -fsSL https://raw.githubusercontent.com/default82/RALF/main/bootstrap/start.sh | bash
#
# Cache-bust:
#   curl -fsSL "https://raw.githubusercontent.com/default82/RALF/main/bootstrap/start.sh?nocache=$(date +%s)" | bash
#
# Runner controls (host side, forwarded into CT):
#   AUTO_APPLY=1 START_AT=030 ONLY_STACKS="030-minio-lxc 031-minio-config" bash start.sh
#
# Quality-of-life toggles:
#   NO_TOOLCHAIN=1   # skip apt/tofu/terragrunt install step
#   NO_RUNNER=1      # skip running bootstrap/runner.sh
#   NO_SECRETS=1     # skip pve.env injection
#   NO_GIT=1         # skip repo checkout/update
#   NO_SSHKEY=1      # skip authorized_keys injection

export PATH=/usr/sbin:/usr/bin:/sbin:/bin

# --------------------------
# Config (safe defaults)
# --------------------------
CT_HOSTNAME="${CT_HOSTNAME:-ralf-bootstrap}"   # IMPORTANT: don't use HOSTNAME (env var collision)

IP_CIDR="${IP_CIDR:-10.10.100.10/16}"
GW="${GW:-10.10.0.1}"
BRIDGE="${BRIDGE:-vmbr0}"

MEM_MB="${MEM_MB:-2048}"
CORES="${CORES:-1}"
DISK_GB="${DISK_GB:-32}"

STORAGE="${STORAGE:-local-lvm}"               # rootfs storage (lvmthin)
TEMPLATE_STORAGE="${TEMPLATE_STORAGE:-local}" # 'dir' storage that has vztmpl content

SSH_PUBKEY_FILE="${SSH_PUBKEY_FILE:-/root/.ssh/ralf_ed25519.pub}"

# Secrets (host -> CT injection)
HOST_PVE_ENV="${HOST_PVE_ENV:-/root/ralf-secrets/pve.env}"     # lives on Proxmox host
CT_PVE_ENV="${CT_PVE_ENV:-/opt/ralf/runtime/secrets/pve.env}"  # expected path inside CT

# Template selection
DIST="${DIST:-ubuntu}"
SERIES="${SERIES:-24.04}"
FLAVOR="${FLAVOR:-standard}"

# RALF repo
RALF_GIT_URL="${RALF_GIT_URL:-https://github.com/default82/RALF}"
RALF_BASE="${RALF_BASE:-/opt/ralf}"
RALF_REPO="${RALF_REPO:-/opt/ralf/repo}"
RALF_RUNTIME="${RALF_RUNTIME:-/opt/ralf/runtime}"

FORCE_RECREATE="${FORCE_RECREATE:-0}"
UNPRIVILEGED="${UNPRIVILEGED:-1}"
FEATURES="${FEATURES:-nesting=1,keyctl=1}"
ONBOOT="${ONBOOT:-0}"
STARTUP="${STARTUP:-}"

# Toggles
NO_TOOLCHAIN="${NO_TOOLCHAIN:-0}"
NO_RUNNER="${NO_RUNNER:-0}"
NO_SECRETS="${NO_SECRETS:-0}"
NO_GIT="${NO_GIT:-0}"
NO_SSHKEY="${NO_SSHKEY:-0}"

# Runner controls (forwarded)
AUTO_APPLY="${AUTO_APPLY:-0}"
START_AT="${START_AT:-030}"
ONLY_STACKS="${ONLY_STACKS:-}"

# --------------------------
# UI helpers
# --------------------------
STEP_NO="0"
step() { STEP_NO="$1"; echo; echo "[STEP $1] $2"; }
ok()   { echo "✔ $1"; }
warn() { echo "⚠ $1" >&2; }
die()  { echo "ERROR: $1" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "missing command: $1"; }

on_err() {
  local ec=$?
  warn "Failed at STEP ${STEP_NO}. Exit code: ${ec}"
  warn "Tip: re-run with cache-bust: curl -fsSL \"https://raw.githubusercontent.com/default82/RALF/main/bootstrap/start.sh?nocache=\$(date +%s)\" | bash"
  exit "$ec"
}
trap on_err ERR

# --------------------------
# Requirements (host)
# --------------------------
need pct
need pveam
need awk
need grep
need sort
need head
need tail
need printf
need sed
need base64

# --------------------------
# Validate SSH key presence (unless skipped)
# --------------------------
if [[ "$NO_SSHKEY" != "1" ]]; then
  [[ -f "$SSH_PUBKEY_FILE" ]] || die "SSH public key not found at $SSH_PUBKEY_FILE (or set NO_SSHKEY=1)"
fi

# --------------------------
# Derive CTID from IP (3rd+4th octet concat) unless CTID is provided
# --------------------------
IP="${IP_CIDR%%/*}"
O3="$(awk -F. '{print $3}' <<<"$IP")"
O4="$(awk -F. '{print $4}' <<<"$IP")"

[[ "${CTID:-}" =~ ^[0-9]+$ ]] || true
if [[ -z "${CTID:-}" ]]; then
  [[ "$O3" =~ ^[0-9]+$ ]] || die "IP third octet is not numeric: $O3"
  [[ "$O4" =~ ^[0-9]+$ ]] || die "IP fourth octet is not numeric: $O4"
  (( O3 >= 0 && O3 <= 255 )) || die "IP third octet out of range: $O3"
  (( O4 >= 0 && O4 <= 255 )) || die "IP fourth octet out of range: $O4"
  CTID="${O3}${O4}"  # e.g. 100 + 10 => "10010"
fi

echo "==> Target: CTID=${CTID} CT_HOSTNAME=${CT_HOSTNAME} IP=${IP_CIDR} GW=${GW} BRIDGE=${BRIDGE}"
echo "==> Storage: rootfs=${STORAGE} templates=${TEMPLATE_STORAGE}"
echo "==> Options: unprivileged=${UNPRIVILEGED} features=${FEATURES} onboot=${ONBOOT} startup='${STARTUP}'"
echo "==> Toggles: NO_TOOLCHAIN=${NO_TOOLCHAIN} NO_GIT=${NO_GIT} NO_SECRETS=${NO_SECRETS} NO_RUNNER=${NO_RUNNER} NO_SSHKEY=${NO_SSHKEY}"
echo "==> Runner: AUTO_APPLY=${AUTO_APPLY} START_AT=${START_AT} ONLY_STACKS='${ONLY_STACKS}'"

ct_exists()   { pct status "${CTID}" >/dev/null 2>&1; }
ct_running()  { pct status "${CTID}" 2>/dev/null | grep -q "running"; }

# --------------------------
# Optional: Force recreate
# --------------------------
if [[ "$FORCE_RECREATE" == "1" ]]; then
  step 0 "FORCE_RECREATE=1 — destroying CT ${CTID}"
  pct stop "${CTID}" >/dev/null 2>&1 || true
  if ct_exists; then
    pct destroy "${CTID}" --purge 1
    ok "CT destroyed"
  else
    ok "CT did not exist"
  fi
fi

# --------------------------
# STEP 1: Resolve latest template
# --------------------------
step 1 "Resolving template"
pveam update >/dev/null

CANDIDATES="$(
  pveam available -section system \
    | awk '{print $NF}' \
    | grep -E "^${DIST}-${SERIES}-${FLAVOR}_[0-9]+\.[0-9]+-[0-9]+_amd64\.tar\.(xz|zst)$" \
    || true
)"

if [[ -z "$CANDIDATES" ]]; then
  warn "No matching template found for ${DIST}-${SERIES}-${FLAVOR}"
  warn "Available ${DIST} templates (first 30):"
  pveam available -section system | awk '{print $NF}' | grep -i "^${DIST}" | head -n 30 >&2 || true
  exit 1
fi

TEMPLATE="$(printf "%s\n" "$CANDIDATES" | sort -V | tail -n 1)"
ok "Template: ${TEMPLATE}"

CACHE="/var/lib/vz/template/cache/${TEMPLATE}"
if [[ -f "$CACHE" ]]; then
  ok "Template cached"
else
  echo "Downloading template to ${TEMPLATE_STORAGE}..."
  pveam download "${TEMPLATE_STORAGE}" "${TEMPLATE}"
  ok "Template downloaded"
fi

OSTEMPLATE="${TEMPLATE_STORAGE}:vztmpl/${TEMPLATE}"

# --------------------------
# STEP 2: Create or update CT
# --------------------------
step 2 "Ensuring container exists/configured"
DESIRED_NET0="name=eth0,bridge=${BRIDGE},ip=${IP_CIDR},gw=${GW}"

if ! ct_exists; then
  step 2 "Creating container ${CTID}"
  pct create "${CTID}" "${OSTEMPLATE}" \
    --hostname "${CT_HOSTNAME}" \
    --memory "${MEM_MB}" \
    --cores "${CORES}" \
    --rootfs "${STORAGE}:${DISK_GB}" \
    --net0 "${DESIRED_NET0}" \
    --unprivileged "${UNPRIVILEGED}" \
    --features "${FEATURES}" \
    --start 0
  ok "Container created"
else
  step 2 "Container exists — adjusting mutable settings"
  pct set "${CTID}" \
    --hostname "${CT_HOSTNAME}" \
    --memory "${MEM_MB}" \
    --cores "${CORES}" \
    --features "${FEATURES}" >/dev/null

  if [[ -n "${STARTUP}" ]]; then
    pct set "${CTID}" --startup "${STARTUP}" >/dev/null || warn "Could not set startup='${STARTUP}' (ignored)"
  fi

  pct set "${CTID}" --onboot "${ONBOOT}" >/dev/null || warn "Could not set onboot=${ONBOOT} (ignored)"

  CURRENT_NET0="$(pct config "${CTID}" | awk -F': ' '$1=="net0"{print $2}')"
  if [[ "${CURRENT_NET0}" != "${DESIRED_NET0}" ]]; then
    if ct_running; then
      warn "CT is running; not changing net0 live (avoids 'Address already assigned')."
      warn "If you changed IP/bridge: pct stop ${CTID} && rerun, or FORCE_RECREATE=1."
    else
      pct set "${CTID}" --net0 "${DESIRED_NET0}" >/dev/null
      ok "net0 updated"
    fi
  fi

  ok "Config ensured"
fi

# --------------------------
# STEP 3: Start CT
# --------------------------
step 3 "Starting container"
if ct_running; then
  ok "Container already running"
else
  pct start "${CTID}" >/dev/null 2>&1 || true
  ct_running && ok "Container running" || die "Container not running"
fi

# --------------------------
# STEP 4: Inject SSH key
# --------------------------
if [[ "$NO_SSHKEY" == "1" ]]; then
  step 4 "Injecting SSH key (skipped)"
  ok "SSH key injection skipped"
else
  step 4 "Injecting SSH key"
  PUBKEY="$(cat "$SSH_PUBKEY_FILE")"
  pct exec "${CTID}" -- bash -lc "set -euo pipefail
install -d -m 700 /root/.ssh
touch /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys
grep -qxF '$PUBKEY' /root/.ssh/authorized_keys || echo '$PUBKEY' >> /root/.ssh/authorized_keys
"
  ok "SSH key ready"
fi

# --------------------------
# STEP 5: Install toolchain inside CT
# --------------------------
if [[ "$NO_TOOLCHAIN" == "1" ]]; then
  step 5 "Installing toolchain inside container (skipped)"
  ok "Toolchain step skipped"
else
  step 5 "Installing toolchain inside container"
  pct exec "${CTID}" -- bash -lc '
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

apt-get update -y
apt-get install -y --no-install-recommends \
  ca-certificates curl unzip jq git openssh-server \
  python3 python3-venv python3-pip \
  ansible

if [[ ! -f /etc/profile.d/ralf-path.sh ]] || ! grep -q "export PATH=/usr/local/bin" /etc/profile.d/ralf-path.sh; then
  printf "%s\n" "export PATH=/usr/local/bin:/usr/bin:/bin:\$PATH" > /etc/profile.d/ralf-path.sh
  chmod 0644 /etc/profile.d/ralf-path.sh
fi

export PATH=/usr/local/bin:/usr/bin:/bin:$PATH

if ! command -v tofu >/dev/null 2>&1; then
  curl --proto "=https" --tlsv1.2 -fsSL https://get.opentofu.org/install-opentofu.sh -o /tmp/install-opentofu.sh
  chmod +x /tmp/install-opentofu.sh
  /tmp/install-opentofu.sh --install-method standalone --skip-verify
  rm -f /tmp/install-opentofu.sh
fi

ARCH=$(dpkg --print-architecture)
case "$ARCH" in
  amd64) TG_ARCH=amd64 ;;
  arm64) TG_ARCH=arm64 ;;
  *) echo "Unsupported arch: $ARCH" >&2; exit 1 ;;
esac

if ! command -v terragrunt >/dev/null 2>&1; then
  TG_VER=$(curl -fsSL https://api.github.com/repos/gruntwork-io/terragrunt/releases/latest | jq -r .tag_name)
  curl -fsSL -o /usr/local/bin/terragrunt "https://github.com/gruntwork-io/terragrunt/releases/download/${TG_VER}/terragrunt_linux_${TG_ARCH}"
  chmod 0755 /usr/local/bin/terragrunt
fi

command -v tofu >/dev/null
command -v terragrunt >/dev/null
command -v ansible >/dev/null
'
  ok "Toolchain installed"
fi

# --------------------------
# STEP 6: Base layout + repo checkout/update
# --------------------------
if [[ "$NO_GIT" == "1" ]]; then
  step 6 "Base layout + repo checkout (skipped)"
  ok "Repo step skipped"
else
  step 6 "Base layout + repo checkout"
  pct exec "${CTID}" -- bash -lc "
set -euo pipefail
export PATH=/usr/local/bin:/usr/bin:/bin:\$PATH

install -d -m 0755 '${RALF_BASE}'
install -d -m 0755 '${RALF_RUNTIME}'

if [[ ! -d '${RALF_REPO}/.git' ]]; then
  rm -rf '${RALF_REPO}'
  git clone '${RALF_GIT_URL}' '${RALF_REPO}'
else
  cd '${RALF_REPO}'
  git fetch --prune origin
  git checkout -f main
  git reset --hard origin/main
fi

echo \"RALF_BASE=${RALF_BASE}\"
echo \"RALF_REPO=${RALF_REPO}\"
echo \"RALF_RUNTIME=${RALF_RUNTIME}\"
"
  ok "Repo + runtime layout ready"
fi

# --------------------------
# STEP 7: Inject Proxmox API secrets (host -> CT)
# --------------------------
if [[ "$NO_SECRETS" == "1" ]]; then
  step 7 "Injecting Proxmox API secrets (skipped)"
  ok "Secrets injection skipped"
else
  step 7 "Injecting Proxmox API secrets (host -> container)"

  [[ -f "$HOST_PVE_ENV" ]] || die "Missing host secrets file: $HOST_PVE_ENV"

  CT_PVE_DIR="$(dirname "$CT_PVE_ENV")"
  pct exec "${CTID}" -- bash -lc "set -euo pipefail
install -d -m 700 '${CT_PVE_DIR}'
"

  PVE_B64="$(base64 -w0 "$HOST_PVE_ENV")"
  pct exec "${CTID}" -- bash -lc "set -euo pipefail
echo '${PVE_B64}' | base64 -d > '${CT_PVE_ENV}'
chmod 600 '${CT_PVE_ENV}'
"
  ok "pve.env injected to ${CT_PVE_ENV}"
fi

# --------------------------
# STEP 8: Run bootstrap runner (ONCE)
# --------------------------
if [[ "$NO_RUNNER" == "1" ]]; then
  step 8 "Running bootstrap runner (skipped)"
  ok "Runner skipped"
else
  step 8 "Running bootstrap runner"
  pct exec "${CTID}" -- bash -lc "
set -euo pipefail
export PATH=/usr/local/bin:/usr/bin:/bin:\$PATH
export RALF_BASE='${RALF_BASE}'
export RALF_REPO='${RALF_REPO}'
export RALF_RUNTIME='${RALF_RUNTIME}'

cd '${RALF_REPO}'
chmod +x bootstrap/runner.sh

export RUN_STACKS=1
export AUTO_APPLY='${AUTO_APPLY}'
export START_AT='${START_AT}'
export ONLY_STACKS='${ONLY_STACKS}'

bash bootstrap/runner.sh
"
  ok "Runner finished"
fi

# --------------------------
# STEP 9: Checks (NO runner call here)
# --------------------------
step 9 "Checks"
echo "  pct exec ${CTID} -- bash -lc 'export PATH=/usr/local/bin:/usr/bin:/bin; tofu version; terragrunt --version | head -n 1; ansible --version | head -n 2'"
echo "  pct exec ${CTID} -- bash -lc 'cd ${RALF_REPO} && git log -1 --oneline'"
echo
ok "Done."
