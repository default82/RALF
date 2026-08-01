#!/usr/bin/env bash

set -Eeuo pipefail

readonly CONTAINER_NAME="ralf-standalone"
readonly TEMPLATE_PATTERN='ubuntu-26\.04-standard'
readonly DEFAULT_CORES=4
readonly DEFAULT_MEMORY_MIB=12288
readonly DEFAULT_SWAP_MIB=4096
readonly DEFAULT_DISK_GIB=40
readonly LXC_FEATURES='nesting=1'

MODE=""
VMID=""
STORAGE=""
BRIDGE=""
CORES="$DEFAULT_CORES"
MEMORY_MIB="$DEFAULT_MEMORY_MIB"
SWAP_MIB="$DEFAULT_SWAP_MIB"
DISK_GIB="$DEFAULT_DISK_GIB"
TEMPLATE=""
PCT_CREATE_ATTEMPTED=0

fail() {
  printf 'Fehler: %s\n' "$*" >&2
  if [[ $MODE == apply ]]; then
    if ((PCT_CREATE_ATTEMPTED == 0)); then
      printf 'Container erstellt: nein; kein pct create wurde ausgeführt.\n' >&2
      printf '  VMID: %s\n' "${VMID:-nicht ermittelt}" >&2
      printf '  Zustand: nicht gestartet; keine Infrastrukturmutation erfolgt.\n' >&2
      printf '  Nächster manueller Schritt: Fehler beheben und den Apply-Plan erneut prüfen.\n' >&2
    else
      printf 'Container erstellt: unbekannt; ein Fehler trat nach dem pct create-Aufruf auf.\n' >&2
      printf '  VMID: %s\n  Zustand: nicht sicher validiert\n  Rollback: nicht automatisch ausgeführt.\n' "$VMID" >&2
    fi
  fi
  exit 1
}

usage() {
  cat >&2 <<'EOF'
Aufruf:
  ralf-standalone-bootstrap.sh (--plan|--check|--apply) [OPTIONEN]

Modi:
  --plan          sicheren Konfigurationsplan ausgeben (read-only)
  --check         Alias für --plan
  --apply         nach erneutem Preflight genau einen LXC erstellen

Optionen:
  --vmid ID       VMID; Standard: nächste freie Proxmox-VMID
  --storage NAME  Ziel-Storage; Standard: genau ein geeigneter Storage
  --bridge NAME   Netzwerk-Bridge; Standard: genau eine geeignete Bridge
  --cores N       CPU-Kerne; Standard: 4
  --memory MIB    Arbeitsspeicher in MiB; Standard: 12288 (12 GiB)
  --swap MIB      Swap in MiB; Standard: 4096 (4 GiB)
  --disk GIB      Root-Disk in GiB; Standard: 40
  --help          diese Hilfe anzeigen
EOF
  exit 2
}

fail_mode_conflict() {
  fail "Widersprüchliche Ausführungsmodi: --${1} und --${2} dürfen nicht gemeinsam verwendet werden."
}

select_mode() {
  local requested=$1
  if [[ -n $MODE && $MODE != "$requested" ]]; then
    fail_mode_conflict "$MODE" "$requested"
  fi
  MODE=$requested
}

check_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Benötigter Befehl fehlt: $1"
}

require_value() {
  local option=$1
  [[ $# -ge 2 && -n ${2:-} ]] || fail "Fehlender Wert für ${option}."
}

validate_positive_integer() {
  local option=$1
  local value=$2
  [[ $value =~ ^[0-9]+$ && $value -gt 0 ]] ||
    fail "Ungültiger Wert für ${option}: ${value}. Erwartet wird eine positive Ganzzahl."
}

validate_non_negative_integer() {
  local option=$1
  local value=$2
  [[ $value =~ ^[0-9]+$ ]] ||
    fail "Ungültiger Wert für ${option}: ${value}. Erwartet wird eine nichtnegative Ganzzahl."
}

parse_args() {
  while (($#)); do
    case $1 in
      --plan) select_mode plan; shift ;;
      --check) select_mode plan; shift ;;
      --apply) select_mode apply; shift ;;
      --vmid|--storage|--bridge|--cores|--memory|--swap|--disk)
        local option=$1
        shift
        require_value "$option" "${1:-}"
        case $option in
          --vmid) VMID=$1 ;;
          --storage) STORAGE=$1 ;;
          --bridge) BRIDGE=$1 ;;
          --cores) CORES=$1 ;;
          --memory) MEMORY_MIB=$1 ;;
          --swap) SWAP_MIB=$1 ;;
          --disk) DISK_GIB=$1 ;;
        esac
        shift
        ;;
      --help) usage ;;
      *) fail "Unbekannte Option: $1" ;;
    esac
  done
  [[ -n $MODE ]] || MODE=plan
}

