#!/usr/bin/env bash

set -Eeuo pipefail

readonly EXPECTED_NAME='ralf-standalone'
readonly EXPECTED_SOURCE_SHA256='8f5b30c7d9335824dfabb19cab5b338337860a45e785a6985370da9b8f6f48d7'
readonly REMOTE_BUNDLE='/run/ralf-bootstrap-unit-update'
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
readonly SCRIPT_DIR
PROJECT_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
readonly PROJECT_ROOT
readonly TARGET_UNIT="$PROJECT_ROOT/deploy/bootstrap-status/ralf-bootstrap.service"
readonly GUEST_SCRIPT="$SCRIPT_DIR/ralf-bootstrap-status-unit-update-guest.sh"

MODE=''
VMID=''
TARGET_SHA256=''
UPDATE_STATE='unit_update_conflict'
LOCAL_BUNDLE=''
PLAN_DONE=0

usage() {
  cat >&2 <<'EOF'
Aufruf:
  ralf-bootstrap-status-unit-update.sh --plan --vmid <VMID>
  ralf-bootstrap-status-unit-update.sh --apply --vmid <VMID>
EOF
  exit 2
}

fail() {
  printf 'Fehler: %s\n' "$1" >&2
  printf '  VMID: %s\n' "${VMID:-unbekannt}" >&2
  printf '  Klassifikation: %s\n' "$UPDATE_STATE" >&2
  printf '  Remote-Bundle: %s\n' "$REMOTE_BUNDLE" >&2
  printf '  Kein zweiter Update-, Übertragungs- oder Restartversuch wurde ausgeführt.\n' >&2
  exit 1
}

select_mode() {
  [[ -z $MODE ]] || fail 'Es darf genau ein Ausführungsmodus angegeben werden.'
  MODE=$1
}

parse_args() {
  while (($#)); do
    case $1 in
      --plan) select_mode plan; shift ;;
      --apply) select_mode apply; shift ;;
      --vmid)
        (($# >= 2)) || fail '--vmid benötigt einen Wert.'
        VMID=$2
        shift 2
        ;;
      --help) usage ;;
      *) fail "Unbekannte Option: $1" ;;
    esac
  done
  [[ -n $MODE && -n $VMID ]] || usage
  [[ $VMID =~ ^[0-9]+$ && $VMID -ge 100 && $VMID -le 999999999 ]] || fail "Ungültige VMID: $VMID"
}

validate_target_unit() {
  python3 - "$TARGET_UNIT" "$EXPECTED_SOURCE_SHA256" <<'PY'
from pathlib import Path
import hashlib
import re
import sys

path = Path(sys.argv[1])
source_hash = sys.argv[2]
if not path.is_file() or path.is_symlink():
    raise SystemExit("Ziel-Unit ist keine reguläre Datei.")
data = path.read_bytes()
control_line = b"  --no-control-socket \\\n"
old_families = b"RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6\n"
new_families = b"RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6 AF_NETLINK\n"
if data.count(control_line) != 1 or data.count(new_families) != 1:
    raise SystemExit("Die beiden erlaubten Unitänderungen sind nicht eindeutig.")
if b"--control-socket" in data or b"AF_PACKET" in data or b"CAP_NET_ADMIN" in data or b"CAP_NET_RAW" in data:
    raise SystemExit("Die Ziel-Unit enthält eine verbotene Netzwerk- oder Control-Socket-Einstellung.")
for exact in (
    b"User=ralf-bootstrap\n",
    b"Group=ralf-bootstrap\n",
    b"ExecStart=/opt/ralf/bootstrap/venv/bin/gunicorn \\\n",
    b"  --workers 1 \\\n",
    b"  --bind 127.0.0.1:8080 \\\n",
    b"NoNewPrivileges=true\n",
    b"ProtectSystem=strict\n",
    b"CapabilityBoundingSet=\n",
    b"AmbientCapabilities=\n",
):
    if data.count(exact) != 1:
        raise SystemExit(f"Vorgabe fehlt oder ist mehrfach vorhanden: {exact!r}")
for forbidden in (b"0.0.0.0", b"RuntimeDirectory=", b"Environment=HOME=", b"sudo", b"ExecStartPre=", b"ExecStartPost="):
    if forbidden in data:
        raise SystemExit(f"Verbotener Unitinhalt: {forbidden!r}")
if re.search(rb"^AmbientCapabilities=\S+", data, re.MULTILINE) or re.search(rb"^CapabilityBoundingSet=\S+", data, re.MULTILINE):
    raise SystemExit("Capability-Grenzen sind nicht leer.")
reconstructed = data.replace(control_line, b"", 1).replace(new_families, old_families, 1)
if hashlib.sha256(reconstructed).hexdigest() != source_hash:
    raise SystemExit("Die Ziel-Unit enthält Änderungen außerhalb des freigegebenen Deltas.")
print(hashlib.sha256(data).hexdigest())
PY
}

