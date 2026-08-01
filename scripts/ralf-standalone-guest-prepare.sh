#!/usr/bin/env bash

set -Eeuo pipefail

readonly EXPECTED_OS_ID='ubuntu'
readonly EXPECTED_VERSION_ID='26.04'
readonly EXPECTED_ARCHITECTURES='amd64|x86_64'
readonly UBUNTU_MIRROR='https://archive.ubuntu.com/ubuntu/'
readonly PACKAGE_CONF_OPTIONS=( '-o' 'Dpkg::Options::=--force-confold' )
readonly GUEST_ROOT="${RALF_GUEST_ROOT:-}"
readonly OS_RELEASE_FILE="${GUEST_ROOT}/etc/os-release"
readonly DPKG_UPDATES_DIRECTORY="${GUEST_ROOT}/var/lib/dpkg/updates"
readonly REBOOT_REQUIRED_FILE="${GUEST_ROOT}/var/run/reboot-required"
readonly RALF_DIRECTORIES=(
  "${GUEST_ROOT}/etc/ralf/"
  "${GUEST_ROOT}/var/lib/ralf/ollama/"
  "${GUEST_ROOT}/var/lib/ralf/webui/"
  "${GUEST_ROOT}/var/log/ralf/"
)

MODE=''
PREFLIGHT_COMPLETED=0
LAST_MUTATION='keine'
APT_UPDATE_STATUS='nicht ausgeführt'
PACKAGE_UPDATE_STATUS='nicht ausgeführt'
DIRECTORIES_STATUS='nicht begonnen'
REBOOT_STATUS='nicht geprüft'
HTTPS_TOOL=''

usage() {
  cat >&2 <<'EOF'
Aufruf:
  ralf-standalone-guest-prepare.sh --plan
  ralf-standalone-guest-prepare.sh --apply

Modi:
  --plan   read-only Plan ausgeben
  --apply  Ubuntu-Vorbereitung nach vollständigem Preflight ausführen
EOF
  exit 2
}

fail() {
  local message=$1
  if [[ $REBOOT_STATUS == 'nicht geprüft' ]]; then
    if [[ -e $REBOOT_REQUIRED_FILE ]]; then
      REBOOT_STATUS='ja (nur gemeldet)'
    else
      REBOOT_STATUS='nein oder nicht markiert'
    fi
  fi
  printf 'Fehler: %s\n' "$message" >&2
  printf '  Preflight abgeschlossen: %s\n' "$([[ $PREFLIGHT_COMPLETED == 1 ]] && printf 'ja' || printf 'nein')" >&2
  printf '  Letzter mutierender Schritt: %s\n' "$LAST_MUTATION" >&2
  printf '  apt-get update: %s\n' "$APT_UPDATE_STATUS" >&2
  printf '  Paketaktualisierung: %s\n' "$PACKAGE_UPDATE_STATUS" >&2
  printf '  Basisverzeichnisse: %s\n' "$DIRECTORIES_STATUS" >&2
  printf '  Neustart erforderlich: %s\n' "$REBOOT_STATUS" >&2
  printf '  Nächster manueller Schritt: Zustand prüfen und den gemeldeten Fehler beheben; kein automatischer Rollback oder Wiederholungsversuch wurde ausgeführt.\n' >&2
  exit 1
}

select_mode() {
  local requested=$1
  if [[ -n $MODE && $MODE != "$requested" ]]; then
    fail "Widersprüchliche Ausführungsmodi: --${MODE} und --${requested} dürfen nicht gemeinsam verwendet werden."
  fi
  MODE=$requested
}

parse_args() {
  while (($#)); do
    case $1 in
      --plan) select_mode plan; shift ;;
      --apply) select_mode apply; shift ;;
      --help) usage ;;
      *) fail "Unbekannte Option: $1" ;;
    esac
  done
  [[ -n $MODE ]] || usage
}

check_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Benötigter Befehl fehlt: $1."
}

check_required_commands() {
  local command_name
  for command_name in apt-get dpkg systemctl ip getent uname id find install chmod chown stat; do
    check_command "$command_name"
  done
  if command -v curl >/dev/null 2>&1; then
    HTTPS_TOOL='curl'
  elif command -v wget >/dev/null 2>&1; then
    HTTPS_TOOL='wget'
  else
    fail 'Für die Erreichbarkeitsprüfung der Ubuntu-Paketquelle fehlt curl oder wget.'
  fi
}

