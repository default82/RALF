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
RESUME=0
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
  ralf-bootstrap-status-deploy.sh --resume --vmid <VMID>
  ralf-bootstrap-status-deploy.sh --resume --apply --vmid <VMID>
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
      --resume) RESUME=1; shift ;;
      --vmid)
        (($# >= 2)) || fail '--vmid benötigt einen Wert.'
        VMID=$2
        shift 2
        ;;
      --help) usage ;;
      *) fail "Unbekannte Option: $1" ;;
    esac
  done
  if [[ -z $MODE && $RESUME == 1 ]]; then
    MODE=plan
  fi
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
  if ! pct exec "$VMID" -- python3 -c 'import ensurepip, venv; print(ensurepip.version())' >/dev/null 2>&1; then
    printf 'Hinweis: ensurepip/venv ist nicht vollständig verfügbar; der Gastinstaller ermittelt das passende pythonX.Y-venv-Paket.\n'
  fi
  existing_state=$(pct exec "$VMID" -- python3 -c '
from pathlib import Path
import grp
import pwd
import socket
import stat
import subprocess

root = Path("/opt/ralf/bootstrap")
final = [Path("/opt/ralf/bootstrap/app"), Path("/opt/ralf/bootstrap/venv"), Path("/opt/ralf/bootstrap/VERSION"), Path("/etc/ralf/bootstrap"), Path("/etc/ralf/bootstrap/config.toml"), Path("/var/lib/ralf/bootstrap"), Path("/etc/systemd/system/ralf-bootstrap.service")]
state_db = Path("/var/lib/ralf/bootstrap/state.db")
if not root.exists() and not any(path.exists() for path in final):
    print("absent")
elif all(path.exists() for path in final) and not state_db.exists():
    print("complete")
else:
    try:
        user = pwd.getpwnam("ralf-bootstrap")
        group = grp.getgrnam("ralf-bootstrap")
        root_stat = root.stat()
        temps = sorted(root.glob(".venv-build.*"))
        app_temps = list(root.glob(".app-build.*"))
        service_absent = not Path("/etc/systemd/system/ralf-bootstrap.service").exists()
        service_inactive = all(subprocess.run(["systemctl", action, "ralf-bootstrap.service"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode != 0 for action in ("is-enabled", "is-active"))
        sock = socket.socket()
        try:
            sock.bind(("127.0.0.1", 8080))
            port_free = True
        except OSError:
            port_free = False
        finally:
            sock.close()
        recoverable = (
            root.is_dir() and root_stat.st_uid == pwd.getpwnam("root").pw_uid and root_stat.st_gid == group.gr_gid and stat.S_IMODE(root_stat.st_mode) == 0o750
            and user.pw_gid == group.gr_gid and user.pw_dir == "/nonexistent" and user.pw_shell == "/usr/sbin/nologin"
            and len(temps) == 1 and not app_temps and all(not path.exists() for path in final) and not state_db.exists()
            and service_absent and service_inactive and port_free
        )
    except (KeyError, OSError):
        recoverable = False
    print("recoverable_venv_failure" if recoverable else "partial")
') || fail 'Zielzustand im Gast konnte nicht ermittelt werden.'
  TARGET_STATE=$existing_state
  case $TARGET_STATE in
    absent) ;;
    complete) printf 'Hinweis: vollständige vorhandene Installation erkannt; der Gast-Installer prüft sie idempotent.\n' ;;
    recoverable_venv_failure) printf 'Hinweis: recoverable_venv_failure erkannt; nur --resume darf diesen Teilzustand behandeln.\n' ;;
    *) fail 'Im Gast ist eine teilweise oder abweichende Installation vorhanden.' ;;
  esac
  if [[ $MODE == apply && $RESUME == 0 && $TARGET_STATE == recoverable_venv_failure ]]; then
    fail 'recoverable_venv_failure erkannt; normaler --apply bleibt gesperrt. Verwende ausdrücklich --resume --apply.'
  fi
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

