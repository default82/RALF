#!/usr/bin/env bash

set -Eeuo pipefail

readonly EXPECTED_NAME='ralf-standalone'
readonly EXPECTED_VERSION='0.1.0'
readonly REMOTE_BUNDLE='/run/ralf-bootstrap-install'
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
readonly SCRIPT_DIR
PROJECT_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
readonly PROJECT_ROOT
readonly INSTALL_SCRIPT="$SCRIPT_DIR/ralf-bootstrap-status-install.sh"
readonly RUNTIME_LOCK="$PROJECT_ROOT/requirements/runtime.lock"
readonly CONFIG_FILE="$PROJECT_ROOT/deploy/bootstrap-status/config.toml"
readonly UNIT_FILE="$PROJECT_ROOT/deploy/bootstrap-status/ralf-bootstrap.service"
readonly BUILD_PYTHON="${RALF_BUILD_PYTHON:-python3}"

MODE=''
VMID=''
BUNDLE_DIR=''
WHEEL=''
PLAN_DONE=0
TARGET_STATE='unknown'

usage() {
  cat >&2 <<'EOF'
Aufruf:
  ralf-bootstrap-status-deploy.sh --plan --vmid <VMID>
  ralf-bootstrap-status-deploy.sh --apply --vmid <VMID>
EOF
  exit 2
}

fail() {
  printf 'Fehler: %s\n' "$1" >&2
  printf '  VMID: %s\n' "${VMID:-unbekannt}" >&2
  printf '  Remote-Bundle: %s\n' "$REMOTE_BUNDLE" >&2
  printf '  Kein zweiter Übertragungs- oder Installationsversuch wurde ausgeführt.\n' >&2
  exit 1
}

select_mode() {
  local requested=$1
  if [[ -n $MODE && $MODE != "$requested" ]]; then
    fail 'Widersprüchliche Modi --plan und --apply.'
  fi
  MODE=$requested
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
  [[ $VMID =~ ^[0-9]+$ && $VMID -ge 100 && $VMID -le 999999999 ]] || fail "Ungültige VMID: $VMID."
}

require_files() {
  local path
  for path in "$RUNTIME_LOCK" "$CONFIG_FILE" "$UNIT_FILE" "$INSTALL_SCRIPT"; do
    [[ -f $path ]] || fail "Deploymentartefakt fehlt: $path."
  done
}

check_container() {
  local config pending line
  [[ $(pct status "$VMID") == 'status: running' ]] || fail "VMID $VMID ist nicht running."
  config=$(pct config "$VMID" --current 1) || fail "Konfiguration von VMID $VMID konnte nicht gelesen werden."
  grep -Eq '^hostname: [[:space:]]*ralf-standalone$' <<<"$config" || fail "VMID $VMID hat nicht den Namen $EXPECTED_NAME."
  pending=$(pct pending "$VMID") || fail "Pending-Konfiguration von VMID $VMID konnte nicht gelesen werden."
  while IFS= read -r line; do
    [[ -z $line || $line == cur\ * ]] || fail "VMID $VMID besitzt eine ausstehende Änderung: $line"
  done <<<"$pending"
}