check_os() {
  [[ -r $OS_RELEASE_FILE ]] || fail "Betriebssysteminformationen fehlen: ${OS_RELEASE_FILE}."
  # shellcheck disable=SC1090
  . "$OS_RELEASE_FILE"
  [[ ${ID:-} == "$EXPECTED_OS_ID" ]] ||
    fail "Nicht unterstütztes Betriebssystem: ${ID:-unbekannt}; erwartet wird Ubuntu."
  [[ ${VERSION_ID:-} == "$EXPECTED_VERSION_ID" ]] ||
    fail "Nicht unterstützte Ubuntu-Version: ${VERSION_ID:-unbekannt}; erwartet wird 26.04."
}

check_architecture() {
  local architecture
  architecture=$(uname -m 2>/dev/null) || fail 'Die CPU-Architektur konnte nicht ermittelt werden.'
  [[ $architecture =~ ^(${EXPECTED_ARCHITECTURES})$ ]] ||
    fail "Nicht unterstützte Architektur: ${architecture}; erwartet wird amd64 beziehungsweise x86_64."
}

check_systemd() {
  local systemd_state networkd_state
  systemd_state=$(systemctl is-system-running 2>/dev/null) ||
    fail 'systemd ist nicht betriebsfähig.'
  [[ $systemd_state == running ]] ||
    fail "systemd meldet keinen betriebsfähigen Zustand: ${systemd_state}."
  networkd_state=$(systemctl is-active systemd-networkd 2>/dev/null) ||
    fail 'systemd-networkd ist nicht aktiv.'
  [[ $networkd_state == active ]] ||
    fail "systemd-networkd meldet nicht active: ${networkd_state}."
}

check_network() {
  local addresses routes dns_output
  addresses=$(ip -4 -o addr show scope global 2>/dev/null) ||
    fail 'IPv4-Adressen konnten nicht gelesen werden.'
  grep -Eq '[[:space:]]inet[[:space:]][0-9]+\.' <<<"$addresses" ||
    fail 'Es ist keine globale IPv4-Adresse vorhanden.'

  routes=$(ip -4 route show default 2>/dev/null) ||
    fail 'IPv4-Routen konnten nicht gelesen werden.'
  grep -q '^default[[:space:]]' <<<"$routes" ||
    fail 'Es ist keine IPv4-Default-Route vorhanden.'

  dns_output=$(getent ahostsv4 archive.ubuntu.com 2>/dev/null) ||
    fail 'DNS-Auflösung für archive.ubuntu.com ist fehlgeschlagen.'
  [[ -n $dns_output ]] || fail 'DNS-Auflösung lieferte kein Ergebnis.'

  if [[ $HTTPS_TOOL == curl ]]; then
    curl --fail --silent --show-error --location --max-time 15 "$UBUNTU_MIRROR" >/dev/null 2>&1 ||
      fail 'Die Ubuntu-Paketquelle ist per HTTPS nicht erreichbar.'
  else
    wget --spider --quiet --timeout=15 --tries=1 "$UBUNTU_MIRROR" >/dev/null 2>&1 ||
      fail 'Die Ubuntu-Paketquelle ist per HTTPS nicht erreichbar.'
  fi
}

check_dpkg_state() {
  dpkg --audit >/dev/null 2>&1 || fail 'dpkg meldet bereits eine beschädigte oder unvollständige Paketkonfiguration.'
  if [[ -d $DPKG_UPDATES_DIRECTORY ]] &&
    find "$DPKG_UPDATES_DIRECTORY" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null | grep -q .; then
    fail 'dpkg befindet sich bereits in einem unterbrochenen Zustand (ausstehende Update-Dateien).'
  fi
}

preflight() {
  [[ $(id -u) == 0 ]] || fail 'Dieses Skript muss als root ausgeführt werden.'
  check_os
  check_architecture
  check_required_commands
  check_systemd
  check_network
  check_dpkg_state
  PREFLIGHT_COMPLETED=1
}

print_plan() {
  cat <<'EOF'
Plan erfolgreich; es werden keine Änderungen vorgenommen.
  Erwartetes Betriebssystem: Ubuntu Server 26.04 LTS
  Erwartete Architektur: amd64 beziehungsweise x86_64
  Paketaktualisierung: apt-get update, danach nichtinteraktives apt-get full-upgrade
  Basisverzeichnisse:
    /etc/ralf/
    /var/lib/ralf/ollama/
    /var/lib/ralf/webui/
    /var/log/ralf/
  Besitzer: root:root
  Modus: 0750
  Ausgeschlossen: Ollama, qwen2.5-coder:7b, Open WebUI, Docker, Podman,
    zusätzliche Datenbanken, GPU-Komponenten und weitere RALF-Software
  Neustart: kein automatischer Neustart; ein erforderlicher Neustart wird nur gemeldet.
EOF
}

