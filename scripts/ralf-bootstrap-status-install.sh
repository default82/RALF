#!/usr/bin/env bash

set -Eeuo pipefail

readonly EXPECTED_VERSION='0.1.0'
readonly EXPECTED_OS='ubuntu'
readonly EXPECTED_UBUNTU='26.04'
readonly EXPECTED_GROUP='ralf-bootstrap'
readonly EXPECTED_USER='ralf-bootstrap'
readonly EXPECTED_SHELL='/usr/sbin/nologin'
readonly EXPECTED_HOME='/nonexistent'
readonly INDEX_URL='https://pypi.org/simple'
readonly UBUNTU_MIRROR='https://archive.ubuntu.com/ubuntu/'
readonly ROOT_PREFIX="${RALF_INSTALL_ROOT:-}"

MODE=''
BUNDLE=''
PREFLIGHT_COMPLETED=0
LAST_MUTATION='keine'
VENV_AVAILABLE=0
VENV_PACKAGE=''
INSTALL_STATE='unbekannt'
WHEEL=''

target_path() {
  printf '%s%s' "$ROOT_PREFIX" "$1"
}

bootstrap_root=$(target_path '/opt/ralf/bootstrap')
app_dir=$(target_path '/opt/ralf/bootstrap/app')
venv_dir=$(target_path '/opt/ralf/bootstrap/venv')
version_file=$(target_path '/opt/ralf/bootstrap/VERSION')
config_dir=$(target_path '/etc/ralf/bootstrap')
config_file=$(target_path '/etc/ralf/bootstrap/config.toml')
state_dir=$(target_path '/var/lib/ralf/bootstrap')
unit_file=$(target_path '/etc/systemd/system/ralf-bootstrap.service')
unit_dir=$(target_path '/etc/systemd/system')
os_release_file=$(target_path '/etc/os-release')
lock_files=(
  "$(target_path '/var/lib/dpkg/lock')"
  "$(target_path '/var/lib/dpkg/lock-frontend')"
  "$(target_path '/var/lib/apt/lists/lock')"
  "$(target_path '/var/cache/apt/archives/lock')"
)

usage() {
  cat >&2 <<'EOF'
Aufruf:
  ralf-bootstrap-status-install.sh --plan --bundle /run/ralf-bootstrap-install
  ralf-bootstrap-status-install.sh --apply --bundle /run/ralf-bootstrap-install
EOF
  exit 2
}

fail() {
  printf 'Fehler: %s\n' "$1" >&2
  printf '  Preflight abgeschlossen: %s\n' "$([[ $PREFLIGHT_COMPLETED == 1 ]] && printf 'ja' || printf 'nein')" >&2
  printf '  Letzter mutierender Schritt: %s\n' "$LAST_MUTATION" >&2
  printf '  Installationszustand: %s\n' "$INSTALL_STATE" >&2
  printf '  Nächster manueller Schritt: erreichten Zustand prüfen; kein automatischer Rollback oder zweiter Versuch.\n' >&2
  exit 1
}

select_mode() {
  local requested=$1
  if [[ -n $MODE && $MODE != "$requested" ]]; then
    fail "Widersprüchliche Ausführungsmodi."
  fi
  MODE=$requested
}

parse_args() {
  while (($#)); do
    case $1 in
      --plan) select_mode plan; shift ;;
      --apply) select_mode apply; shift ;;
      --bundle)
        (($# >= 2)) || fail '--bundle benötigt einen Wert.'
        BUNDLE=$2
        shift 2
        ;;
      --help) usage ;;
      *) fail "Unbekannte Option: $1" ;;
    esac
  done
  [[ -n $MODE ]] || usage
  [[ -n $BUNDLE ]] || fail '--bundle ist erforderlich.'
  [[ $BUNDLE == /* && $BUNDLE != */ ]] || fail '--bundle muss ein absoluter Verzeichnispfad sein.'
}

check_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Benötigter Befehl fehlt: $1."
}