resources_contain_vmid() {
  local resources
  resources=$(pvesh get /cluster/resources --type vm --output-format json) ||
    fail "Die belegten Proxmox-VMIDs konnten nicht gelesen werden."
  grep -Eq '"vmid"[[:space:]]*:[[:space:]]*'"$1"'([,}])' <<<"$resources"
}

name_is_in_use() {
  local containers
  containers=$(pct list) || fail "Die vorhandenen LXC-Container konnten nicht gelesen werden."
  awk -v name="$CONTAINER_NAME" 'NR > 1 && $NF == name { found = 1 } END { exit !found }' <<<"$containers"
}

resolve_vmid() {
  local nextid
  if [[ -z $VMID ]]; then
    nextid=$(pvesh get /cluster/nextid | tr -d '[:space:]') ||
      fail "Die nächste freie Proxmox-VMID konnte nicht ermittelt werden."
    VMID=$nextid
  fi

  [[ $VMID =~ ^[0-9]+$ && $VMID -ge 100 && $VMID -le 999999999 ]] ||
    fail "Ungültige VMID: ${VMID}. Erwartet wird eine Ganzzahl zwischen 100 und 999999999."
  if resources_contain_vmid "$VMID"; then
    fail "Die VMID ${VMID} ist bereits belegt; es wird nichts überschrieben."
  fi
  if name_is_in_use; then
    fail "Ein LXC namens ${CONTAINER_NAME} existiert bereits; es wird nichts überschrieben."
  fi
}

storage_candidates() {
  pvesm status --content rootdir | awk 'NR > 1 && $1 != "" && $3 == "active" { print $1 }'
}

bridge_candidates() {
  ip -o link show type bridge | sed -E 's/^[0-9]+: ([^:]+):.*/\1/'
}