run_apt_update() {
  LAST_MUTATION='apt-get update'
  APT_UPDATE_STATUS='läuft'
  if ! DEBIAN_FRONTEND=noninteractive apt-get "${PACKAGE_CONF_OPTIONS[@]}" update; then
    APT_UPDATE_STATUS='fehlgeschlagen'
    fail 'apt-get update ist fehlgeschlagen.'
  fi
  APT_UPDATE_STATUS='erfolgreich'
}

run_package_update() {
  LAST_MUTATION='Paketaktualisierung mit apt-get full-upgrade'
  PACKAGE_UPDATE_STATUS='läuft'
  if ! DEBIAN_FRONTEND=noninteractive apt-get "${PACKAGE_CONF_OPTIONS[@]}" -y full-upgrade; then
    PACKAGE_UPDATE_STATUS='fehlgeschlagen'
    fail 'Die Paketaktualisierung mit apt-get full-upgrade ist fehlgeschlagen.'
  fi
  PACKAGE_UPDATE_STATUS='erfolgreich'
}

prepare_directories() {
  local directory
  DIRECTORIES_STATUS='teilweise oder unvollständig'
  for directory in "${RALF_DIRECTORIES[@]}"; do
    LAST_MUTATION="Basisverzeichnis ${directory}"
    install -d -m 0750 -o root -g root "$directory" ||
      fail "Das Basisverzeichnis ${directory} konnte nicht angelegt werden."
    chmod 0750 "$directory" ||
      fail "Die Berechtigungen von ${directory} konnten nicht gesetzt werden."
    chown root:root "$directory" ||
      fail "Der Besitzer von ${directory} konnte nicht gesetzt werden."
  done
  DIRECTORIES_STATUS='erfolgreich'
}

verify_os_and_packages() {
  check_os
  check_dpkg_state
}

verify_directories() {
  local directory metadata
  for directory in "${RALF_DIRECTORIES[@]}"; do
    [[ -d $directory && ! -L $directory ]] ||
      fail "Das erwartete Basisverzeichnis fehlt oder ist kein Verzeichnis: ${directory}."
    metadata=$(stat -c '%U:%G %a' "$directory" 2>/dev/null) ||
      fail "Besitzer und Modus von ${directory} konnten nicht gelesen werden."
    [[ $metadata == 'root:root 750' ]] ||
      fail "Unerwarteter Besitzer oder Modus für ${directory}: ${metadata}; erwartet root:root 750."
  done
}

verify_failed_units() {
  local failed_units
  failed_units=$(systemctl --failed --no-legend --no-pager 2>/dev/null) ||
    fail 'Fehlgeschlagene systemd-Units konnten nicht geprüft werden.'
  [[ -z $failed_units ]] || fail "Fehlgeschlagene systemd-Units vorhanden: ${failed_units}"
}

verify_reboot_requirement() {
  if [[ -e $REBOOT_REQUIRED_FILE ]]; then
    REBOOT_STATUS='ja (nur gemeldet)'
  else
    REBOOT_STATUS='nein'
  fi
}

verify_result() {
  verify_os_and_packages
  verify_directories
  check_systemd
  check_network
  verify_failed_units
  verify_reboot_requirement
}

print_result() {
  printf 'Vorbereitung erfolgreich; Ubuntu und Basiszustand wurden geprüft.\n'
  printf '  apt-get update: %s\n' "$APT_UPDATE_STATUS"
  printf '  Paketaktualisierung: %s\n' "$PACKAGE_UPDATE_STATUS"
  printf '  Basisverzeichnisse: %s (root:root, 0750)\n' "$DIRECTORIES_STATUS"
  printf '  Neustart erforderlich: %s\n' "$REBOOT_STATUS"
  printf '  Ausgeschlossen: Ollama, Modell, Open WebUI, Docker/Podman, Datenbanken und GPU-Komponenten\n'
  printf '  Nächster manueller Schritt: separater, ausdrücklich freigegebener Installationsschritt.\n'
}

parse_args "$@"
if [[ $MODE == plan ]]; then
  print_plan
else
  preflight
  run_apt_update
  run_package_update
  prepare_directories
  verify_result
  print_result
fi