check_guest_read_only() {
  local version existing_state
  version=$(pct exec "$VMID" -- python3 --version 2>&1) || fail 'Python-Version im Gast konnte nicht gelesen werden.'
  grep -Eq '^Python 3\.(1[2-9]|[2-9][0-9])\.' <<<"$version" || fail "Python erfüllt nicht die Mindestversion 3.12: $version"
  pct exec "$VMID" -- python3 -m venv --help >/dev/null 2>&1 ||
    printf 'Hinweis: python3 -m venv fehlt; Apply darf ausschließlich das passende Ubuntu-venv-Paket installieren.\n'
  existing_state=$(pct exec "$VMID" -- python3 -c '
from pathlib import Path
markers = [Path("/opt/ralf/bootstrap"), Path("/opt/ralf/bootstrap/app"), Path("/opt/ralf/bootstrap/venv"), Path("/opt/ralf/bootstrap/VERSION"), Path("/etc/ralf/bootstrap"), Path("/etc/ralf/bootstrap/config.toml"), Path("/var/lib/ralf/bootstrap"), Path("/etc/systemd/system/ralf-bootstrap.service")]
present = sum(path.exists() for path in markers)
if present == 0:
    print("absent")
elif present == len(markers) and not Path("/var/lib/ralf/bootstrap/state.db").exists():
    print("complete")
else:
    print("partial")
') || fail 'Zielzustand im Gast konnte nicht ermittelt werden.'
  TARGET_STATE=$existing_state
  case $TARGET_STATE in
    absent) ;;
    complete) printf 'Hinweis: vollständige vorhandene Installation erkannt; der Gast-Installer prüft sie idempotent.\n' ;;
    *) fail 'Im Gast ist eine teilweise oder abweichende Installation vorhanden.' ;;
  esac
  if [[ $TARGET_STATE == absent ]]; then
    if pct exec "$VMID" -- getent passwd ralf-bootstrap >/dev/null 2>&1; then
      fail 'Der Benutzer ralf-bootstrap ist bereits vorhanden.'
    fi
    if pct exec "$VMID" -- getent group ralf-bootstrap >/dev/null 2>&1; then
      fail 'Die Gruppe ralf-bootstrap ist bereits vorhanden.'
    fi
  fi
  if ! pct exec "$VMID" -- python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 8080)); s.close()' >/dev/null 2>&1; then
    if [[ $TARGET_STATE != complete ]] || ! pct exec "$VMID" -- systemctl is-active --quiet ralf-bootstrap.service; then
      fail '127.0.0.1:8080 ist bereits belegt.'
    fi
  fi
  if pct exec "$VMID" -- ss -ltn 2>/dev/null | grep -Eq '(^|[[:space:]])(127\.0\.0\.1|::1):8080([[:space:]]|$)'; then
    if [[ $TARGET_STATE != complete ]] || ! pct exec "$VMID" -- systemctl is-active --quiet ralf-bootstrap.service; then
      fail 'Port 127.0.0.1:8080 ist laut ss belegt.'
    fi
  fi
}

