#!/usr/bin/env bash
set -euo pipefail

### ============================================================
### RALF DEPLOY – Master-Script fuer das gesamte Homelab
### ============================================================
###
### Verwendung:
###   export RALF_SECRETS_FILE="/pfad/zu/secrets.env"
###   bash ralf-deploy.sh [--phase N] [--from-phase N] [--dry-run] [--skip-preflight]
###
### Voraussetzungen:
###   - Ausfuehrung auf dem Proxmox-Host (pct, pveam verfuegbar)
###   - Secrets in $RALF_SECRETS_FILE oder als Umgebungsvariablen
###   - Netzwerk-Baseline (OPNsense) funktional
###
### Phasen:
###   1 = Core Bootstrap (Semaphore, PostgreSQL, Gitea)
###   2 = Sicherheit (Vaultwarden)
###   3 = Mail (Maddy)
###   4 = Reverse Proxy (Caddy via OPNsense API)
###   5 = Observability (Prometheus, Grafana, Loki)
###   6 = Plattform (NetBox, Snipe-IT)
###   7 = Automatisierung (n8n)
###   8 = Kommunikation (Matrix/Synapse, Element)
###   9 = Abschluss (Smoke Tests, Report)
###
### ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/ralf-deploy.log"
STATE_FILE="${SCRIPT_DIR}/.ralf-deploy-state"

### =========================
### Defaults
### =========================

RUN_PHASE=""
FROM_PHASE="1"
DRY_RUN="false"
SKIP_PREFLIGHT="false"

### =========================
### Argument parsing
### =========================

while [[ $# -gt 0 ]]; do
  case "$1" in
    --phase)     RUN_PHASE="$2"; shift 2 ;;
    --from-phase) FROM_PHASE="$2"; shift 2 ;;
    --dry-run)   DRY_RUN="true"; shift ;;
    --skip-preflight) SKIP_PREFLIGHT="true"; shift ;;
    -h|--help)
      head -30 "$0" | grep "^###" | sed 's/^### //'
      exit 0
      ;;
    *) echo "Unbekannter Parameter: $1"; exit 1 ;;
  esac
done