check_commands() {
  local command_name
  for command_name in apt-get awk dpkg find fuser getent grep groupadd id install ip pgrep python3 sha256sum sort stat systemctl uname useradd wget; do
    check_command "$command_name"
  done
}

check_root() {
  [[ $(id -u) == 0 ]] || fail 'Dieses Skript muss als root ausgeführt werden.'
}

check_os() {
  [[ -r $os_release_file ]] || fail "Betriebssysteminformationen fehlen: $os_release_file."
  # shellcheck disable=SC1090
  . "$os_release_file"
  [[ ${ID:-} == "$EXPECTED_OS" ]] || fail "Nicht unterstütztes Betriebssystem: ${ID:-unbekannt}."
  [[ ${VERSION_ID:-} == "$EXPECTED_UBUNTU" ]] || fail "Nicht unterstützte Ubuntu-Version: ${VERSION_ID:-unbekannt}."
}

check_architecture_and_python() {
  local architecture python_version major minor
  architecture=$(uname -m 2>/dev/null) || fail 'Architektur konnte nicht ermittelt werden.'
  [[ $architecture == amd64 || $architecture == x86_64 ]] || fail "Nicht unterstützte Architektur: $architecture."
  python_version=$(python3 -c 'import sys; print("%d.%d.%d" % sys.version_info[:3])') ||
    fail 'Python 3 konnte nicht ausgeführt werden.'
  IFS=. read -r major minor _ <<<"$python_version"
  ((major > 3 || (major == 3 && minor >= 12))) || fail "Python $python_version ist zu alt; mindestens 3.12 ist erforderlich."
  if python3 -m venv --help >/dev/null 2>&1; then
    VENV_AVAILABLE=1
  else
    VENV_AVAILABLE=0
    VENV_PACKAGE="python${major}.${minor}-venv"
  fi
}

check_systemd() {
  local state
  state=$(systemctl is-system-running 2>/dev/null) || fail 'systemd ist nicht betriebsfähig.'
  [[ $state == running ]] || fail "systemd meldet keinen betriebsfähigen Zustand: $state."
}

check_network() {
  local routes dns
  ip -4 route show default | grep -q '^default[[:space:]]' || fail 'Keine IPv4-Default-Route vorhanden.'
  dns=$(getent ahostsv4 archive.ubuntu.com 2>/dev/null) || fail 'DNS-Auflösung für archive.ubuntu.com fehlgeschlagen.'
  [[ -n $dns ]] || fail 'DNS-Auflösung lieferte kein Ergebnis.'
  wget --spider --quiet --timeout=15 --tries=1 "$UBUNTU_MIRROR" >/dev/null 2>&1 ||
    fail 'HTTPS-Erreichbarkeit der Ubuntu-Paketquelle fehlgeschlagen.'
  routes=$(ip -4 route show default)
  [[ -n $routes ]] || fail 'Default-Route konnte nicht gelesen werden.'
}

check_package_state() {
  local process lock
  dpkg --audit >/dev/null 2>&1 || fail 'dpkg meldet einen beschädigten Paketstatus.'
  for process in apt apt-get dpkg unattended-upgrade; do
    if pgrep -x "$process" >/dev/null 2>&1; then
      fail "Paketmanagerprozess läuft bereits: $process."
    fi
  done
  for lock in "${lock_files[@]}"; do
    if [[ -e $lock ]] && fuser -s "$lock" >/dev/null 2>&1; then
      fail "Paketmanager-Lock ist belegt: $lock."
    fi
  done
}