build_wheel() {
  local build_dir=$1 source_dir
  command -v "$BUILD_PYTHON" >/dev/null 2>&1 || fail "Build-Python fehlt: $BUILD_PYTHON."
  source_dir=$(mktemp -d "$BUNDLE_DIR/source.XXXXXX")
  cp "$PROJECT_ROOT/pyproject.toml" "$source_dir/pyproject.toml"
  cp -a "$PROJECT_ROOT/src" "$source_dir/src"
  (cd "$source_dir" && "$BUILD_PYTHON" -m build --wheel --no-isolation --outdir "$build_dir") >/dev/null ||
    fail 'Wheel konnte nicht gebaut werden. Installiere das festgelegte Buildwerkzeug lokal und wiederhole den Plan.'
  mapfile -t wheels < <(find "$build_dir" -mindepth 1 -maxdepth 1 -type f -name 'ralf_bootstrap-*.whl' -printf '%f\n' | sort)
  ((${#wheels[@]} == 1)) || fail 'Der Build erzeugte nicht genau ein ralf-bootstrap-Wheel.'
  WHEEL=${wheels[0]}
  [[ $WHEEL =~ ^ralf_bootstrap-0\.1\.0-.*\.whl$ ]] || fail "Unerwartete Wheel-Version oder Dateiname: $WHEEL"
  "$BUILD_PYTHON" - "$build_dir/$WHEEL" <<'PY' || fail 'Wheel-Metadaten enthalten nicht ralf-bootstrap 0.1.0.'
import email
import sys
import zipfile

with zipfile.ZipFile(sys.argv[1]) as archive:
    names = [name for name in archive.namelist() if name.endswith('.dist-info/METADATA')]
    if len(names) != 1:
        raise SystemExit(1)
    metadata = email.message_from_bytes(archive.read(names[0]))
    if metadata.get('Name') != 'ralf-bootstrap' or metadata.get('Version') != '0.1.0':
        raise SystemExit(1)
PY
}

prepare_bundle() {
  BUNDLE_DIR=$(mktemp -d)
  local build_dir="$BUNDLE_DIR/dist"
  mkdir -p "$build_dir"
  build_wheel "$build_dir"
  install -m 0640 "$build_dir/$WHEEL" "$BUNDLE_DIR/$WHEEL"
  install -m 0640 "$RUNTIME_LOCK" "$BUNDLE_DIR/runtime.lock"
  install -m 0640 "$CONFIG_FILE" "$BUNDLE_DIR/config.toml"
  install -m 0640 "$UNIT_FILE" "$BUNDLE_DIR/ralf-bootstrap.service"
  install -m 0750 "$INSTALL_SCRIPT" "$BUNDLE_DIR/ralf-bootstrap-status-install.sh"
  (cd "$BUNDLE_DIR" && sha256sum "$WHEEL" runtime.lock config.toml ralf-bootstrap.service ralf-bootstrap-status-install.sh > SHA256SUMS)
  chmod 0640 "$BUNDLE_DIR/SHA256SUMS"
}

print_hashes() {
  local file
  printf 'Geprüfte Artefakte und SHA-256:\n'
  while IFS= read -r file; do
    printf '  %s  %s\n' "${file%% *}" "${file#*  }"
  done <"$BUNDLE_DIR/SHA256SUMS"
}

run_plan() {
  require_files
  check_container
  check_guest_read_only
  prepare_bundle
  print_hashes
  PLAN_DONE=1
  printf 'Plan erfolgreich; VMID %s wurde nicht verändert (Paketversion %s).\n' "$VMID" "$EXPECTED_VERSION"
  printf '  Bestehender Zielzustand: %s\n' "$TARGET_STATE"
  printf '  Übertragung bei --apply: genau die Dateien aus %s nach %s\n' "$BUNDLE_DIR" "$REMOTE_BUNDLE"
  printf '  Gastaktion bei --apply: genau einmal ralf-bootstrap-status-install.sh --apply\n'
  printf '  Benutzer/Gruppe: idempotent ralf-bootstrap als Systembenutzer mit /usr/sbin/nologin und /nonexistent\n'
  printf '  Dateien: root:ralf-bootstrap; Bootstrap/App/venv/Konfigurationsverzeichnisse 0750, VERSION/Artefakte/Konfiguration 0640\n'
  printf '  Python: temporäre venv, Runtime-Lock per HTTPS exakt installieren, Wheel anschließend --no-deps installieren\n'
  printf '  Dienst: daemon-reload, enable und start; kein Containerneustart, keine LAN-Bindung, keine state.db\n'
  printf '  Nach Erfolg: nur temporäre Bundle-Dateien im Gast entfernen.\n'
  printf '  Bei Fehler: kein Rollback; temporärer Zustand bleibt zur Prüfung erhalten.\n'
}

cleanup_local() {
  if [[ -n $BUNDLE_DIR && -d $BUNDLE_DIR ]]; then
    find "$BUNDLE_DIR" -type f -delete
    find "$BUNDLE_DIR" -depth -type d -empty -delete
  fi
}

apply_bundle() {
  [[ $PLAN_DONE == 1 ]] || fail 'Apply wurde ohne vollständigen Preflight aufgerufen.'
  pct exec "$VMID" -- install -d -m 0700 "$REMOTE_BUNDLE" || fail 'Temporäres Gastverzeichnis konnte nicht angelegt werden.'
  local file
  for file in "$WHEEL" runtime.lock config.toml ralf-bootstrap.service ralf-bootstrap-status-install.sh SHA256SUMS; do
    pct push "$VMID" "$BUNDLE_DIR/$file" "$REMOTE_BUNDLE/$file" || fail "Übertragung fehlgeschlagen: $file"
  done
  pct exec "$VMID" -- bash "$REMOTE_BUNDLE/ralf-bootstrap-status-install.sh" --apply --bundle "$REMOTE_BUNDLE" ||
    fail 'Gast-Installationsskript ist fehlgeschlagen; temporäre Gastartefakte bleiben erhalten.'
  pct exec "$VMID" -- rm -rf "$REMOTE_BUNDLE" || fail 'Erfolgreiche Installation, aber temporäre Gastartefakte konnten nicht entfernt werden.'
  printf 'Deployment erfolgreich; VMID %s wurde nicht neugestartet.\n' "$VMID"
}

main() {
  parse_args "$@"
  trap cleanup_local EXIT
  if [[ $MODE == plan ]]; then
    run_plan
    exit 0
  fi
  run_plan
  apply_bundle
}

main "$@"
