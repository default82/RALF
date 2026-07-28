#!/usr/bin/env bash

set -Eeuo pipefail

readonly CONTAINER_NAME="ralf-standalone"
readonly TEMPLATE_PATTERN='ubuntu-26\.04-standard'

fail() {
  printf 'Fehler: %s\n' "$*" >&2
  exit 1
}

usage() {
  printf 'Aufruf: %s --check\n' "${0##*/}" >&2
  exit 2
}

check_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Benötigter Befehl fehlt: $1"
}

run_preflight() {
  local templates
  local containers

  (( EUID == 0 )) || fail "Der Proxmox-Preflight muss als root ausgeführt werden."

  check_command pveversion
  check_command pveam
  check_command pct

  pveversion >/dev/null 2>&1 ||
    fail "Die Proxmox-Version konnte nicht abgefragt werden."

  templates=$(pveam available --section system) ||
    fail "Der Proxmox-Templatekatalog konnte nicht gelesen werden."
  grep -Eq "$TEMPLATE_PATTERN" <<<"$templates" ||
    fail "Kein Ubuntu-26.04-LXC-Template im Proxmox-Katalog gefunden."

  containers=$(pct list) ||
    fail "Die vorhandenen LXC-Container konnten nicht gelesen werden."
  if awk -v name="$CONTAINER_NAME" 'NR > 1 && $NF == name { found = 1 } END { exit !found }' <<<"$containers"; then
    fail "Ein LXC mit dem Namen ${CONTAINER_NAME} existiert bereits."
  fi

  printf 'Preflight erfolgreich: Proxmox ist bereit und der Name %s ist frei.\n' "$CONTAINER_NAME"
}

[[ $# == 1 && $1 == "--check" ]] || usage
run_preflight