check_remote_bundle() {
  local state
  state=$(pct exec "$VMID" -- python3 -c '
import hashlib
from pathlib import Path
import re

bundle = Path("/run/ralf-bootstrap-install")
files = {path.name for path in bundle.iterdir() if path.is_file()}
wheels = sorted(name for name in files if re.fullmatch(r"ralf_bootstrap-0\.1\.0-.+\.whl", name))
expected = {"SHA256SUMS", "runtime.lock", "config.toml", "ralf-bootstrap.service", "ralf-bootstrap-status-install.sh"}
if len(wheels) != 1 or files != expected | {wheels[0]}:
    print("invalid")
else:
    valid = True
    entries = {}
    for line in (bundle / "SHA256SUMS").read_text(encoding="utf-8").splitlines():
        parts = line.split(maxsplit=1)
        if len(parts) != 2:
            valid = False
            break
        digest, name = parts
        if name in entries:
            valid = False
            break
        entries[name] = digest
    if set(entries) != files:
        valid = False
    for name, digest in entries.items():
        path = bundle / name
        if Path(name).name != name or not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest() != digest:
            valid = False
            break
    print("valid" if valid else "invalid")
') || fail 'Vorhandenes Resume-Bundle konnte nicht gelesen werden.'
  [[ $state == valid ]] || fail 'Das vorhandene Resume-Bundle ist unvollständig oder enthält unerwartete Dateien.'
}

run_guest_resume() {
  local guest_mode=$1
  if [[ $guest_mode == plan ]]; then
    pct exec "$VMID" -- bash -s -- --resume --plan --bundle "$REMOTE_BUNDLE" <"$INSTALL_SCRIPT" ||
      fail 'Der read-only Resume-Plan im Gast ist fehlgeschlagen.'
  else
    pct exec "$VMID" -- bash -s -- --resume --apply --bundle "$REMOTE_BUNDLE" <"$INSTALL_SCRIPT" ||
      fail 'Der Gast-Resume ist fehlgeschlagen; Bundle und erreichten Zustand unverändert zur Prüfung belassen.'
  fi
}

resume_preflight() {
  require_files
  check_container
  check_guest_read_only
  [[ $TARGET_STATE == recoverable_venv_failure ]] ||
    fail "Resume ist nur für recoverable_venv_failure zulässig; erkannt: $TARGET_STATE."
  check_remote_bundle
}

run_resume_plan() {
  resume_preflight
  run_guest_resume plan
  printf 'Resume-Plan erfolgreich; VMID %s wurde nicht verändert.\n' "$VMID"
  printf '  Zustand: recoverable_venv_failure\n'
  printf '  Vorhandenes Bundle: %s (Prüfsummen erfolgreich)\n' "$REMOTE_BUNDLE"
  printf '  Bei --resume --apply: genau ein Gast-Resume ohne erneute Artefaktübertragung.\n'
}

run_resume_apply() {
  resume_preflight
  run_guest_resume apply
  pct exec "$VMID" -- rm -rf -- "$REMOTE_BUNDLE" ||
    fail 'Resume erfolgreich, aber temporäre Gastartefakte konnten nicht entfernt werden.'
  printf 'Resume erfolgreich; VMID %s wurde nicht neugestartet.\n' "$VMID"
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
  pct exec "$VMID" -- rm -rf -- "$REMOTE_BUNDLE" || fail 'Erfolgreiche Installation, aber temporäre Gastartefakte konnten nicht entfernt werden.'
  printf 'Deployment erfolgreich; VMID %s wurde nicht neugestartet.\n' "$VMID"
}

main() {
  parse_args "$@"
  trap cleanup_local EXIT
  if ((RESUME == 1)); then
    if [[ $MODE == plan ]]; then
      run_resume_plan
    else
      run_resume_apply
    fi
    exit 0
  fi
  if [[ $MODE == plan ]]; then
    run_plan
    exit 0
  fi
  run_plan
  apply_bundle
}

main "$@"