check_local_files() {
  local mode owner
  [[ -f $TARGET_UNIT && ! -L $TARGET_UNIT ]] || fail "Ziel-Unit fehlt oder ist ein Symlink: $TARGET_UNIT"
  [[ -f $GUEST_SCRIPT && ! -L $GUEST_SCRIPT ]] || fail "Gast-Updater fehlt oder ist ein Symlink: $GUEST_SCRIPT"
  mode=$(stat -c '%a' "$TARGET_UNIT")
  owner=$(stat -c '%u' "$TARGET_UNIT")
  [[ $owner == "$EUID" ]] || fail "Ziel-Unit gehört nicht dem ausführenden Repository-Benutzer: UID $owner"
  (( (8#$mode & 0022) == 0 )) || fail "Ziel-Unit ist gruppen- oder weltbeschreibbar: Modus $mode"
  TARGET_SHA256=$(validate_target_unit) || fail 'Lokale Ziel-Unit verletzt die semantische Updategrenze.'
  [[ $TARGET_SHA256 =~ ^[0-9a-f]{64}$ && $TARGET_SHA256 != "$EXPECTED_SOURCE_SHA256" ]] || fail 'Ziel-Unit-Hash ist ungültig oder entspricht der alten Unit.'
  bash -n "$GUEST_SCRIPT" || fail 'Gast-Updater besitzt einen Syntaxfehler.'
}

check_container() {
  command -v pct >/dev/null 2>&1 || fail 'pct ist nicht verfügbar; Proxmox-Rechte können nicht geprüft werden.'
  [[ $(pct status "$VMID" 2>/dev/null) == 'status: running' ]] || fail "VMID $VMID ist nicht running oder nicht lesbar."
  local config pending line features
  config=$(pct config "$VMID" --current 1) || fail 'Containerkonfiguration konnte nicht gelesen werden.'
  grep -Eq '^hostname:[[:space:]]*ralf-standalone$' <<<"$config" || fail "Containername ist nicht $EXPECTED_NAME."
  grep -Eq '^unprivileged:[[:space:]]*1$' <<<"$config" || fail 'Container ist nicht unprivilegiert.'
  features=$(awk -F': *' '$1 == "features" {print $2}' <<<"$config")
  [[ ,$features, == *,nesting=1,* || $features == nesting=1 ]] || fail 'nesting=1 ist nicht wirksam.'
  pending=$(pct pending "$VMID") || fail 'Pending-Konfiguration konnte nicht gelesen werden.'
  while IFS= read -r line; do
    [[ -z $line || $line == cur\ * ]] || fail "Pending-Proxmox-Änderung vorhanden: $line"
  done <<<"$pending"
}

check_remote_bundle_absent() {
  if pct exec "$VMID" -- test -e "$REMOTE_BUNDLE"; then
    fail "Remote-Updatebundle existiert bereits und wird nicht überschrieben: $REMOTE_BUNDLE"
  fi
}

classify_guest() {
  local output status diagnostics
  diagnostics=$(mktemp)
  set +e
  output=$(pct exec "$VMID" -- bash -s -- --classify --target-sha256 "$TARGET_SHA256" <"$GUEST_SCRIPT" 2>"$diagnostics")
  status=$?
  set -e
  if [[ -s $diagnostics ]]; then
    printf 'Gastdiagnose:\n' >&2
    cat "$diagnostics" >&2
  fi
  find "$diagnostics" -maxdepth 0 -type f -delete
  ((status == 0)) || fail 'Read-only Gastklassifikation ist fehlgeschlagen.'
  [[ $output != *$'\n'* ]] || fail 'Gastklassifikation enthält mehrere oder zusätzliche stdout-Zeilen.'
  [[ $output =~ ^RALF_BOOTSTRAP_UNIT_STATE_V1=(unit_update_required|unit_already_current|unit_update_conflict)$ ]] || fail 'Gastklassifikation ist leer, unbekannt oder nicht eindeutig.'
  UPDATE_STATE=${BASH_REMATCH[1]}
}

run_preflight() {
  check_local_files
  check_container
  check_remote_bundle_absent
  classify_guest
  [[ $UPDATE_STATE != unit_update_conflict ]] || fail 'Gast meldet unit_update_conflict; kein automatisches Update ist zulässig.'
  PLAN_DONE=1
}

print_plan() {
  local installed_hash service_state
  installed_hash=$(pct exec "$VMID" -- sha256sum /etc/systemd/system/ralf-bootstrap.service | awk '{print $1}') || fail 'Installierter Unit-Hash konnte nicht gelesen werden.'
  service_state=$(pct exec "$VMID" -- systemctl show ralf-bootstrap.service -p ActiveState -p SubState -p Result -p ExecMainStatus -p NRestarts --no-pager | paste -sd, -) || fail 'Dienstzustand konnte nicht gelesen werden.'
  printf 'RALF Bootstrap Unit-Update-Plan\n'
  printf '  VMID: %s\n' "$VMID"
  printf '  Containername: %s\n' "$EXPECTED_NAME"
  printf '  Bootstrap-Version: 0.1.0\n'
  printf '  Dienstzustand: %s\n' "$service_state"
  printf '  Installierte Unit: /etc/systemd/system/ralf-bootstrap.service\n'
  printf '  Quell-Hash: %s\n' "$installed_hash"
  printf '  Zulässiger alter Hash: %s\n' "$EXPECTED_SOURCE_SHA256"
  printf '  Ziel-Hash: %s\n' "$TARGET_SHA256"
  printf '  Klassifikation: %s\n' "$UPDATE_STATE"
  printf '  Erlaubte Änderung 1: genau --no-control-socket ergänzen.\n'
  printf '  Erlaubte Änderung 2: RestrictAddressFamilies ausschließlich um AF_NETLINK ergänzen.\n'
  if [[ $UPDATE_STATE == unit_update_required ]]; then
    printf '  Apply-Bundle: exakt ralf-bootstrap.service, ralf-bootstrap-status-unit-update-guest.sh und SHA256SUMS nach %s.\n' "$REMOTE_BUNDLE"
    printf '  Apply: Unit atomar ersetzen, genau ein daemon-reload, genau ein Restart, begrenzte Bereitschafts- und vollständige read-only Nachprüfung.\n'
  else
    printf '  Apply: bereits aktuell; keine Übertragung, kein daemon-reload und kein Restart.\n'
  fi
  printf '  Ausgeschlossen: Anwendung, Wheel, Runtime-Lock, Venv, Konfiguration, Benutzer, Daten, Pakete, enable, Stop/Start, Containerneustart, LAN-Freigabe und Rollback.\n'
  printf '  Erwartete Nachprüfung: Unit/Prozess/Journal, Loopback, drei HTTP-Endpunkte, Netzwerk configured, Sicherheitsheader, Härtung und unveränderte Anwendungshashes.\n'
}

prepare_bundle() {
  LOCAL_BUNDLE=$(mktemp -d)
  install -m 0644 "$TARGET_UNIT" "$LOCAL_BUNDLE/ralf-bootstrap.service"
  install -m 0750 "$GUEST_SCRIPT" "$LOCAL_BUNDLE/ralf-bootstrap-status-unit-update-guest.sh"
  (cd "$LOCAL_BUNDLE" && sha256sum ralf-bootstrap.service ralf-bootstrap-status-unit-update-guest.sh >SHA256SUMS)
  chmod 0640 "$LOCAL_BUNDLE/SHA256SUMS"
  [[ $(find "$LOCAL_BUNDLE" -mindepth 1 -maxdepth 1 -type f | wc -l) == 3 ]] || fail 'Lokales Updatebundle enthält nicht genau drei Dateien.'
}

cleanup_local() {
  if [[ -n $LOCAL_BUNDLE && -d $LOCAL_BUNDLE ]]; then
    find "$LOCAL_BUNDLE" -type f -delete
    find "$LOCAL_BUNDLE" -depth -type d -empty -delete
  fi
}

cleanup_remote_after_success() {
  pct exec "$VMID" -- rm -f -- \
    "$REMOTE_BUNDLE/ralf-bootstrap.service" \
    "$REMOTE_BUNDLE/ralf-bootstrap-status-unit-update-guest.sh" \
    "$REMOTE_BUNDLE/SHA256SUMS" || fail 'Update war erfolgreich, aber die drei Bundle-Dateien konnten nicht entfernt werden.'
  pct exec "$VMID" -- rmdir -- "$REMOTE_BUNDLE" || fail 'Update war erfolgreich, aber das leere Bundle-Verzeichnis konnte nicht entfernt werden.'
}

apply_update() {
  [[ $PLAN_DONE == 1 ]] || fail 'Apply wurde ohne vollständigen unmittelbar vorherigen Preflight aufgerufen.'
  if [[ $UPDATE_STATE == unit_already_current ]]; then
    printf 'Unit ist bereits aktuell; keine Übertragung oder Mutation ausgeführt.\n'
    return 0
  fi
  [[ $UPDATE_STATE == unit_update_required ]] || fail "Apply ist für $UPDATE_STATE nicht zulässig."
  prepare_bundle
  pct exec "$VMID" -- install -d -m 0700 -o root -g root "$REMOTE_BUNDLE" || fail 'Remote-Updatebundle konnte nicht angelegt werden.'
  local file
  for file in ralf-bootstrap.service ralf-bootstrap-status-unit-update-guest.sh SHA256SUMS; do
    pct push "$VMID" "$LOCAL_BUNDLE/$file" "$REMOTE_BUNDLE/$file" || fail "Übertragung fehlgeschlagen: $file"
  done
  pct exec "$VMID" -- bash "$REMOTE_BUNDLE/ralf-bootstrap-status-unit-update-guest.sh" \
    --apply --target-sha256 "$TARGET_SHA256" --bundle "$REMOTE_BUNDLE" ||
    fail 'Gast-Unit-Update ist fehlgeschlagen; Bundle und erreichter Zustand bleiben zur Diagnose erhalten.'
  cleanup_remote_after_success
  printf 'Unit-Update erfolgreich; VMID %s blieb ohne Containerneustart.\n' "$VMID"
}

main() {
  parse_args "$@"
  trap cleanup_local EXIT
  run_preflight
  print_plan
  if [[ $MODE == plan ]]; then
    printf 'Plan blieb vollständig read-only; es wurde kein Remote-Bundle angelegt.\n'
    exit 0
  fi
  apply_update
}

main "$@"