### =========================
### Helpers
### =========================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()      { echo -e "${BLUE}[RALF]${NC} $*" | tee -a "$LOG_FILE"; }
log_ok()   { echo -e "${GREEN}[  OK]${NC} $*" | tee -a "$LOG_FILE"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*" | tee -a "$LOG_FILE"; }
log_err()  { echo -e "${RED}[ ERR]${NC} $*" | tee -a "$LOG_FILE"; }
log_phase(){ echo -e "\n${BLUE}==============================${NC}" | tee -a "$LOG_FILE"
             echo -e "${BLUE}  PHASE $1 – $2${NC}" | tee -a "$LOG_FILE"
             echo -e "${BLUE}==============================${NC}\n" | tee -a "$LOG_FILE"; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || { log_err "Befehl nicht gefunden: $1"; return 1; }
}

need_var() {
  local var_name="$1"
  if [[ -z "${!var_name:-}" ]]; then
    log_err "Variable nicht gesetzt: $var_name"
    return 1
  fi
}

save_state() {
  echo "$1" > "$STATE_FILE"
}

load_state() {
  if [[ -f "$STATE_FILE" ]]; then
    cat "$STATE_FILE"
  else
    echo "0"
  fi
}

should_run_phase() {
  local phase="$1"
  if [[ -n "$RUN_PHASE" ]]; then
    [[ "$phase" == "$RUN_PHASE" ]]
  else
    [[ "$phase" -ge "$FROM_PHASE" ]]
  fi
}

run_or_dry() {
  if [[ "$DRY_RUN" == "true" ]]; then
    log_warn "[DRY-RUN] Wuerde ausfuehren: $*"
  else
    "$@"
  fi
}

pct_running() {
  local ctid="$1"
  pct status "$ctid" 2>/dev/null | grep -q "running"
}

wait_for_port() {
  local ip="$1" port="$2" timeout="${3:-30}"
  log "Warte auf ${ip}:${port} (max ${timeout}s)..."
  for i in $(seq 1 "$timeout"); do
    if bash -c "echo >/dev/tcp/${ip}/${port}" 2>/dev/null; then
      log_ok "${ip}:${port} erreichbar"
      return 0
    fi
    sleep 1
  done
  log_err "${ip}:${port} nicht erreichbar nach ${timeout}s"
  return 1
}

### =========================
### Secrets laden
### =========================

if [[ -n "${RALF_SECRETS_FILE:-}" && -f "$RALF_SECRETS_FILE" ]]; then
  log "Lade Secrets aus: $RALF_SECRETS_FILE"
  # shellcheck source=/dev/null
  source "$RALF_SECRETS_FILE"
else
  log_warn "Kein RALF_SECRETS_FILE angegeben – erwarte Secrets als Umgebungsvariablen"
fi

### =========================
### PREFLIGHT CHECK
### =========================

preflight() {
  log_phase "0" "Preflight Check"
  local errors=0

  # Befehle pruefen
  for cmd in pct pveam pvesm curl jq git bash ssh-keygen; do
    if need_cmd "$cmd"; then
      log_ok "$cmd verfuegbar"
    else
      ((errors++))
    fi
  done

  # Netzwerk pruefen
  if ping -c1 -W3 10.10.0.1 >/dev/null 2>&1; then
    log_ok "Gateway 10.10.0.1 erreichbar"
  else
    log_err "Gateway 10.10.0.1 nicht erreichbar"
    ((errors++))
  fi

  if ping -c1 -W3 10.10.10.10 >/dev/null 2>&1; then
    log_ok "Proxmox 10.10.10.10 erreichbar"
  else
    log_warn "Proxmox 10.10.10.10 nicht erreichbar (ok wenn wir AUF Proxmox laufen)"
  fi

  # Secrets pruefen (Phase 1 Minimum)
  for var in SEMAPHORE_PASS PG_SUPERUSER_PASS SEMAPHORE_DB_PASS GITEA_DB_PASS; do
    if need_var "$var"; then
      log_ok "$var gesetzt"
    else
      ((errors++))
    fi
  done

  # Ubuntu Template pruefen
  local tpl="${TPL_STORAGE:-local}:vztmpl/${TPL_NAME:-ubuntu-24.04-standard_24.04-2_amd64.tar.zst}"
  if pveam list "${TPL_STORAGE:-local}" 2>/dev/null | awk '{print $1}' | grep -qx "$tpl"; then
    log_ok "Ubuntu Template vorhanden"
  else
    log_warn "Ubuntu Template nicht gefunden – wird beim Bootstrap heruntergeladen"
  fi

  # Ansible pruefen (optional fuer spaetere Phasen)
  if command -v ansible-playbook >/dev/null 2>&1; then
    log_ok "Ansible verfuegbar: $(ansible-playbook --version | head -1)"
  else
    log_warn "Ansible nicht installiert – wird fuer Phasen 2+ benoetigt"
  fi

  # OpenTofu pruefen
  if command -v tofu >/dev/null 2>&1; then
    log_ok "OpenTofu verfuegbar: $(tofu version | head -1)"
  else
    log_warn "OpenTofu nicht installiert – wird fuer Terragrunt benoetigt"
  fi

  # Terragrunt pruefen
  if command -v terragrunt >/dev/null 2>&1; then
    log_ok "Terragrunt verfuegbar: $(terragrunt --version | head -1)"
  else
    log_warn "Terragrunt nicht installiert – wird fuer Phase 9 benoetigt"
  fi

  if [[ "$errors" -gt 0 ]]; then
    log_err "Preflight fehlgeschlagen: $errors Fehler"
    log_err "Behebe die Fehler und starte erneut."
    exit 1
  fi

  log_ok "Preflight bestanden"
}

### ============================================================
### PHASE 1 – Core Bootstrap
### ============================================================

phase_1() {
  log_phase "1" "Core Bootstrap (Semaphore, PostgreSQL, Gitea)"

  # --- 1a: Semaphore ---
  log "--- 1a: Semaphore deployen ---"
  if pct_running 10015; then
    log_ok "Semaphore CT 10015 laeuft bereits"
  else
    run_or_dry bash "${SCRIPT_DIR}/bootstrap/create-and-fill-runner.sh"
  fi
  run_or_dry wait_for_port 10.10.100.15 3000 60
  log_ok "Semaphore bereit"

  # --- 1b: PostgreSQL ---
  log "--- 1b: PostgreSQL deployen ---"
  if pct_running 2010; then
    log_ok "PostgreSQL CT 2010 laeuft bereits"
  else
    run_or_dry bash "${SCRIPT_DIR}/bootstrap/create-postgresql.sh"
  fi
  run_or_dry wait_for_port 10.10.20.10 5432 60
  log_ok "PostgreSQL bereit"

  # --- 1c: Datenbank-Provisioning ---
  log "--- 1c: Datenbanken + User anlegen ---"
  if command -v ansible-playbook >/dev/null 2>&1; then
    run_or_dry ansible-playbook \
      -i "${SCRIPT_DIR}/iac/ansible/inventory/hosts.yml" \
      "${SCRIPT_DIR}/iac/ansible/playbooks/provision-databases.yml" \
      --extra-vars "semaphore_db_pass=${SEMAPHORE_DB_PASS} gitea_db_pass=${GITEA_DB_PASS}"
  else
    log_warn "Ansible nicht verfuegbar – Datenbank-Provisioning manuell durchfuehren:"
    log_warn "  psql -h 10.10.20.10 -U postgres"
    log_warn "  CREATE ROLE semaphore WITH LOGIN PASSWORD '...';"
    log_warn "  CREATE DATABASE semaphore OWNER semaphore;"
    log_warn "  CREATE ROLE gitea WITH LOGIN PASSWORD '...';"
    log_warn "  CREATE DATABASE gitea OWNER gitea;"
  fi
  log_ok "Datenbank-Provisioning abgeschlossen"

  # --- 1d: Gitea ---
  log "--- 1d: Gitea deployen ---"
  if pct_running 2012; then
    log_ok "Gitea CT 2012 laeuft bereits"
  else
    run_or_dry bash "${SCRIPT_DIR}/bootstrap/create-gitea.sh"
  fi
  run_or_dry wait_for_port 10.10.20.12 3000 60
  log_ok "Gitea bereit"

  # --- 1e: Smoke Tests ---
  log "--- 1e: Smoke Tests Phase 1 ---"
  run_or_dry bash "${SCRIPT_DIR}/tests/bootstrap/smoke.sh" || log_warn "Bootstrap Smoke Test fehlgeschlagen"
  run_or_dry bash "${SCRIPT_DIR}/tests/postgresql/smoke.sh" || log_warn "PostgreSQL Smoke Test fehlgeschlagen"
  run_or_dry bash "${SCRIPT_DIR}/tests/gitea/smoke.sh" || log_warn "Gitea Smoke Test fehlgeschlagen"

  save_state "1"
  log_ok "Phase 1 abgeschlossen"
}

### ============================================================
### PHASE 2 – Sicherheit (Vaultwarden)
### ============================================================

phase_2() {
  log_phase "2" "Sicherheit (Vaultwarden)"

  need_var "VAULTWARDEN_DB_PASS"
  need_var "VAULTWARDEN_ADMIN_TOKEN"

  # Container erstellen
  if pct_running 3010; then
    log_ok "Vaultwarden CT 3010 laeuft bereits"
  else
    if [[ -f "${SCRIPT_DIR}/bootstrap/create-vaultwarden.sh" ]]; then
      run_or_dry bash "${SCRIPT_DIR}/bootstrap/create-vaultwarden.sh"
    else
      log_err "bootstrap/create-vaultwarden.sh existiert noch nicht"
      log_warn "Erstelle es gemaess plans/roadmap/02-sicherheit.md"
      return 1
    fi
  fi

  # DB-Provisioning
  if command -v ansible-playbook >/dev/null 2>&1; then
    run_or_dry ansible-playbook \
      -i "${SCRIPT_DIR}/iac/ansible/inventory/hosts.yml" \
      "${SCRIPT_DIR}/iac/ansible/playbooks/provision-databases.yml" \
      --extra-vars "semaphore_db_pass=${SEMAPHORE_DB_PASS} gitea_db_pass=${GITEA_DB_PASS} vaultwarden_db_pass=${VAULTWARDEN_DB_PASS}"
  fi

  # Ansible Deploy
  if [[ -f "${SCRIPT_DIR}/iac/ansible/playbooks/deploy-vaultwarden.yml" ]]; then
    run_or_dry ansible-playbook \
      -i "${SCRIPT_DIR}/iac/ansible/inventory/hosts.yml" \
      "${SCRIPT_DIR}/iac/ansible/playbooks/deploy-vaultwarden.yml" \
      --extra-vars "vaultwarden_db_pass=${VAULTWARDEN_DB_PASS} vaultwarden_admin_token=${VAULTWARDEN_ADMIN_TOKEN}"
  else
    log_warn "Playbook deploy-vaultwarden.yml existiert noch nicht"
  fi

  run_or_dry wait_for_port 10.10.30.10 8080 60 || true

  if [[ -f "${SCRIPT_DIR}/tests/vaultwarden/smoke.sh" ]]; then
    run_or_dry bash "${SCRIPT_DIR}/tests/vaultwarden/smoke.sh" || log_warn "Vaultwarden Smoke Test fehlgeschlagen"
  fi

  save_state "2"
  log_ok "Phase 2 abgeschlossen"
}

### ============================================================
### PHASE 3 – Mail (Maddy)
### ============================================================

phase_3() {
  log_phase "3" "Mail-Server (Maddy)"

  need_var "KOLJA_MAIL_PASS"
  need_var "RALF_MAIL_PASS"

  if pct_running 4010; then
    log_ok "Mail CT 4010 laeuft bereits"
  else
    if [[ -f "${SCRIPT_DIR}/bootstrap/create-mail.sh" ]]; then
      run_or_dry bash "${SCRIPT_DIR}/bootstrap/create-mail.sh"
    else
      log_err "bootstrap/create-mail.sh existiert noch nicht"
      return 1
    fi
  fi

  if [[ -f "${SCRIPT_DIR}/iac/ansible/playbooks/deploy-mail.yml" ]]; then
    run_or_dry ansible-playbook \
      -i "${SCRIPT_DIR}/iac/ansible/inventory/hosts.yml" \
      "${SCRIPT_DIR}/iac/ansible/playbooks/deploy-mail.yml" \
      --extra-vars "kolja_mail_pass=${KOLJA_MAIL_PASS} ralf_mail_pass=${RALF_MAIL_PASS}"
  else
    log_warn "Playbook deploy-mail.yml existiert noch nicht"
  fi

  run_or_dry wait_for_port 10.10.40.10 25 60 || true

  if [[ -f "${SCRIPT_DIR}/tests/mail/smoke.sh" ]]; then
    run_or_dry bash "${SCRIPT_DIR}/tests/mail/smoke.sh" || log_warn "Mail Smoke Test fehlgeschlagen"
  fi

  save_state "3"
  log_ok "Phase 3 abgeschlossen"
}

### ============================================================
### PHASE 4 – Reverse Proxy (Caddy via OPNsense API)
### ============================================================

phase_4() {
  log_phase "4" "Reverse Proxy (Caddy auf OPNsense)"

  need_var "OPNSENSE_API_KEY"
  need_var "OPNSENSE_API_SECRET"

  local OPN_URL="${OPNSENSE_URL:-https://10.10.0.1:8443}"

  # Caddy-Status pruefen
  log "Pruefe Caddy-Status auf OPNsense..."
  local status
  status=$(curl -sk -u "${OPNSENSE_API_KEY}:${OPNSENSE_API_SECRET}" \
    "${OPN_URL}/api/caddy/service/status" 2>/dev/null || echo '{"status":"error"}')

  if echo "$status" | jq -e '.status' >/dev/null 2>&1; then
    log_ok "Caddy API erreichbar"
  else
    log_err "Caddy API nicht erreichbar – ist os-caddy installiert?"
    return 1
  fi

  # Ansible Playbook oder direkte API-Calls
  if [[ -f "${SCRIPT_DIR}/iac/ansible/playbooks/configure-caddy.yml" ]]; then
    run_or_dry ansible-playbook \
      "${SCRIPT_DIR}/iac/ansible/playbooks/configure-caddy.yml" \
      --extra-vars "opnsense_api_key=${OPNSENSE_API_KEY} opnsense_api_secret=${OPNSENSE_API_SECRET}"
  else
    log_warn "Playbook configure-caddy.yml existiert noch nicht"
    log "Konfiguriere Caddy direkt via API..."

    local -a SERVICES=(
      "gitea.homelab.lan|10.10.20.12|3000|Gitea"
      "semaphore.homelab.lan|10.10.100.15|3000|Semaphore"
      "vault.homelab.lan|10.10.30.10|8080|Vaultwarden"
    )

    for svc in "${SERVICES[@]}"; do
      IFS='|' read -r domain upstream port desc <<< "$svc"
      log "Konfiguriere: $domain → $upstream:$port"

      # Domain erstellen
      local result
      result=$(curl -sk -u "${OPNSENSE_API_KEY}:${OPNSENSE_API_SECRET}" \
        -X POST "${OPN_URL}/api/caddy/reverse_proxy/add_reverse_proxy" \
        -H "Content-Type: application/json" \
        -d "{\"reverse\":{\"enabled\":\"1\",\"FromDomain\":\"${domain}\",\"FromPort\":\"443\",\"Description\":\"RALF – ${desc}\"}}" \
        2>/dev/null || echo '{}')

      local uuid
      uuid=$(echo "$result" | jq -r '.uuid // empty')
      if [[ -n "$uuid" ]]; then
        # Handle erstellen
        curl -sk -u "${OPNSENSE_API_KEY}:${OPNSENSE_API_SECRET}" \
          -X POST "${OPN_URL}/api/caddy/reverse_proxy/add_handle" \
          -H "Content-Type: application/json" \
          -d "{\"handle\":{\"enabled\":\"1\",\"reverse\":\"${uuid}\",\"ToDomain\":\"${upstream}\",\"ToPort\":\"${port}\",\"Description\":\"${desc} Backend\"}}" \
          >/dev/null 2>&1
        log_ok "$domain konfiguriert"
      else
        log_warn "$domain uebersprungen (existiert bereits oder Fehler)"
      fi
    done

    # Anwenden
    curl -sk -u "${OPNSENSE_API_KEY}:${OPNSENSE_API_SECRET}" \
      -X POST "${OPN_URL}/api/caddy/service/reconfigure" >/dev/null 2>&1
    log_ok "Caddy-Konfiguration angewendet"
  fi

  save_state "4"
  log_ok "Phase 4 abgeschlossen"
}

### ============================================================
### PHASE 5 – Observability (Prometheus, Grafana, Loki)
### ============================================================

phase_5() {
  log_phase "5" "Observability (Prometheus, Grafana, Loki)"

  local -A PHASE5_CTS=(
    [8010]="prometheus|create-prometheus.sh|deploy-prometheus.yml|10.10.80.10|9090"
    [8014]="loki|create-loki.sh|deploy-loki.yml|10.10.80.14|3100"
    [8012]="grafana|create-grafana.sh|deploy-grafana.yml|10.10.80.12|3000"
  )

  for ctid in 8010 8014 8012; do
    IFS='|' read -r name bootstrap playbook ip port <<< "${PHASE5_CTS[$ctid]}"
    log "--- Deploye $name (CT $ctid) ---"

    if pct_running "$ctid"; then
      log_ok "$name CT $ctid laeuft bereits"
    elif [[ -f "${SCRIPT_DIR}/bootstrap/${bootstrap}" ]]; then
      run_or_dry bash "${SCRIPT_DIR}/bootstrap/${bootstrap}"
    else
      log_warn "bootstrap/${bootstrap} existiert noch nicht – ueberspringe $name"
      continue
    fi

    if [[ -f "${SCRIPT_DIR}/iac/ansible/playbooks/${playbook}" ]]; then
      run_or_dry ansible-playbook \
        -i "${SCRIPT_DIR}/iac/ansible/inventory/hosts.yml" \
        "${SCRIPT_DIR}/iac/ansible/playbooks/${playbook}"
    else
      log_warn "Playbook ${playbook} existiert noch nicht"
    fi

    run_or_dry wait_for_port "$ip" "$port" 60 || log_warn "$name nicht erreichbar"
  done

  save_state "5"
  log_ok "Phase 5 abgeschlossen"
}

### ============================================================
### PHASE 6 – Plattform (NetBox, Snipe-IT)
### ============================================================

phase_6() {
  log_phase "6" "Plattform (NetBox, Snipe-IT)"

  # NetBox
  log "--- NetBox deployen ---"
  if pct_running 4012; then
    log_ok "NetBox CT 4012 laeuft bereits"
  elif [[ -f "${SCRIPT_DIR}/bootstrap/create-netbox.sh" ]]; then
    run_or_dry bash "${SCRIPT_DIR}/bootstrap/create-netbox.sh"
  else
    log_warn "bootstrap/create-netbox.sh existiert noch nicht"
  fi

  if [[ -f "${SCRIPT_DIR}/iac/ansible/playbooks/deploy-netbox.yml" ]]; then
    run_or_dry ansible-playbook \
      -i "${SCRIPT_DIR}/iac/ansible/inventory/hosts.yml" \
      "${SCRIPT_DIR}/iac/ansible/playbooks/deploy-netbox.yml" \
      --extra-vars "netbox_db_pass=${NETBOX_DB_PASS:-} netbox_secret_key=${NETBOX_SECRET_KEY:-}"
  else
    log_warn "Playbook deploy-netbox.yml existiert noch nicht"
  fi

  # Snipe-IT
  log "--- Snipe-IT deployen ---"
  if pct_running 4014; then
    log_ok "Snipe-IT CT 4014 laeuft bereits"
  elif [[ -f "${SCRIPT_DIR}/bootstrap/create-snipeit.sh" ]]; then
    run_or_dry bash "${SCRIPT_DIR}/bootstrap/create-snipeit.sh"
  else
    log_warn "bootstrap/create-snipeit.sh existiert noch nicht"
  fi

  if [[ -f "${SCRIPT_DIR}/iac/ansible/playbooks/deploy-snipeit.yml" ]]; then
    run_or_dry ansible-playbook \
      -i "${SCRIPT_DIR}/iac/ansible/inventory/hosts.yml" \
      "${SCRIPT_DIR}/iac/ansible/playbooks/deploy-snipeit.yml" \
      --extra-vars "snipeit_db_pass=${SNIPEIT_DB_PASS:-}"
  else
    log_warn "Playbook deploy-snipeit.yml existiert noch nicht"
  fi

  save_state "6"
  log_ok "Phase 6 abgeschlossen"
}

### ============================================================
### PHASE 7 – Automatisierung (n8n)
### ============================================================

phase_7() {
  log_phase "7" "Automatisierung (n8n)"

  need_var "N8N_DB_PASS"

  if pct_running 10020; then
    log_ok "n8n CT 10020 laeuft bereits"
  elif [[ -f "${SCRIPT_DIR}/bootstrap/create-n8n.sh" ]]; then
    run_or_dry bash "${SCRIPT_DIR}/bootstrap/create-n8n.sh"
  else
    log_warn "bootstrap/create-n8n.sh existiert noch nicht"
  fi

  # DB-Provisioning fuer n8n
  if command -v ansible-playbook >/dev/null 2>&1 && [[ -f "${SCRIPT_DIR}/iac/ansible/playbooks/provision-databases.yml" ]]; then
    run_or_dry ansible-playbook \
      -i "${SCRIPT_DIR}/iac/ansible/inventory/hosts.yml" \
      "${SCRIPT_DIR}/iac/ansible/playbooks/provision-databases.yml" \
      --extra-vars "semaphore_db_pass=${SEMAPHORE_DB_PASS} gitea_db_pass=${GITEA_DB_PASS} n8n_db_pass=${N8N_DB_PASS}"
  fi

  if [[ -f "${SCRIPT_DIR}/iac/ansible/playbooks/deploy-n8n.yml" ]]; then
    run_or_dry ansible-playbook \
      -i "${SCRIPT_DIR}/iac/ansible/inventory/hosts.yml" \
      "${SCRIPT_DIR}/iac/ansible/playbooks/deploy-n8n.yml" \
      --extra-vars "n8n_db_pass=${N8N_DB_PASS}"
  else
    log_warn "Playbook deploy-n8n.yml existiert noch nicht"
  fi

  run_or_dry wait_for_port 10.10.100.20 5678 60 || true

  save_state "7"
  log_ok "Phase 7 abgeschlossen"
}

### ============================================================
### PHASE 8 – Kommunikation (Matrix/Synapse, Element)
### ============================================================

phase_8() {
  log_phase "8" "Kommunikation (Matrix/Synapse, Element)"

  need_var "SYNAPSE_DB_PASS"
  need_var "SYNAPSE_REGISTRATION_SECRET"

  # Synapse
  log "--- Synapse deployen ---"
  if pct_running 4030; then
    log_ok "Synapse CT 4030 laeuft bereits"
  elif [[ -f "${SCRIPT_DIR}/bootstrap/create-synapse.sh" ]]; then
    run_or_dry bash "${SCRIPT_DIR}/bootstrap/create-synapse.sh"
  else
    log_warn "bootstrap/create-synapse.sh existiert noch nicht"
  fi

  if [[ -f "${SCRIPT_DIR}/iac/ansible/playbooks/deploy-synapse.yml" ]]; then
    run_or_dry ansible-playbook \
      -i "${SCRIPT_DIR}/iac/ansible/inventory/hosts.yml" \
      "${SCRIPT_DIR}/iac/ansible/playbooks/deploy-synapse.yml" \
      --extra-vars "synapse_db_pass=${SYNAPSE_DB_PASS} synapse_registration_secret=${SYNAPSE_REGISTRATION_SECRET}"
  else
    log_warn "Playbook deploy-synapse.yml existiert noch nicht"
  fi

  run_or_dry wait_for_port 10.10.40.30 8008 60 || true

  # Element
  log "--- Element deployen ---"
  if pct_running 4032; then
    log_ok "Element CT 4032 laeuft bereits"
  elif [[ -f "${SCRIPT_DIR}/bootstrap/create-element.sh" ]]; then
    run_or_dry bash "${SCRIPT_DIR}/bootstrap/create-element.sh"
  else
    log_warn "bootstrap/create-element.sh existiert noch nicht"
  fi

  if [[ -f "${SCRIPT_DIR}/iac/ansible/playbooks/deploy-element.yml" ]]; then
    run_or_dry ansible-playbook \
      -i "${SCRIPT_DIR}/iac/ansible/inventory/hosts.yml" \
      "${SCRIPT_DIR}/iac/ansible/playbooks/deploy-element.yml"
  else
    log_warn "Playbook deploy-element.yml existiert noch nicht"
  fi

  run_or_dry wait_for_port 10.10.40.32 8080 60 || true

  save_state "8"
  log_ok "Phase 8 abgeschlossen"
}

### ============================================================
### PHASE 9 – Abschluss (Smoke Tests + Report)
### ============================================================

phase_9() {
  log_phase "9" "Abschluss (Smoke Tests + Report)"

  log "--- Smoke Tests ---"
  local total=0 passed=0 failed=0 skipped=0

  local -a SMOKE_TESTS=(
    "tests/bootstrap/smoke.sh"
    "tests/postgresql/smoke.sh"
    "tests/gitea/smoke.sh"
    "tests/vaultwarden/smoke.sh"
    "tests/mail/smoke.sh"
    "tests/caddy/smoke.sh"
    "tests/prometheus/smoke.sh"
    "tests/loki/smoke.sh"
    "tests/grafana/smoke.sh"
    "tests/netbox/smoke.sh"
    "tests/snipeit/smoke.sh"
    "tests/n8n/smoke.sh"
    "tests/synapse/smoke.sh"
    "tests/element/smoke.sh"
  )

  for test in "${SMOKE_TESTS[@]}"; do
    ((total++))
    if [[ ! -f "${SCRIPT_DIR}/${test}" ]]; then
      log_warn "SKIP: $test (nicht vorhanden)"
      ((skipped++))
      continue
    fi
    if run_or_dry bash "${SCRIPT_DIR}/${test}"; then
      log_ok "PASS: $test"
      ((passed++))
    else
      log_err "FAIL: $test"
      ((failed++))
    fi
  done

  # Report
  echo ""
  echo "============================================"
  echo "  RALF DEPLOYMENT REPORT"
  echo "============================================"
  echo ""
  echo "  Datum:      $(date '+%Y-%m-%d %H:%M:%S')"
  echo "  Log:        $LOG_FILE"
  echo ""
  echo "  Smoke Tests: $total total"
  echo "    Bestanden: $passed"
  echo "    Fehlgeschlagen: $failed"
  echo "    Uebersprungen: $skipped"
  echo ""

  # Container-Status
  echo "  Container-Status:"
  local -a ALL_CTS=(10015 2010 2012 3010 4010 4012 4014 8010 8012 8014 10020 4030 4032)
  local -a ALL_NAMES=("Semaphore" "PostgreSQL" "Gitea" "Vaultwarden" "Mail" "NetBox" "Snipe-IT" "Prometheus" "Grafana" "Loki" "n8n" "Synapse" "Element")

  for i in "${!ALL_CTS[@]}"; do
    local ct="${ALL_CTS[$i]}"
    local name="${ALL_NAMES[$i]}"
    if pct_running "$ct" 2>/dev/null; then
      echo "    [ONLINE]  CT $ct – $name"
    elif pct status "$ct" >/dev/null 2>&1; then
      echo "    [STOPPED] CT $ct – $name"
    else
      echo "    [ABSENT]  CT $ct – $name"
    fi
  done

  echo ""
  echo "============================================"

  if [[ "$failed" -gt 0 ]]; then
    log_err "Deployment mit $failed fehlgeschlagenen Tests abgeschlossen"
  else
    log_ok "RALF Deployment erfolgreich abgeschlossen!"
  fi

  save_state "9"
}

### ============================================================
### MAIN
### ============================================================

main() {
  echo ""
  echo "  ____      _    _     _____ "
  echo " |  _ \\    / \\  | |   |  ___|"
  echo " | |_) |  / _ \\ | |   | |_   "
  echo " |  _ <  / ___ \\| |___|  _|  "
  echo " |_| \\_\\/_/   \\_\\_____|_|    "
  echo ""
  echo " Homelab Deployment – $(date '+%Y-%m-%d %H:%M')"
  echo ""

  # Preflight
  if [[ "$SKIP_PREFLIGHT" != "true" ]]; then
    preflight
  fi

  # Phasen ausfuehren
  for phase in 1 2 3 4 5 6 7 8 9; do
    if should_run_phase "$phase"; then
      "phase_${phase}" || {
        log_err "Phase $phase fehlgeschlagen!"
        log "Neustart moeglich mit: bash ralf-deploy.sh --from-phase $phase"
        exit 1
      }
    else
      log "Phase $phase uebersprungen"
    fi
  done
}

main "$@"