choose_unique() {
  local kind=$1
  local requested=$2
  shift 2
  local candidates=("$@")
  local candidate

  if [[ -n $requested ]]; then
    for candidate in "${candidates[@]}"; do
      if [[ $candidate == "$requested" ]]; then
        printf '%s' "$requested"
        return 0
      fi
    done
    fail "${kind} '${requested}' ist nicht als geeignete aktive Option verfügbar. Verfügbar: ${candidates[*]:-keine}."
  fi

  ((${#candidates[@]} == 1)) && {
    printf '%s' "${candidates[0]}"
    return 0
  }
  if ((${#candidates[@]} == 0)); then
    fail "Keine geeignete ${kind} gefunden. Verfügbare Optionen: keine."
  fi
  local option_name=storage
  [[ $kind == Bridge ]] && option_name=bridge
  fail "Mehrere geeignete ${kind} gefunden. Bitte --${option_name} wählen: ${candidates[*]}"
}

resolve_storage_and_bridge() {
  local -a storages bridges
  mapfile -t storages < <(storage_candidates) ||
    fail "Geeignete Storages konnten nicht gelesen werden."
  mapfile -t bridges < <(bridge_candidates) ||
    fail "Geeignete Netzwerk-Bridges konnten nicht gelesen werden."
  STORAGE=$(choose_unique "Storage" "$STORAGE" "${storages[@]}")
  BRIDGE=$(choose_unique "Bridge" "$BRIDGE" "${bridges[@]}")
}

resolve_template() {
  local catalog
  local storage
  local template
  local -a template_storages templates
  catalog=$(pveam available --section system) ||
    fail "Der Proxmox-Templatekatalog konnte nicht gelesen werden."
  grep -Eq "$TEMPLATE_PATTERN" <<<"$catalog" ||
    fail "Kein Ubuntu-26.04-LXC-Template im Proxmox-Katalog gefunden."
  mapfile -t template_storages < <(pvesm status --content vztmpl | awk 'NR > 1 && $1 != "" && $3 == "active" { print $1 }')
  for storage in "${template_storages[@]}"; do
    while IFS= read -r template; do
      [[ -n $template ]] && templates+=("$template")
    done < <(pveam list "$storage" | awk -v pattern="$TEMPLATE_PATTERN" '$1 ~ pattern { print $1 }')
  done
  ((${#templates[@]} > 0)) ||
    fail "Kein Ubuntu-26.04-LXC-Template in einem aktiven Template-Storage gefunden."
  TEMPLATE=$(printf '%s\n' "${templates[@]}" | sort -V | tail -n1)
}

validate_values() {
  validate_positive_integer '--cores' "$CORES"
  validate_positive_integer '--memory' "$MEMORY_MIB"
  validate_non_negative_integer '--swap' "$SWAP_MIB"
  validate_positive_integer '--disk' "$DISK_GIB"
}

validate_plan() {
  (( EUID == 0 )) || fail "Der Proxmox-Plan muss als root ausgeführt werden."
  check_command pveversion
  check_command pveam
  check_command pvesh
  check_command pvesm
  check_command pct
  check_command ip
  pveversion >/dev/null 2>&1 || fail "Die Proxmox-Version konnte nicht abgefragt werden."
  resolve_template
  validate_values
  resolve_vmid
  resolve_storage_and_bridge
}

print_plan() {
  local prefix=$1
  printf '%s\n' "$prefix"
  printf '  VMID: %s\n' "$VMID"
  printf '  Name: %s\n' "$CONTAINER_NAME"
  printf '  Template: %s\n' "$TEMPLATE"
  printf '  LXC-Features: %s\n' "$LXC_FEATURES"
  printf '  Storage: %s\n' "$STORAGE"
  printf '  Bridge: %s\n' "$BRIDGE"
  printf '  CPU: %s Kerne\n' "$CORES"
  printf '  RAM: %s MiB\n' "$MEMORY_MIB"
  printf '  Swap: %s MiB\n' "$SWAP_MIB"
  printf '  Root-Disk: %s GiB\n' "$DISK_GIB"
}

verify_created_config() {
  local config=$1
  if ! grep -Eq '^unprivileged: 1$' <<<"$config"; then
    printf 'Fehler: Erzeugte Konfiguration ist nicht unprivilegiert.\n' >&2
    return 1
  fi
  if ! grep -Eq "^hostname: ${CONTAINER_NAME}$" <<<"$config"; then
    printf 'Fehler: Hostname der erzeugten Konfiguration stimmt nicht.\n' >&2
    return 1
  fi
  if ! grep -Eq "^cores: ${CORES}$" <<<"$config"; then
    printf 'Fehler: CPU-Konfiguration stimmt nicht.\n' >&2
    return 1
  fi
  if ! grep -Eq "^memory: ${MEMORY_MIB}$" <<<"$config"; then
    printf 'Fehler: RAM-Konfiguration stimmt nicht.\n' >&2
    return 1
  fi
  if ! grep -Eq "^swap: ${SWAP_MIB}$" <<<"$config"; then
    printf 'Fehler: Swap-Konfiguration stimmt nicht.\n' >&2
    return 1
  fi
  if ! grep -Eq "^rootfs: ${STORAGE}:.*size=${DISK_GIB}G([,[:space:]]|$)" <<<"$config"; then
    printf 'Fehler: Root-Disk-Konfiguration stimmt nicht.\n' >&2
    return 1
  fi
  if ! grep -Eq "^net0: .*bridge=${BRIDGE}(,|$).*ip=dhcp(,|$)" <<<"$config"; then
    printf 'Fehler: DHCP-Bridge-Konfiguration stimmt nicht.\n' >&2
    return 1
  fi
  if ! grep -Fxq "features: ${LXC_FEATURES}" <<<"$config"; then
    printf 'Fehler: LXC-Features müssen exakt "features: %s" sein.\n' "$LXC_FEATURES" >&2
    return 1
  fi
  if grep -Eq '^mp[0-9]+:' <<<"$config"; then
    printf 'Fehler: Die erzeugte Konfiguration enthält unerwartete Mountpoints.\n' >&2
    return 1
  fi
}

report_failed_create() {
  local state="nicht in pct config sichtbar"
  if pct config "$VMID" >/dev/null 2>&1; then
    state="in pct config registriert; mögliche Teilressource"
  fi
  printf 'Container erstellt: nein bestätigt; pct create ist fehlgeschlagen.\n' >&2
  printf '  VMID: %s\n' "$VMID" >&2
  printf '  Zustand: %s\n' "$state" >&2
  printf '  Rollback: nicht automatisch ausgeführt.\n' >&2
  printf '  Nächster manueller Schritt: Zustand und Proxmox-Storage prüfen.\n' >&2
}

run_plan() {
  validate_plan
  print_plan 'Plan erfolgreich; es wurden keine Änderungen vorgenommen.'
}

run_apply() {
  local first_vmid first_storage first_bridge first_template
  local create_output config status_output
  validate_plan
  first_vmid=$VMID
  first_storage=$STORAGE
  first_bridge=$BRIDGE
  first_template=$TEMPLATE

  validate_plan
  [[ $VMID == "$first_vmid" && $STORAGE == "$first_storage" &&
    $BRIDGE == "$first_bridge" && $TEMPLATE == "$first_template" ]] ||
    fail "Der unmittelbare Preflight lieferte einen geänderten Plan (zuvor VMID=${first_vmid}, Storage=${first_storage}, Bridge=${first_bridge}, Template=${first_template}; jetzt VMID=${VMID}, Storage=${STORAGE}, Bridge=${BRIDGE}, Template=${TEMPLATE}); es wurde nichts erstellt."
  print_plan 'Unmittelbarer Preflight erfolgreich; genau ein LXC wird erstellt.'

  PCT_CREATE_ATTEMPTED=1
  if ! create_output=$(pct create "$VMID" "$TEMPLATE" \
    --hostname "$CONTAINER_NAME" \
    --unprivileged 1 \
    --cores "$CORES" \
    --memory "$MEMORY_MIB" \
    --swap "$SWAP_MIB" \
    --rootfs "${STORAGE}:${DISK_GIB}" \
    --net0 "name=eth0,bridge=${BRIDGE},ip=dhcp,type=veth" \
    --features "$LXC_FEATURES" \
    --ostype ubuntu 2>&1); then
    printf '%s\n' "$create_output" >&2
    report_failed_create
    return 1
  fi

  if ! config=$(pct config "$VMID"); then
    printf 'Container erstellt: ja; read-only Konfigurationsprüfung konnte nicht gelesen werden.\n' >&2
    printf '  VMID: %s\n  Zustand: erstellt, aber nicht validiert\n  Rollback: nicht automatisch ausgeführt.\n' "$VMID" >&2
    return 1
  fi
  if ! verify_created_config "$config"; then
    printf 'Container erstellt: ja; Konfigurationsprüfung fehlgeschlagen.\n' >&2
    printf '  VMID: %s\n  Zustand: erstellt, aber nicht validiert\n  Rollback: nicht automatisch ausgeführt.\n' "$VMID" >&2
    return 1
  fi
  if ! status_output=$(pct status "$VMID"); then
    printf 'Container erstellt: ja; Status konnte nicht read-only gelesen werden.\n' >&2
    printf '  VMID: %s\n  Zustand: erstellt, aber nicht validiert\n  Rollback: nicht automatisch ausgeführt.\n' "$VMID" >&2
    return 1
  fi
  if ! grep -Eq 'status: stopped$' <<<"$status_output"; then
    printf 'Container erstellt: ja; Container ist nicht erwartungsgemäß gestoppt.\n' >&2
    printf '  VMID: %s\n  Zustand: gestartet oder unbekannt\n  Rollback: nicht automatisch ausgeführt.\n' "$VMID" >&2
    return 1
  fi
  printf 'Container erstellt: ja\n'
  printf '  VMID: %s\n' "$VMID"
  printf '  Zustand: gestoppt (kein automatischer Start)\n'
  printf '  Nächster manueller Schritt: Softwareinstallation in einem separaten Arbeitsdurchlauf.\n'
}

parse_args "$@"
if [[ $MODE == apply ]]; then
  run_apply
else
  run_plan
fi
