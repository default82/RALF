#!/usr/bin/env bash

set -Eeuo pipefail

readonly CONTAINER_NAME="ralf-standalone"
readonly TEMPLATE_PATTERN='ubuntu-26\.04-standard'
readonly DEFAULT_CORES=4
readonly DEFAULT_MEMORY_MIB=12288
readonly DEFAULT_SWAP_MIB=4096
readonly DEFAULT_DISK_GIB=40

MODE="plan"
VMID=""
STORAGE=""
BRIDGE=""
CORES="$DEFAULT_CORES"
MEMORY_MIB="$DEFAULT_MEMORY_MIB"
SWAP_MIB="$DEFAULT_SWAP_MIB"
DISK_GIB="$DEFAULT_DISK_GIB"

fail() {
  printf 'Fehler: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat >&2 <<'EOF'
Aufruf:
  ralf-standalone-bootstrap.sh [--plan|--check] [OPTIONEN]

Optionen:
  --vmid ID       VMID; Standard: nächste freie Proxmox-VMID
  --storage NAME  Ziel-Storage; Standard: genau ein geeigneter Storage
  --bridge NAME   Netzwerk-Bridge; Standard: genau eine geeignete Bridge
  --cores N       CPU-Kerne; Standard: 4
  --memory MIB    Arbeitsspeicher in MiB; Standard: 12288 (12 GiB)
  --swap MIB      Swap in MiB; Standard: 4096 (4 GiB)
  --disk GIB      Root-Disk in GiB; Standard: 40
  --plan          sicheren Konfigurationsplan ausgeben (Standard)
  --check         Alias für --plan
  --help          diese Hilfe anzeigen
EOF
  exit 2
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
      --plan|--check)
        MODE="plan"
        shift
        ;;
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
      --help)
        usage
        ;;
      *)
        fail "Unbekannte Option: $1"
        ;;
    esac
  done
}

resources_contain_vmid() {
  local resources
  resources=$(pvesh get /cluster/resources --type vm --output-format json) ||
    fail "Die belegten Proxmox-VMIDs konnten nicht gelesen werden."
  grep -Eq '"vmid"[[:space:]]*:[[:space:]]*'"$1"'([,}])' <<<"$resources"
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
      [[ $candidate == "$requested" ]] && return 0
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

validate_values() {
  validate_positive_integer '--cores' "$CORES"
  validate_positive_integer '--memory' "$MEMORY_MIB"
  validate_non_negative_integer '--swap' "$SWAP_MIB"
  validate_positive_integer '--disk' "$DISK_GIB"
}

run_plan() {
  local templates

  (( EUID == 0 )) || fail "Der Proxmox-Plan muss als root ausgeführt werden."
  check_command pveversion
  check_command pveam
  check_command pvesh
  check_command pvesm
  check_command pct
  check_command ip
  pveversion >/dev/null 2>&1 || fail "Die Proxmox-Version konnte nicht abgefragt werden."

  templates=$(pveam available --section system) ||
    fail "Der Proxmox-Templatekatalog konnte nicht gelesen werden."
  grep -Eq "$TEMPLATE_PATTERN" <<<"$templates" ||
    fail "Kein Ubuntu-26.04-LXC-Template im Proxmox-Katalog gefunden."

  validate_values
  resolve_vmid
  resolve_storage_and_bridge

  printf 'Plan erfolgreich; es wurden keine Änderungen vorgenommen.\n'
  printf '  VMID: %s\n' "$VMID"
  printf '  Name: %s\n' "$CONTAINER_NAME"
  printf '  Storage: %s\n' "$STORAGE"
  printf '  Bridge: %s\n' "$BRIDGE"
  printf '  CPU: %s Kerne\n' "$CORES"
  printf '  RAM: %s MiB\n' "$MEMORY_MIB"
  printf '  Swap: %s MiB\n' "$SWAP_MIB"
  printf '  Root-Disk: %s GiB\n' "$DISK_GIB"
}

parse_args "$@"
[[ $MODE == plan ]] || fail "Unbekannter Ausführungsmodus."
run_plan