find_wheel() {
  local -a wheels
  mapfile -t wheels < <(find "$BUNDLE" -mindepth 1 -maxdepth 1 -type f -name 'ralf_bootstrap-0.1.0-*.whl' -printf '%f\n' | sort)
  ((${#wheels[@]} == 1)) || fail 'Bundle muss genau ein Wheel ralf_bootstrap-0.1.0-*.whl enthalten.'
  WHEEL=${wheels[0]}
}

check_bundle_files() {
  local -a expected actual
  expected=("$WHEEL" SHA256SUMS config.toml ralf-bootstrap.service ralf-bootstrap-status-install.sh runtime.lock)
  mapfile -t actual < <(find "$BUNDLE" -mindepth 1 -maxdepth 1 -type f -printf '%f\n' | sort)
  mapfile -t expected < <(printf '%s\n' "${expected[@]}" | sort)
  [[ ${actual[*]} == "${expected[*]}" ]] || fail 'Bundle enthält unerwartete oder fehlende Dateien.'
  (cd "$BUNDLE" && sha256sum -c SHA256SUMS >/dev/null) || fail 'Eine Bundle-Prüfsumme ist ungültig.'
}

check_wheel_metadata() {
  python3 - "$BUNDLE/$WHEEL" <<'PY' || exit 1
import email
import sys
import zipfile

wheel_path = sys.argv[1]
with zipfile.ZipFile(wheel_path) as archive:
    metadata_names = [name for name in archive.namelist() if name.endswith('.dist-info/METADATA')]
    if len(metadata_names) != 1:
        raise SystemExit('Wheel-Metadaten fehlen oder sind nicht eindeutig.')
    message = email.message_from_bytes(archive.read(metadata_names[0]))
    if message.get('Name') != 'ralf-bootstrap' or message.get('Version') != '0.1.0':
        raise SystemExit('Wheel-Metadaten enthalten nicht ralf-bootstrap 0.1.0.')
PY
}

check_user_group() {
  local passwd_line group_line user_gid group_gid groups
  passwd_line=$(getent passwd "$EXPECTED_USER" || true)
  group_line=$(getent group "$EXPECTED_GROUP" || true)
  if [[ -z $passwd_line && -z $group_line ]]; then
    return 0
  fi
  [[ -n $passwd_line && -n $group_line ]] || fail 'Benutzer und Gruppe sind nur teilweise vorhanden.'
  IFS=: read -r _ _ _ user_gid _ user_home user_shell <<<"$passwd_line"
  IFS=: read -r _ _ group_gid _ <<<"$group_line"
  [[ $user_home == "$EXPECTED_HOME" && $user_shell == "$EXPECTED_SHELL" && $user_gid == "$group_gid" ]] ||
    fail 'Vorhandener ralf-bootstrap-Benutzer entspricht nicht dem Sollzustand.'
  groups=$(id -Gn "$EXPECTED_USER")
  [[ $groups == "$EXPECTED_GROUP" ]] || fail 'ralf-bootstrap besitzt unerwartete Gruppenzugehörigkeiten.'
  if getent group sudo >/dev/null 2>&1 && getent group sudo | grep -Eq '(^|,)'"$EXPECTED_USER"'(,|$)'; then
    fail 'ralf-bootstrap besitzt unerlaubte sudo-Gruppenzugehörigkeit.'
  fi
}

check_install_state() {
  local -a markers existing
  markers=(
    "$bootstrap_root" "$app_dir" "$app_dir/$WHEEL" "$app_dir/runtime.lock"
    "$venv_dir" "$venv_dir/bin/gunicorn" "$version_file"
    "$config_dir" "$config_file" "$state_dir" "$unit_file"
  )
  existing=()
  for marker in "${markers[@]}"; do
    [[ -e $marker ]] && existing+=("$marker")
  done
  if ((${#existing[@]} == 0)); then
    INSTALL_STATE='absent'
  elif ((${#existing[@]} == ${#markers[@]})) && [[ ! -e $(target_path '/var/lib/ralf/bootstrap/state.db') ]]; then
    INSTALL_STATE='complete'
  else
    INSTALL_STATE='partial'
    fail 'Eine teilweise oder abweichende Bootstrap-Installation ist vorhanden; sie wird nicht überschrieben.'
  fi
  if [[ $INSTALL_STATE == complete ]]; then
    local artifact installed
    for artifact in "$WHEEL" runtime.lock; do
      installed="$app_dir/$artifact"
      [[ $(sha256sum "$installed" | cut -d' ' -f1) == $(sha256sum "$BUNDLE/$artifact" | cut -d' ' -f1) ]] ||
        fail "Vorhandenes Artefakt weicht vom Bundle ab: $artifact."
    done
    [[ $(sha256sum "$config_file" | cut -d' ' -f1) == $(sha256sum "$BUNDLE/config.toml" | cut -d' ' -f1) ]] ||
      fail 'Vorhandene config.toml weicht vom Bundle ab.'
    [[ $(sha256sum "$unit_file" | cut -d' ' -f1) == $(sha256sum "$BUNDLE/ralf-bootstrap.service" | cut -d' ' -f1) ]] ||
      fail 'Vorhandene systemd-Unit weicht vom Bundle ab.'
  fi
  if [[ $INSTALL_STATE == absent ]] && { [[ -e "$unit_file" ]] || [[ -n $(getent passwd "$EXPECTED_USER" || true) ]] || [[ -n $(getent group "$EXPECTED_GROUP" || true) ]]; }; then
    fail 'Benutzer, Gruppe oder systemd-Unit ist ohne vollständige Installation vorhanden.'
  fi
}

port_is_free() {
  python3 - <<'PY'
import socket
sock = socket.socket()
try:
    sock.bind(('127.0.0.1', 8080))
except OSError:
    raise SystemExit(1)
finally:
    sock.close()
PY
}

check_port() {
  if ! port_is_free; then
    if [[ $INSTALL_STATE != complete ]] || ! systemctl is-active --quiet ralf-bootstrap.service; then
      fail '127.0.0.1:8080 ist bereits belegt.'
    fi
  fi
}

check_preflight() {
  check_root
  check_commands
  [[ -d $BUNDLE ]] || fail "Bundle-Verzeichnis fehlt: $BUNDLE."
  find_wheel
  check_bundle_files
  check_wheel_metadata
  check_os
  check_architecture_and_python
  check_systemd
  check_network
  check_package_state
  check_user_group
  check_install_state
  check_port
  PREFLIGHT_COMPLETED=1
}

print_plan() {
  printf 'Plan erfolgreich; Modus: %s; es wurden noch keine Installationsmutationen ausgeführt.\n' "$MODE"
  printf '  Bundle: %s\n' "$BUNDLE"
  printf '  Wheel: %s (Version %s)\n' "$WHEEL" "$EXPECTED_VERSION"
  printf '  Installationszustand: %s\n' "$INSTALL_STATE"
  printf '  Ziel: /opt/ralf/bootstrap/{app,venv,VERSION}\n'
  printf '  Konfiguration: /etc/ralf/bootstrap/config.toml\n'
  printf '  Zustandspfad: /var/lib/ralf/bootstrap/ (state.db wird nicht angelegt)\n'
  printf '  Benutzer/Gruppe: %s:%s, Systembenutzer, Shell %s, Home %s\n' "$EXPECTED_USER" "$EXPECTED_GROUP" "$EXPECTED_SHELL" "$EXPECTED_HOME"
  printf '  Dienst: ralf-bootstrap.service, Gunicorn auf 127.0.0.1:8080\n'
  if ((VENV_AVAILABLE == 0)); then
    printf '  Fehlendes venv: Apply dürfte ausschließlich %s installieren.\n' "$VENV_PACKAGE"
  else
    printf '  Python-venv: verfügbar; keine Paketinstallation hierfür erforderlich.\n'
  fi
  printf '  Runtime-Quelle: exakt gepinnte Pakete über HTTPS von PyPI; Runtime-Artefakte sind noch nicht gehasht.\n'
}

ensure_user_group() {
  local group_line passwd_line
  group_line=$(getent group "$EXPECTED_GROUP" || true)
  if [[ -z $group_line ]]; then
    LAST_MUTATION='Systemgruppe ralf-bootstrap anlegen'
    groupadd --system "$EXPECTED_GROUP"
  fi
  passwd_line=$(getent passwd "$EXPECTED_USER" || true)
  if [[ -z $passwd_line ]]; then
    LAST_MUTATION='Systembenutzer ralf-bootstrap anlegen'
    useradd --system --gid "$EXPECTED_GROUP" --shell "$EXPECTED_SHELL" --home-dir "$EXPECTED_HOME" --no-create-home "$EXPECTED_USER"
  fi
  check_user_group
}

install_runtime() {
  local temp_venv
  temp_venv=$(mktemp -d "$bootstrap_root/.venv-build.XXXXXX")
  if ((VENV_AVAILABLE == 0)); then
    LAST_MUTATION="Paket $VENV_PACKAGE installieren"
    DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y "$VENV_PACKAGE" || fail "Die notwendige venv-Paketinstallation ist fehlgeschlagen: $VENV_PACKAGE."
    python3 -m venv --help >/dev/null 2>&1 || fail 'python3 -m venv ist nach der Paketinstallation weiterhin nicht verfügbar.'
  fi
  LAST_MUTATION='temporäre Python-Umgebung erstellen'
  python3 -m venv "$temp_venv" || fail 'Temporäre Python-Umgebung konnte nicht erstellt werden.'
  LAST_MUTATION='gepinnten Runtime-Abhängigkeiten installieren'
  "$temp_venv/bin/python" -m pip install --disable-pip-version-check --no-input --index-url "$INDEX_URL" --requirement "$BUNDLE/runtime.lock" ||
    fail 'Installation der gepinnten Runtime-Abhängigkeiten ist fehlgeschlagen.'
  LAST_MUTATION='geprüftes RALF-Wheel installieren'
  "$temp_venv/bin/python" -m pip install --disable-pip-version-check --no-input --no-deps "$BUNDLE/$WHEEL" ||
    fail 'Installation des geprüften RALF-Wheels ist fehlgeschlagen.'
  "$temp_venv/bin/python" - "$BUNDLE/runtime.lock" <<'PY' || fail 'Installierte Paketversionen entsprechen nicht dem Runtime-Lock.'
import importlib.metadata
import sys

lock_path = sys.argv[1]
expected = {}
for line in open(lock_path, encoding='utf-8'):
    line = line.strip()
    if line and not line.startswith('#'):
        name, version = line.split('==', 1)
        expected[name] = version
expected['ralf-bootstrap'] = '0.1.0'
for name, version in expected.items():
    actual = importlib.metadata.version(name)
    if actual != version:
        raise SystemExit(f'{name}: erwartet {version}, gefunden {actual}')
PY
  LAST_MUTATION='temporäre Python-Umgebung an Zielpfad verschieben'
  mv "$temp_venv" "$venv_dir"
  chown -R root:"$EXPECTED_GROUP" "$venv_dir"
  chmod 0750 "$venv_dir"
}

install_files() {
  local temp_app temp_version
  temp_app=$(mktemp -d "$bootstrap_root/.app-build.XXXXXX")
  install -m 0640 -o root -g "$EXPECTED_GROUP" "$BUNDLE/$WHEEL" "$temp_app/$WHEEL"
  install -m 0640 -o root -g "$EXPECTED_GROUP" "$BUNDLE/runtime.lock" "$temp_app/runtime.lock"
  LAST_MUTATION='Anwendung und Runtime-Lock an Zielpfad verschieben'
  mv "$temp_app" "$app_dir"
  chown -R root:"$EXPECTED_GROUP" "$app_dir"
  chmod 0750 "$app_dir"

  temp_version="$bootstrap_root/.VERSION.$$"
  printf '%s\n' "$EXPECTED_VERSION" >"$temp_version"
  install -m 0640 -o root -g "$EXPECTED_GROUP" "$temp_version" "$version_file"
  rm -f "$temp_version"

  install -d -m 0750 -o root -g "$EXPECTED_GROUP" "$config_dir"
  install -m 0640 -o root -g "$EXPECTED_GROUP" "$BUNDLE/config.toml" "$config_file"
  install -d -m 0750 -o "$EXPECTED_USER" -g "$EXPECTED_GROUP" "$state_dir"
  install -d -m 0755 -o root -g root "$unit_dir"
  install -m 0644 -o root -g root "$BUNDLE/ralf-bootstrap.service" "$unit_file"
}

check_installed_permissions() {
  local metadata
  for metadata in \
    "$bootstrap_root|root:$EXPECTED_GROUP|750" \
    "$app_dir|root:$EXPECTED_GROUP|750" \
    "$venv_dir|root:$EXPECTED_GROUP|750" \
    "$app_dir/$WHEEL|root:$EXPECTED_GROUP|640" \
    "$app_dir/runtime.lock|root:$EXPECTED_GROUP|640" \
    "$version_file|root:$EXPECTED_GROUP|640" \
    "$config_dir|root:$EXPECTED_GROUP|750" \
    "$config_file|root:$EXPECTED_GROUP|640" \
    "$state_dir|$EXPECTED_USER:$EXPECTED_GROUP|750" \
    "$unit_file|root:root|644"; do
    local path owner mode actual
    IFS='|' read -r path owner mode <<<"$metadata"
    actual=$(stat -c '%U:%G|%a' "$path")
    [[ $actual == "$owner|$mode" ]] || fail "Falsche Berechtigungen oder Eigentümer: $path ($actual, erwartet $owner|$mode)."
  done
  [[ ! -e $(target_path '/var/lib/ralf/bootstrap/state.db') ]] || fail 'state.db wurde unerwartet angelegt.'
}

activate_service() {
  if command -v systemd-analyze >/dev/null 2>&1; then
    systemd-analyze verify "$unit_file" || fail 'systemd-Unit ist syntaktisch oder semantisch ungültig.'
  fi
  LAST_MUTATION='systemd daemon-reload'
  systemctl daemon-reload
  LAST_MUTATION='systemd-Dienst aktivieren'
  systemctl enable ralf-bootstrap.service
  LAST_MUTATION='systemd-Dienst starten'
  systemctl start ralf-bootstrap.service
}

validate_service() {
  systemctl is-enabled ralf-bootstrap.service >/dev/null || fail 'ralf-bootstrap.service ist nicht aktiviert.'
  systemctl is-active ralf-bootstrap.service >/dev/null || fail 'ralf-bootstrap.service ist nicht aktiv.'
  python3 - <<'PY'
import json
from urllib.request import Request, urlopen

for path in ('/healthz', '/api/v1/status', '/'):
    with urlopen(Request('http://127.0.0.1:8080' + path), timeout=5) as response:
        body = response.read()
        if response.status != 200:
            raise SystemExit(f'{path}: HTTP {response.status}')
        for header in ('X-Content-Type-Options', 'X-Frame-Options', 'Referrer-Policy', 'Cache-Control'):
            if not response.headers.get(header):
                raise SystemExit(f'{path}: Sicherheitsheader fehlt: {header}')
        if path == '/api/v1/status':
            payload = json.loads(body)
            if payload['bootstrap']['version'] != '0.1.0':
                raise SystemExit('Status meldet falsche Bootstrap-Version.')
            if payload['bootstrap']['sqlite']['status'] != 'not_initialized':
                raise SystemExit('SQLite ist nicht im erwarteten not_initialized-Zustand.')
            if any(item['status'] != 'not_configured' for item in payload['components'][1:]):
                raise SystemExit('Modellkomponenten sind nicht not_configured.')
PY
}

main() {
  parse_args "$@"
  check_preflight
  print_plan
  if [[ $MODE == plan ]]; then
    exit 0
  fi
  if [[ $INSTALL_STATE == complete ]]; then
    check_installed_permissions
    validate_service
    printf 'Bereits vollständige Installation erkannt; es wurden keine Dateien ersetzt.\n'
    exit 0
  fi
  ensure_user_group
  install -d -m 0750 -o root -g "$EXPECTED_GROUP" "$bootstrap_root"
  install_runtime
  install_files
  check_installed_permissions
  activate_service
  validate_service
  printf 'Installation erfolgreich; ralf-bootstrap läuft als %s auf 127.0.0.1:8080.\n' "$EXPECTED_USER"
}

main "$@"
