#!/usr/bin/env bash

set -Eeuo pipefail

readonly EXPECTED_VERSION='0.3.0'
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
RESUME=0
REPAIR_VENV=0
CLASSIFY=0
PREFLIGHT_COMPLETED=0
LAST_MUTATION='keine'
VENV_AVAILABLE=0
VENV_PACKAGE=''
PYTHON_VERSION=''
ENSUREPIP_VERSION='unavailable'
APT_CANDIDATE=''
APT_INSTALLED='unknown'
INSTALL_STATE='unbekannt'
WHEEL=''
RECOVERABLE_TEMP_VENV=''
TEMP_VENV_PATH=''
TEMP_VENV_REMOVED=0
NEW_VENV_CREATED=0
APT_INSTALL_SUCCEEDED=0
CLASSIFICATION_FAILURES=()
CLASSIFICATION_OBSERVED=()
CLASSIFICATION_EXPECTED=()
SERVICE_LOAD_STATE='unknown'
SERVICE_UNIT_FILE_STATE='unknown'
SERVICE_ACTIVE_STATE='unknown'
SERVICE_SUB_STATE='unknown'
SERVICE_RESULT='unknown'
SERVICE_EXEC_MAIN_CODE='unknown'
SERVICE_EXEC_MAIN_STATUS='unknown'

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
install_marker=$(target_path '/opt/ralf/bootstrap/.venv-install-in-progress')
repair_marker=$(target_path '/opt/ralf/bootstrap/.venv-repair-in-progress')
state_db=$(target_path '/var/lib/ralf/bootstrap/state.db')
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
  ralf-bootstrap-status-install.sh --resume --bundle /run/ralf-bootstrap-install
  ralf-bootstrap-status-install.sh --resume --apply --bundle /run/ralf-bootstrap-install
  ralf-bootstrap-status-install.sh --repair-venv --plan --bundle /run/ralf-bootstrap-install
  ralf-bootstrap-status-install.sh --repair-venv --apply --bundle /run/ralf-bootstrap-install
  ralf-bootstrap-status-install.sh --classify --bundle /run/ralf-bootstrap-install
EOF
  exit 2
}

fail() {
  printf 'Fehler: %s\n' "$1" >&2
  printf '  Preflight abgeschlossen: %s\n' "$([[ $PREFLIGHT_COMPLETED == 1 ]] && printf 'ja' || printf 'nein')" >&2
  printf '  Letzter mutierender Schritt: %s\n' "$LAST_MUTATION" >&2
  printf '  Installationszustand: %s\n' "$INSTALL_STATE" >&2
  printf '  Python: %s; ensurepip: %s; venv-Paket: %s; installiert: %s; Candidate: %s\n' "${PYTHON_VERSION:-unbekannt}" "$ENSUREPIP_VERSION" "${VENV_PACKAGE:-unbekannt}" "$APT_INSTALLED" "${APT_CANDIDATE:-unbekannt}" >&2
  printf '  Fehlgeschlagenes Venv: %s; entfernt: %s; neue Venv begonnen: %s (%s); Paketinstallation erfolgreich: %s\n' "${RECOVERABLE_TEMP_VENV:-keines}" "$TEMP_VENV_REMOVED" "$NEW_VENV_CREATED" "${TEMP_VENV_PATH:-kein Pfad}" "$APT_INSTALL_SUCCEEDED" >&2
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
      --resume) RESUME=1; shift ;;
      --repair-venv) REPAIR_VENV=1; shift ;;
      --classify) CLASSIFY=1; shift ;;
      --bundle)
        (($# >= 2)) || fail '--bundle benötigt einen Wert.'
        BUNDLE=$2
        shift 2
        ;;
      --help) usage ;;
      *) fail "Unbekannte Option: $1" ;;
    esac
  done
  if ((RESUME == 1 && REPAIR_VENV == 1)); then
    fail '--resume und --repair-venv dürfen nicht gemeinsam verwendet werden.'
  fi
  if ((CLASSIFY == 1)) && { [[ -n $MODE ]] || ((RESUME == 1 || REPAIR_VENV == 1)); }; then
    fail '--classify darf nicht mit Plan-, Apply-, Resume- oder Reparaturmodi kombiniert werden.'
  fi
  if [[ -z $MODE && ( $RESUME == 1 || $REPAIR_VENV == 1 ) ]]; then
    MODE=plan
  fi
  ((CLASSIFY == 1)) || [[ -n $MODE ]] || usage
  [[ -n $BUNDLE ]] || fail '--bundle ist erforderlich.'
  [[ $BUNDLE == /* && $BUNDLE != */ ]] || fail '--bundle muss ein absoluter Verzeichnispfad sein.'
}

check_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Benötigter Befehl fehlt: $1."
}

check_commands() {
  local command_name
  for command_name in apt-cache apt-get awk dpkg find fuser getent grep groupadd head id install ip mktemp mountpoint paste pgrep python3 sha256sum sleep sort stat systemctl uname useradd wget; do
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

check_venv_capability() {
  local ensurepip_output
  if ensurepip_output=$(python3 -c 'import ensurepip, venv; print(ensurepip.version())' 2>/dev/null) && [[ $ensurepip_output =~ ^[0-9][0-9A-Za-z.+~-]*$ ]]; then
    VENV_AVAILABLE=1
    ENSUREPIP_VERSION=$ensurepip_output
  else
    VENV_AVAILABLE=0
    ENSUREPIP_VERSION='unavailable'
  fi
}

check_apt_candidate() {
  local policy candidate codename
  [[ $VENV_PACKAGE =~ ^python3\.[0-9]+-venv$ ]] || fail "Unsicherer Venv-Paketname: $VENV_PACKAGE."
  policy=$(apt-cache policy "$VENV_PACKAGE" 2>/dev/null) || fail "apt-cache policy konnte $VENV_PACKAGE nicht prüfen."
  candidate=$(awk '$1 == "Candidate:" { print $2; exit }' <<<"$policy")
  [[ $candidate =~ ^[0-9][0-9A-Za-z.+:~_-]*$ && $candidate != '(none)' ]] ||
    fail "Kein installierbarer Candidate für $VENV_PACKAGE verfügbar."
  codename=${VERSION_CODENAME:-}
  [[ $codename == resolute ]] || fail "Ubuntu-Codename ist für die Paketquellenprüfung nicht eindeutig: ${codename:-unbekannt}."
  APT_INSTALLED=$(awk '$1 == "Installed:" { print $2; exit }' <<<"$policy")
  [[ -n $APT_INSTALLED && $APT_INSTALLED != '(none)' ]] &&
    [[ $APT_INSTALLED =~ ^[0-9][0-9A-Za-z.+:~_-]*$ ]] || [[ $APT_INSTALLED == '(none)' ]] ||
    fail "Unerwarteter Installationsstatus für $VENV_PACKAGE: ${APT_INSTALLED:-unbekannt}."
  grep -Eq "^[[:space:]]*[0-9]+[[:space:]]+https?://[^[:space:]]+[[:space:]]+${codename}([[:space:]/-]|$)" <<<"$policy" ||
    fail "Candidate $candidate für $VENV_PACKAGE stammt nicht nachweisbar aus einer konfigurierten Ubuntu-$EXPECTED_UBUNTU-Quelle."
  APT_CANDIDATE=$candidate
}

check_architecture_and_python() {
  local architecture python_version major minor
  architecture=$(uname -m 2>/dev/null) || fail 'Architektur konnte nicht ermittelt werden.'
  [[ $architecture == amd64 || $architecture == x86_64 ]] || fail "Nicht unterstützte Architektur: $architecture."
  python_version=$(python3 -c 'import sys; print("%d.%d.%d" % sys.version_info[:3])') ||
    fail 'Python 3 konnte nicht ausgeführt werden.'
  [[ $python_version =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] || fail "Unerwartete Python-Versionsausgabe: $python_version."
  major=${BASH_REMATCH[1]}
  minor=${BASH_REMATCH[2]}
  ((major > 3 || (major == 3 && minor >= 12))) || fail "Python $python_version ist zu alt; mindestens 3.12 ist erforderlich."
  PYTHON_VERSION="$python_version"
  VENV_PACKAGE="python${major}.${minor}-venv"
  check_venv_capability
  if ((VENV_AVAILABLE == 0)); then
    check_apt_candidate
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
  mapfile -t wheels < <(find "$BUNDLE" -mindepth 1 -maxdepth 1 -type f -name 'ralf_bootstrap-0.3.0-*.whl' -printf '%f\n' | sort)
  ((${#wheels[@]} == 1)) || fail 'Bundle muss genau ein Wheel ralf_bootstrap-0.3.0-*.whl enthalten.'
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
    if message.get('Name') != 'ralf-bootstrap' or message.get('Version') != '0.3.0':
        raise SystemExit('Wheel-Metadaten enthalten nicht ralf-bootstrap 0.3.0.')
PY
}

sanitize_diagnostic_value() {
  local value=${1//$'\n'/ }
  value=${value//$'\r'/ }
  value=${value//$'\t'/ }
  printf '%.240s' "$value"
}

record_failed_predicate() {
  CLASSIFICATION_FAILURES+=("$1")
  CLASSIFICATION_OBSERVED+=("$(sanitize_diagnostic_value "$2")")
  CLASSIFICATION_EXPECTED+=("$(sanitize_diagnostic_value "$3")")
}

predicate_equals() {
  local name=$1 observed=$2 expected_value=$3
  if [[ $observed == "$expected_value" ]]; then
    return 0
  fi
  record_failed_predicate "$name" "$observed" "$expected_value"
  return 1
}

emit_classification_diagnostics() {
  local index
  printf 'state=%s\n' "$INSTALL_STATE" >&2
  for index in "${!CLASSIFICATION_FAILURES[@]}"; do
    printf 'failed_check=%s\n' "${CLASSIFICATION_FAILURES[$index]}" >&2
    printf 'observed=%s\n' "${CLASSIFICATION_OBSERVED[$index]}" >&2
    printf 'expected=%s\n' "${CLASSIFICATION_EXPECTED[$index]}" >&2
  done
  if [[ $SERVICE_ACTIVE_STATE != unknown || $SERVICE_SUB_STATE != unknown ]]; then
    printf 'observed_load_state=%s\n' "$SERVICE_LOAD_STATE" >&2
    printf 'observed_unit_file_state=%s\n' "$SERVICE_UNIT_FILE_STATE" >&2
    printf 'observed_active_state=%s\n' "$SERVICE_ACTIVE_STATE" >&2
    printf 'observed_sub_state=%s\n' "$SERVICE_SUB_STATE" >&2
    printf 'observed_result=%s\n' "$SERVICE_RESULT" >&2
    printf 'observed_exec_main_code=%s\n' "$SERVICE_EXEC_MAIN_CODE" >&2
    printf 'observed_exec_main_status=%s\n' "$SERVICE_EXEC_MAIN_STATUS" >&2
    printf 'expected_active_state=inactive\n' >&2
    printf 'expected_sub_state=dead\n' >&2
  fi
}

probe_bundle() {
  local -a actual expected wheels
  [[ -d $BUNDLE ]] || return 1
  mapfile -t wheels < <(find "$BUNDLE" -mindepth 1 -maxdepth 1 -type f -name 'ralf_bootstrap-0.3.0-*.whl' -printf '%f\n' | sort)
  ((${#wheels[@]} == 1)) || return 1
  WHEEL=${wheels[0]}
  expected=("$WHEEL" SHA256SUMS config.toml ralf-bootstrap.service ralf-bootstrap-status-install.sh runtime.lock)
  mapfile -t actual < <(find "$BUNDLE" -mindepth 1 -maxdepth 1 -type f -printf '%f\n' | sort)
  mapfile -t expected < <(printf '%s\n' "${expected[@]}" | sort)
  [[ ${actual[*]} == "${expected[*]}" ]] || return 1
  (cd "$BUNDLE" && sha256sum -c SHA256SUMS >/dev/null 2>&1) || return 1
  python3 - "$BUNDLE/$WHEEL" <<'PY' >/dev/null 2>&1
import email
import sys
import zipfile

with zipfile.ZipFile(sys.argv[1]) as archive:
    names = [name for name in archive.namelist() if name.endswith('.dist-info/METADATA')]
    if len(names) != 1:
        raise SystemExit(1)
    metadata = email.message_from_bytes(archive.read(names[0]))
    if metadata.get('Name') != 'ralf-bootstrap' or metadata.get('Version') != '0.3.0':
        raise SystemExit(1)
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
  local user_uid
  IFS=: read -r _ _ user_uid user_gid _ user_home user_shell <<<"$passwd_line"
  IFS=: read -r _ _ group_gid _ <<<"$group_line"
  [[ $user_uid =~ ^[0-9]+$ && $user_uid -ge 100 && $user_uid -lt 1000 && $user_gid =~ ^[0-9]+$ && $user_gid -ge 100 && $user_gid -lt 1000 ]] ||
    fail 'Vorhandener ralf-bootstrap-Benutzer oder dessen Gruppe ist kein Systemkonto.'
  [[ $user_home == "$EXPECTED_HOME" && $user_shell == "$EXPECTED_SHELL" && $user_gid == "$group_gid" ]] ||
    fail 'Vorhandener ralf-bootstrap-Benutzer entspricht nicht dem Sollzustand.'
  groups=$(id -Gn "$EXPECTED_USER")
  [[ $groups == "$EXPECTED_GROUP" ]] || fail 'ralf-bootstrap besitzt unerwartete Gruppenzugehörigkeiten.'
  if getent group sudo >/dev/null 2>&1 && getent group sudo | grep -Eq '(^|,)'"$EXPECTED_USER"'(,|$)'; then
    fail 'ralf-bootstrap besitzt unerlaubte sudo-Gruppenzugehörigkeit.'
  fi
}

user_group_is_valid() {
  local passwd_line group_line user_uid user_gid group_gid user_home user_shell groups
  passwd_line=$(getent passwd "$EXPECTED_USER" 2>/dev/null || true)
  group_line=$(getent group "$EXPECTED_GROUP" 2>/dev/null || true)
  [[ -n $passwd_line && -n $group_line ]] || return 1
  IFS=: read -r _ _ user_uid user_gid _ user_home user_shell <<<"$passwd_line"
  IFS=: read -r _ _ group_gid _ <<<"$group_line"
  [[ $user_uid =~ ^[0-9]+$ && $user_uid -ge 100 && $user_uid -lt 1000 ]] || return 1
  [[ $user_gid =~ ^[0-9]+$ && $user_gid == "$group_gid" ]] || return 1
  [[ $user_home == "$EXPECTED_HOME" && $user_shell == "$EXPECTED_SHELL" ]] || return 1
  groups=$(id -Gn "$EXPECTED_USER" 2>/dev/null || true)
  [[ $groups == "$EXPECTED_GROUP" ]] || return 1
  if getent group sudo >/dev/null 2>&1 && getent group sudo | grep -Eq '(^|,)'"$EXPECTED_USER"'(,|$)'; then
    return 1
  fi
}

service_snapshot_is_transient() {
  case $SERVICE_ACTIVE_STATE in
    activating|deactivating|reloading) return 0 ;;
  esac
  case $SERVICE_SUB_STATE in
    start|start-pre|start-post|stop|stop-sigterm|stop-sigkill|auto-restart) return 0 ;;
  esac
  return 1
}

read_service_snapshot() {
  local output line key value attempt
  for attempt in 1 2 3; do
    SERVICE_LOAD_STATE='unknown'
    SERVICE_UNIT_FILE_STATE='unknown'
    SERVICE_ACTIVE_STATE='unknown'
    SERVICE_SUB_STATE='unknown'
    SERVICE_RESULT='unknown'
    SERVICE_EXEC_MAIN_CODE='unknown'
    SERVICE_EXEC_MAIN_STATUS='unknown'
    output=$(systemctl show ralf-bootstrap.service \
      -p LoadState -p UnitFileState -p ActiveState -p SubState -p Result \
      -p ExecMainCode -p ExecMainStatus --no-pager 2>/dev/null || true)
    while IFS= read -r line; do
      key=${line%%=*}
      value=${line#*=}
      case $key in
        LoadState) SERVICE_LOAD_STATE=$value ;;
        UnitFileState) SERVICE_UNIT_FILE_STATE=$value ;;
        ActiveState) SERVICE_ACTIVE_STATE=$value ;;
        SubState) SERVICE_SUB_STATE=$value ;;
        Result) SERVICE_RESULT=$value ;;
        ExecMainCode) SERVICE_EXEC_MAIN_CODE=$value ;;
        ExecMainStatus) SERVICE_EXEC_MAIN_STATUS=$value ;;
      esac
    done <<<"$output"
    if ! service_snapshot_is_transient || ((attempt == 3)); then
      return 0
    fi
    sleep 0.2
  done
}

find_recoverable_temp() {
  local -a candidates
  mapfile -t candidates < <(find "$bootstrap_root" -mindepth 1 -maxdepth 1 -type d -name '.venv-build.*' -printf '%p\n' | sort)
  ((${#candidates[@]} == 1)) || return 1
  RECOVERABLE_TEMP_VENV=${candidates[0]}
}

check_recoverable_shape() {
  local actual
  [[ -d $bootstrap_root ]] || return 1
  actual=$(stat -c '%U:%G|%a' "$bootstrap_root" 2>/dev/null) || return 1
  [[ $actual == "root:$EXPECTED_GROUP|750" ]] || return 1
  [[ -n $(getent passwd "$EXPECTED_USER" || true) && -n $(getent group "$EXPECTED_GROUP" || true) ]] || return 1
  user_group_is_valid || return 1
  find_recoverable_temp || return 1
  while IFS= read -r actual; do
    [[ $actual == "$RECOVERABLE_TEMP_VENV" ]] || return 1
  done < <(find "$bootstrap_root" -mindepth 1 -maxdepth 1 -print)
  ! find "$bootstrap_root" -mindepth 1 -maxdepth 1 -type d -name '.app-build.*' -print -quit | grep -q . || return 1
  for path in "$app_dir" "$venv_dir" "$version_file" "$config_dir" "$state_dir" "$unit_file" "$state_db"; do
    [[ ! -e $path ]] || return 1
  done
  [[ ! -e $unit_file ]] || return 1
  ! systemctl is-enabled ralf-bootstrap.service >/dev/null 2>&1 || return 1
  ! systemctl is-active ralf-bootstrap.service >/dev/null 2>&1 || return 1
  port_is_free || return 1
}

permissions_match() {
  local metadata path owner mode actual
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
    IFS='|' read -r path owner mode <<<"$metadata"
    [[ -e $path ]] || return 1
    actual=$(stat -c '%U:%G|%a' "$path" 2>/dev/null) || return 1
    [[ $actual == "$owner|$mode" ]] || return 1
  done
  [[ ! -e $state_db ]]
}

check_installed_package_versions() {
  "$venv_dir/bin/python" - "$BUNDLE/runtime.lock" <<'PY'
import importlib.metadata
import sys

expected = {}
for line in open(sys.argv[1], encoding='utf-8'):
    line = line.strip()
    if line and not line.startswith('#'):
        name, version = line.split('==', 1)
        expected[name] = version
expected['ralf-bootstrap'] = '0.3.0'
for name, version in expected.items():
    if importlib.metadata.version(name) != version:
        raise SystemExit(1)
PY
}

check_installed_artifact_hashes() {
  local artifact
  for artifact in "$WHEEL" runtime.lock; do
    [[ $(sha256sum "$app_dir/$artifact" | cut -d' ' -f1) == $(sha256sum "$BUNDLE/$artifact" | cut -d' ' -f1) ]] || return 1
  done
  [[ $(sha256sum "$config_file" | cut -d' ' -f1) == $(sha256sum "$BUNDLE/config.toml" | cut -d' ' -f1) ]] || return 1
  [[ $(sha256sum "$unit_file" | cut -d' ' -f1) == $(sha256sum "$BUNDLE/ralf-bootstrap.service" | cut -d' ' -f1) ]]
}

venv_shebang_is_moved() {
  local shebang path moved=0
  [[ -x $venv_dir/bin/gunicorn && ! -L $venv_dir ]] || return 1
  while IFS= read -r path; do
    [[ $path == "$venv_dir/bin/python" ]] && continue
    shebang=$(head -n 1 "$path" 2>/dev/null || true)
    case $shebang in
      '#!'"$venv_dir"'/bin/python'*)
        [[ -x ${shebang#\#!} ]] || return 1
        ;;
      '#!'*/.venv-build.*/bin/python*)
        [[ $shebang =~ ^#!/opt/ralf/bootstrap/\.venv-build\.[^/]+/bin/python[0-9.]*$ ]] || return 1
        [[ ! -e ${shebang#\#!} ]] || return 1
        moved=1
        ;;
      '#!'*) return 1 ;;
    esac
  done < <(find "$venv_dir/bin" -maxdepth 1 -type f -perm /111 -print)
  ((moved == 1))
}

check_moved_venv_shape() {
  [[ -d $bootstrap_root && ! -L $venv_dir ]] || return 1
  [[ -f $venv_dir/pyvenv.cfg && -x $venv_dir/bin/python ]] || return 1
  [[ $(cat "$version_file" 2>/dev/null) == "$EXPECTED_VERSION" ]] || return 1
  permissions_match || return 1
  check_installed_artifact_hashes || return 1
  check_installed_package_versions || return 1
  [[ ! -e $install_marker && ! -e $repair_marker ]] || return 1
  ! find "$bootstrap_root" -mindepth 1 -maxdepth 1 \( -name '.venv-build.*' -o -name '.app-build.*' \) -print -quit | grep -q . || return 1
  venv_shebang_is_moved || return 1
  read_service_snapshot
  [[ $SERVICE_UNIT_FILE_STATE == enabled && $SERVICE_EXEC_MAIN_STATUS == 203 ]] || return 1
  ! pgrep -x gunicorn >/dev/null 2>&1 || return 1
  port_is_free || return 1
  return 0
}

repair_marker_is_valid() {
  [[ -f $repair_marker && ! -L $repair_marker ]] || return 1
  [[ $(stat -c '%U:%G|%a' "$repair_marker" 2>/dev/null) == "root:$EXPECTED_GROUP|640" ]] || return 1
  [[ $(cat "$repair_marker" 2>/dev/null) == $'bootstrap_version=0.3.0\noperation=repair-venv' ]]
}

repair_permissions_match() {
  local metadata path owner mode actual
  for metadata in \
    "$bootstrap_root|root:$EXPECTED_GROUP|750" \
    "$app_dir|root:$EXPECTED_GROUP|750" \
    "$venv_dir|root:root|755" \
    "$app_dir/$WHEEL|root:$EXPECTED_GROUP|640" \
    "$app_dir/runtime.lock|root:$EXPECTED_GROUP|640" \
    "$version_file|root:$EXPECTED_GROUP|640" \
    "$config_dir|root:$EXPECTED_GROUP|750" \
    "$config_file|root:$EXPECTED_GROUP|640" \
    "$state_dir|$EXPECTED_USER:$EXPECTED_GROUP|750" \
    "$unit_file|root:root|644"; do
    IFS='|' read -r path owner mode <<<"$metadata"
    [[ -e $path ]] || return 1
    actual=$(stat -c '%U:%G|%a' "$path" 2>/dev/null) || return 1
    [[ $actual == "$owner|$mode" ]] || return 1
  done
  [[ ! -e $state_db ]]
}

probe_venv_semantics() {
  [[ -x $venv_dir/bin/python ]] || return 1
  "$venv_dir/bin/python" - "$venv_dir" <<'PY' >/dev/null 2>&1
import os
import pathlib
import sys
import sysconfig

expected = pathlib.Path(sys.argv[1]).resolve()
launcher = expected / 'bin' / 'python'
assert pathlib.Path(sys.prefix).resolve() == expected
assert pathlib.Path(sys.exec_prefix).resolve() == expected
assert sys.prefix != sys.base_prefix
assert sys.exec_prefix != sys.base_exec_prefix
assert sys.executable
assert launcher.is_file() and os.access(launcher, os.X_OK)
assert os.path.samefile(sys.executable, launcher)
assert pathlib.Path(sysconfig.get_paths()['purelib']).resolve().is_relative_to(expected)
PY
}

gunicorn_shebang_is_final() {
  [[ -x $venv_dir/bin/gunicorn ]] || return 1
  [[ $(head -n 1 "$venv_dir/bin/gunicorn" 2>/dev/null) == "#!$venv_dir/bin/python" ]] || return 1
  [[ -x $venv_dir/bin/python ]]
}

venv_build_references_are_absent() {
  ! find "$venv_dir/bin" -maxdepth 1 -type f -perm /111 -exec grep -IlF '.venv-build.' {} + 2>/dev/null | grep -q .
}

evaluate_repair_validation_state() {
  local valid=1 observed entries expected_entries package_state artifact_state process_state port_state
  CLASSIFICATION_FAILURES=()
  CLASSIFICATION_OBSERVED=()
  CLASSIFICATION_EXPECTED=()

  observed=$([[ -d $bootstrap_root && ! -L $bootstrap_root ]] && printf valid || printf invalid)
  predicate_equals bootstrap_root_valid "$observed" valid || valid=0
  observed=$(user_group_is_valid && printf valid || printf invalid)
  predicate_equals user_valid "$observed" valid || valid=0
  predicate_equals group_valid "$observed" valid || valid=0
  observed=$([[ -d $app_dir ]] && printf present || printf absent)
  predicate_equals app_present "$observed" present || valid=0
  observed=$(cat "$version_file" 2>/dev/null || printf absent)
  predicate_equals version_valid "$observed" "$EXPECTED_VERSION" || valid=0
  observed=$([[ -d $config_dir && -f $config_file ]] && printf present || printf absent)
  predicate_equals config_present "$observed" present || valid=0
  observed=$([[ -d $state_dir ]] && printf present || printf absent)
  predicate_equals state_directory_present "$observed" present || valid=0
  observed=$([[ -f $unit_file ]] && printf present || printf absent)
  predicate_equals unit_present "$observed" present || valid=0
  observed=$([[ ! -e $state_db ]] && printf absent || printf present)
  predicate_equals state_db_absent "$observed" absent || valid=0
  observed=$(repair_marker_is_valid && printf valid || printf invalid)
  predicate_equals repair_marker_valid "$observed" valid || valid=0
  observed=$([[ ! -e $install_marker ]] && printf absent || printf present)
  predicate_equals install_marker_absent "$observed" absent || valid=0

  entries=$(find "$bootstrap_root" -mindepth 1 -maxdepth 1 -printf '%f\n' 2>/dev/null | sort | paste -sd, -)
  expected_entries=$(printf '%s\n' .venv-repair-in-progress VERSION app venv | sort | paste -sd, -)
  predicate_equals bootstrap_entries_valid "$entries" "$expected_entries" || valid=0
  observed=$(! find "$bootstrap_root" -mindepth 1 -maxdepth 1 \( -name '.venv-build.*' -o -name '.app-build.*' -o -name '.venv-install-in-progress' \) -print -quit 2>/dev/null | grep -q . && printf absent || printf present)
  predicate_equals temporary_directories_absent "$observed" absent || valid=0

  observed=$([[ -d $venv_dir && ! -L $venv_dir ]] && ! mountpoint -q "$venv_dir" && printf valid || printf invalid)
  predicate_equals venv_directory_valid "$observed" valid || valid=0
  observed=$(stat -c '%U:%G|%a' "$venv_dir" 2>/dev/null || printf 'absent|absent')
  predicate_equals venv_owner_is_intermediate "${observed%|*}" root:root || valid=0
  predicate_equals venv_mode_is_intermediate "${observed##*|}" 755 || valid=0
  observed=$([[ -f $venv_dir/pyvenv.cfg ]] && printf present || printf absent)
  predicate_equals pyvenv_cfg_present "$observed" present || valid=0
  observed=$(probe_venv_semantics && printf valid || printf invalid)
  predicate_equals venv_semantics_valid "$observed" valid || valid=0
  package_state=$(check_installed_package_versions >/dev/null 2>&1 && printf valid || printf invalid)
  predicate_equals package_versions_valid "$package_state" valid || valid=0
  observed=$(gunicorn_shebang_is_final && printf valid || printf invalid)
  predicate_equals gunicorn_shebang_valid "$observed" valid || valid=0
  observed=$(venv_build_references_are_absent && printf absent || printf present)
  predicate_equals build_path_references_absent "$observed" absent || valid=0
  artifact_state=$(check_installed_artifact_hashes >/dev/null 2>&1 && printf valid || printf invalid)
  predicate_equals installed_artifacts_match_bundle "$artifact_state" valid || valid=0
  observed=$(repair_permissions_match && printf valid || printf invalid)
  predicate_equals installed_permissions_valid "$observed" valid || valid=0

  read_service_snapshot
  predicate_equals unit_enabled "$SERVICE_UNIT_FILE_STATE" enabled || valid=0
  predicate_equals service_inactive_dead "$SERVICE_ACTIVE_STATE/$SERVICE_SUB_STATE" inactive/dead || valid=0
  process_state=$(pgrep -x gunicorn >/dev/null 2>&1 && printf present || printf absent)
  predicate_equals gunicorn_process_absent "$process_state" absent || valid=0
  port_state=$(port_is_free && printf free || printf occupied)
  predicate_equals loopback_port_free "$port_state" free || valid=0

  ((valid == 1))
}

check_direct_venv_failure_shape() {
  [[ -f $install_marker && -d $venv_dir && ! -L $venv_dir ]] || return 1
  [[ $(stat -c '%U:%G|%a' "$bootstrap_root" 2>/dev/null) == "root:$EXPECTED_GROUP|750" ]] || return 1
  [[ -f $venv_dir/pyvenv.cfg ]] || return 1
  while IFS= read -r actual; do
    [[ $actual == "$install_marker" || $actual == "$venv_dir" ]] || return 1
  done < <(find "$bootstrap_root" -mindepth 1 -maxdepth 1 -print)
  [[ ! -e $app_dir && ! -e $config_dir && ! -e $state_dir && ! -e $unit_file && ! -e $state_db ]] || return 1
  ! find "$bootstrap_root" -mindepth 1 -maxdepth 1 -name '.app-build.*' -print -quit | grep -q . || return 1
  port_is_free || return 1
}

check_install_state() {
  local -a markers existing
  local absent_identity=0
  markers=(
    "$app_dir" "$app_dir/$WHEEL" "$app_dir/runtime.lock"
    "$venv_dir" "$venv_dir/bin/gunicorn" "$version_file"
    "$config_dir" "$config_file" "$state_dir" "$unit_file"
  )
  existing=()
  for marker in "${markers[@]}"; do
    [[ -e $marker ]] && existing+=("$marker")
  done
  if [[ -z $(getent passwd "$EXPECTED_USER" 2>/dev/null || true) && -z $(getent group "$EXPECTED_GROUP" 2>/dev/null || true) && ! -e $unit_file ]]; then
    absent_identity=1
  fi
  if [[ ! -e $bootstrap_root && ${#existing[@]} == 0 && $absent_identity == 1 ]]; then
    INSTALL_STATE='absent'
    CLASSIFICATION_FAILURES=()
    CLASSIFICATION_OBSERVED=()
    CLASSIFICATION_EXPECTED=()
  elif [[ -e $repair_marker ]]; then
    if evaluate_repair_validation_state; then
      INSTALL_STATE='recoverable_venv_repair_validation_failure'
    else
      INSTALL_STATE='partial'
    fi
  elif check_moved_venv_shape; then
    INSTALL_STATE='recoverable_moved_venv_exec_failure'
  elif ((${#existing[@]} == ${#markers[@]})) && [[ ! -e $state_db ]]; then
    INSTALL_STATE='complete'
  elif check_recoverable_shape; then
    INSTALL_STATE='recoverable_venv_failure'
  elif check_direct_venv_failure_shape; then
    INSTALL_STATE='recoverable_direct_venv_failure'
  else
    INSTALL_STATE='partial'
  fi
  if [[ $INSTALL_STATE == complete ]]; then
    if ! check_installed_artifact_hashes; then
      INSTALL_STATE='partial'
      record_failed_predicate installed_artifacts_match_bundle invalid valid
    fi
  fi
  if [[ $INSTALL_STATE == partial && ${#CLASSIFICATION_FAILURES[@]} == 0 ]]; then
    record_failed_predicate recognized_installation_shape unmatched 'one allowed state'
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

run_classification() {
  local command_name
  for command_name in find getent grep head id mountpoint paste pgrep python3 sha256sum sleep sort stat systemctl; do
    command -v "$command_name" >/dev/null 2>&1 || {
      INSTALL_STATE='partial'
      record_failed_predicate classification_command "$command_name:missing" present
      printf 'RALF_BOOTSTRAP_STATE_V1=%s\n' "$INSTALL_STATE"
      emit_classification_diagnostics
      return 0
    }
  done
  if ! probe_bundle; then
    INSTALL_STATE='partial'
    record_failed_predicate bundle_valid invalid valid
  else
    check_install_state
  fi
  case $INSTALL_STATE in
    absent|complete|recoverable_venv_failure|recoverable_direct_venv_failure|recoverable_moved_venv_exec_failure|recoverable_venv_repair_validation_failure|partial) ;;
    *)
      INSTALL_STATE='partial'
      record_failed_predicate state_value unknown 'allowed state'
      ;;
  esac
  printf 'RALF_BOOTSTRAP_STATE_V1=%s\n' "$INSTALL_STATE"
  if [[ $INSTALL_STATE == partial ]]; then
    emit_classification_diagnostics
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
  if [[ $INSTALL_STATE == partial ]]; then
    emit_classification_diagnostics
    fail 'Eine teilweise oder abweichende Bootstrap-Installation ist nicht automatisch behandelbar.'
  fi
  check_port
  if [[ $RESUME == 1 && $INSTALL_STATE != recoverable_venv_failure && $INSTALL_STATE != recoverable_direct_venv_failure ]]; then
    fail "Resume ist nur für einen bekannten Venv-Teilzustand zulässig; erkannt: $INSTALL_STATE."
  fi
  if [[ $REPAIR_VENV == 1 && $INSTALL_STATE != recoverable_moved_venv_exec_failure ]]; then
    [[ $INSTALL_STATE == recoverable_venv_repair_validation_failure ]] ||
      fail "--repair-venv ist nur für recoverable_moved_venv_exec_failure oder recoverable_venv_repair_validation_failure zulässig; erkannt: $INSTALL_STATE."
  fi
  if [[ $MODE == apply && $RESUME == 0 && $REPAIR_VENV == 0 && $INSTALL_STATE == recoverable_venv_failure ]]; then
    fail 'Der erkannte recoverable_venv_failure darf nicht mit --apply fortgesetzt werden; verwende ausdrücklich --resume --apply.'
  fi
  if [[ $MODE == apply && $RESUME == 0 && $REPAIR_VENV == 0 && $INSTALL_STATE == recoverable_direct_venv_failure ]]; then
    fail 'Der erkannte recoverable_direct_venv_failure darf nicht mit --apply fortgesetzt werden; verwende ausdrücklich --resume --apply.'
  fi
  if [[ $REPAIR_VENV == 0 && $INSTALL_STATE == recoverable_moved_venv_exec_failure ]]; then
    fail 'Der erkannte recoverable_moved_venv_exec_failure darf nicht mit --apply oder --resume fortgesetzt werden; verwende ausdrücklich --repair-venv.'
  fi
  if [[ $REPAIR_VENV == 0 && $INSTALL_STATE == recoverable_venv_repair_validation_failure ]]; then
    fail 'Der erkannte recoverable_venv_repair_validation_failure darf nicht mit --apply oder --resume fortgesetzt werden; verwende ausdrücklich --repair-venv.'
  fi
  PREFLIGHT_COMPLETED=1
}

print_plan() {
  printf 'Plan erfolgreich; Modus: %s; es wurden noch keine Installationsmutationen ausgeführt.\n' "$MODE"
  printf '  Bundle: %s\n' "$BUNDLE"
  printf '  Wheel: %s (Version %s)\n' "$WHEEL" "$EXPECTED_VERSION"
  printf '  Installationszustand: %s\n' "$INSTALL_STATE"
  printf '  Python: %s; venv: %s; ensurepip: %s\n' "$PYTHON_VERSION" "$([[ $VENV_AVAILABLE == 1 ]] && printf verfügbar || printf fehlt)" "$ENSUREPIP_VERSION"
  if ((VENV_AVAILABLE == 0)); then
    printf '  Benötigtes Paket: %s; installiert: %s; Candidate: %s\n' "$VENV_PACKAGE" "$APT_INSTALLED" "${APT_CANDIDATE:-unbekannt}"
  fi
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
  if [[ $INSTALL_STATE == recoverable_moved_venv_exec_failure ]]; then
    printf '  Reparaturzustand: recoverable_moved_venv_exec_failure; Gunicorn-Shebang: %s\n' "$(head -n 1 "$venv_dir/bin/gunicorn" 2>/dev/null || true)"
    printf '  Reparatur: Dienst stoppen, ausschließlich %s neu und direkt erstellen; kein Shebang-Umschreiben.\n' "$venv_dir"
    printf '  Exakte Reihenfolge: stop/warten, Venv validieren und entfernen, Marker anlegen, Venv direkt erstellen, Lock+Wheel installieren, Pfade prüfen, Marker entfernen, reset-failed, einmalig starten, Endpunkte prüfen.\n'
    printf '  Nicht geplant: Benutzer/Gruppe, python3.14-venv, apt update/upgrade, Übertragung, enable, Containerneustart, state.db oder Rollback.\n'
  elif [[ $INSTALL_STATE == recoverable_venv_repair_validation_failure ]]; then
    printf '  Reparaturzustand: recoverable_venv_repair_validation_failure; direkte Venv und Pakete bleiben erhalten.\n'
    printf '  Fortsetzung: nur Venv-Rechte finalisieren, Unit prüfen, reset-failed und genau einmal starten; keine Venv-Löschung oder Neuerstellung.\n'
    printf '  Nicht geplant: Paket-/Wheel-Installation, Übertragung, Benutzer/Gruppe, enable, Shebang-Umschreibung, Containerneustart oder state.db.\n'
  elif [[ $INSTALL_STATE == recoverable_venv_failure ]]; then
    printf '  Fehlgeschlagenes temporäres Venv: %s\n' "$RECOVERABLE_TEMP_VENV"
    printf '  Resume-Bereinigung: ausschließlich dieses Verzeichnis; keine Benutzer-, Gruppen- oder Bundle-Löschung.\n'
  elif [[ $INSTALL_STATE == recoverable_direct_venv_failure ]]; then
    printf '  Unterbrochene direkte Venv: %s; Resume entfernt ausschließlich diesen validierten Zielpfad.\n' "$venv_dir"
  elif [[ $RESUME == 0 && $REPAIR_VENV == 0 ]]; then
    printf '  Normaler --apply behandelt recoverable_venv_failure nicht; verwende --resume --apply.\n'
  fi
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

validate_final_venv() {
  local python_path=$venv_dir/bin/python shebang
  [[ -x $python_path && -f $venv_dir/pyvenv.cfg && ! -L $venv_dir ]] || fail 'Die endgültige Python-Umgebung ist unvollständig oder ein Symlink.'
  probe_venv_semantics || fail 'Die Venv-Interpreterprüfung ist fehlgeschlagen.'
  "$python_path" -m pip --version | grep -Fq "$venv_dir" || fail 'Pip verweist nicht auf die endgültige Venv.'
  "$python_path" -c 'import gunicorn, ralf_bootstrap' || fail 'Gunicorn oder ralf_bootstrap ist nicht importierbar.'
  shebang=$(head -n 1 "$venv_dir/bin/gunicorn" 2>/dev/null) || fail 'Gunicorn-Skript fehlt.'
  case $shebang in
    "#!$venv_dir/bin/python") ;;
    *) fail "Gunicorn-Shebang verweist nicht auf den endgültigen Interpreter: $shebang" ;;
  esac
  [[ -x ${shebang#\#!} ]] || fail 'Der im Gunicorn-Shebang referenzierte Interpreter fehlt.'
  if find "$venv_dir/bin" -maxdepth 1 -type f -perm /111 -exec grep -IlF '.venv-build.' {} + 2>/dev/null | grep -q .; then
    fail 'Ein ausführbares Venv-Skript verweist noch auf einen verschobenen .venv-build.-Pfad.'
  fi
}

install_runtime_contents() {
  local python_path=$venv_dir/bin/python
  [[ -x $python_path ]] || fail 'Die endgültige Python-Umgebung enthält kein ausführbares Python.'
  "$python_path" -m pip --version >/dev/null 2>&1 || fail 'Pip ist in der endgültigen Python-Umgebung nicht funktionsfähig.'
  LAST_MUTATION='gepinnten Runtime-Abhängigkeiten installieren'
  "$python_path" -m pip install --disable-pip-version-check --no-input --index-url "$INDEX_URL" --requirement "$BUNDLE/runtime.lock" ||
    fail 'Installation der gepinnten Runtime-Abhängigkeiten ist fehlgeschlagen.'
  LAST_MUTATION='geprüftes RALF-Wheel installieren'
  "$python_path" -m pip install --disable-pip-version-check --no-input --no-deps "$BUNDLE/$WHEEL" ||
    fail 'Installation des geprüften RALF-Wheels ist fehlgeschlagen.'
  "$python_path" - "$BUNDLE/runtime.lock" <<'PY' || fail 'Installierte Paketversionen entsprechen nicht dem Runtime-Lock.'
import importlib.metadata
import sys

lock_path = sys.argv[1]
expected = {}
for line in open(lock_path, encoding='utf-8'):
    line = line.strip()
    if line and not line.startswith('#'):
        name, version = line.split('==', 1)
        expected[name] = version
expected['ralf-bootstrap'] = '0.3.0'
for name, version in expected.items():
    actual = importlib.metadata.version(name)
    if actual != version:
        raise SystemExit(f'{name}: erwartet {version}, gefunden {actual}')
PY
  validate_final_venv
}

install_runtime() {
  if [[ $RESUME == 1 ]]; then
    if [[ $INSTALL_STATE == recoverable_venv_failure ]]; then
      [[ $RECOVERABLE_TEMP_VENV == "$bootstrap_root"/.venv-build.* && -d $RECOVERABLE_TEMP_VENV ]] ||
        fail 'Das validierte fehlgeschlagene Venv-Verzeichnis ist nicht mehr eindeutig vorhanden.'
      LAST_MUTATION="validiertes fehlgeschlagenes Venv entfernen: $RECOVERABLE_TEMP_VENV"
      rm -rf -- "$RECOVERABLE_TEMP_VENV"
      TEMP_VENV_REMOVED=1
    elif [[ $INSTALL_STATE == recoverable_direct_venv_failure ]]; then
      [[ $venv_dir == "$(target_path '/opt/ralf/bootstrap/venv')" && -d $venv_dir && ! -L $venv_dir ]] || fail 'Direkte Venv ist nicht sicher für den Resume freigegeben.'
      LAST_MUTATION="validierte direkte Venv entfernen: $venv_dir"
      rm -rf -- "$venv_dir"
      TEMP_VENV_REMOVED=1
    fi
  fi
  if ((VENV_AVAILABLE == 0)); then
    LAST_MUTATION="Paket $VENV_PACKAGE installieren"
    DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y "$VENV_PACKAGE" || fail "Die notwendige venv-Paketinstallation ist fehlgeschlagen: $VENV_PACKAGE."
    APT_INSTALL_SUCCEEDED=1
    check_venv_capability
    ((VENV_AVAILABLE == 1)) || fail 'ensurepip ist nach der venv-Paketinstallation weiterhin nicht verfügbar.'
  fi
  LAST_MUTATION='direkte Python-Umgebung am endgültigen Zielpfad erstellen'
  python3 -m venv "$venv_dir" || fail 'Python-Umgebung am endgültigen Zielpfad konnte nicht erstellt werden.'
  TEMP_VENV_PATH=$venv_dir
  NEW_VENV_CREATED=1
  install_runtime_contents
}

write_marker() {
  local path=$1 kind=$2
  install -m 0640 -o root -g "$EXPECTED_GROUP" /dev/null "$path"
  printf 'bootstrap_version=%s\noperation=%s\n' "$EXPECTED_VERSION" "$kind" >"$path"
  chown root:"$EXPECTED_GROUP" "$path"
  chmod 0640 "$path"
}

wait_for_service_stop() {
  local attempt=0
  while ((attempt < 30)); do
    ((attempt += 1))
    if ! systemctl is-active --quiet ralf-bootstrap.service; then
      return 0
    fi
    sleep 1
  done
  fail 'ralf-bootstrap.service blieb nach dem Stoppen aktiv.'
}

repair_venv_apply() {
  check_preflight
  [[ $INSTALL_STATE == recoverable_moved_venv_exec_failure ]] || fail "Reparaturzustand ist nicht mehr gültig: $INSTALL_STATE."
  LAST_MUTATION='ralf-bootstrap.service kontrolliert stoppen'
  systemctl stop ralf-bootstrap.service || fail 'ralf-bootstrap.service konnte nicht gestoppt werden.'
  wait_for_service_stop
  ! pgrep -x gunicorn >/dev/null 2>&1 || fail 'Ein Gunicorn-Prozess läuft nach dem Stoppen weiterhin.'
  port_is_free || fail '127.0.0.1:8080 ist nach dem Stoppen weiterhin belegt.'
  check_moved_venv_shape || fail 'Der nachgewiesene verschobene Venv-Zustand hat sich vor der Entfernung verändert.'
  write_marker "$repair_marker" 'repair-venv'
  LAST_MUTATION="ausschließlich endgültige fehlerhafte Venv entfernen: $venv_dir"
  [[ $venv_dir == "$(target_path '/opt/ralf/bootstrap/venv')" && -d $venv_dir && ! -L $venv_dir ]] || fail 'Der Venv-Pfad ist nicht exakt für die Reparatur freigegeben.'
  if mountpoint -q "$venv_dir"; then
    fail 'Die Venv ist ein Mountpoint und darf nicht entfernt werden.'
  fi
  rm -rf -- "$venv_dir"
  TEMP_VENV_REMOVED=1
  LAST_MUTATION='Python-Umgebung direkt am endgültigen Reparaturpfad erstellen'
  python3 -m venv "$venv_dir" || fail 'Die neue Venv konnte am endgültigen Pfad nicht erstellt werden.'
  TEMP_VENV_PATH=$venv_dir
  NEW_VENV_CREATED=1
  install_runtime_contents
  chown -R root:"$EXPECTED_GROUP" "$venv_dir"
  chmod 0750 "$venv_dir"
  validate_final_venv
  if command -v systemd-analyze >/dev/null 2>&1; then
    systemd-analyze verify "$unit_file" || fail 'Die vorhandene systemd-Unit ist ungültig.'
  fi
  LAST_MUTATION='systemd-Fehlerzustand zurücksetzen'
  systemctl reset-failed ralf-bootstrap.service
  LAST_MUTATION='ralf-bootstrap.service einmalig starten'
  systemctl start ralf-bootstrap.service || fail 'ralf-bootstrap.service konnte nach der Venv-Reparatur nicht gestartet werden.'
  check_installed_permissions
  validate_service
  LAST_MUTATION='Reparaturmarkierung nach vollständiger Validierung entfernen'
  rm -f -- "$repair_marker"
  printf 'Venv-Reparatur erfolgreich; die Umgebung wurde direkt unter %s erstellt.\n' "$venv_dir"
}

repair_validation_apply() {
  check_preflight
  [[ $INSTALL_STATE == recoverable_venv_repair_validation_failure ]] ||
    fail "Fortsetzungszustand ist nicht mehr gültig: $INSTALL_STATE."
  ! systemctl is-active --quiet ralf-bootstrap.service || fail 'ralf-bootstrap.service ist unerwartet aktiv.'
  ! pgrep -x gunicorn >/dev/null 2>&1 || fail 'Ein Gunicorn-Prozess läuft unerwartet.'
  port_is_free || fail '127.0.0.1:8080 ist unerwartet belegt.'
  validate_final_venv
  LAST_MUTATION='Eigentümer der vorhandenen Venv rekursiv finalisieren'
  chown -R root:"$EXPECTED_GROUP" "$venv_dir" || fail 'Eigentümer der vorhandenen Venv konnten nicht finalisiert werden.'
  LAST_MUTATION='Modus der vorhandenen Venv-Wurzel finalisieren'
  chmod 0750 "$venv_dir" || fail 'Modus der vorhandenen Venv konnte nicht finalisiert werden.'
  check_installed_permissions
  if command -v systemd-analyze >/dev/null 2>&1; then
    systemd-analyze verify "$unit_file" || fail 'Die vorhandene systemd-Unit ist ungültig.'
  fi
  LAST_MUTATION='systemd-Fehlerzustand zurücksetzen'
  systemctl reset-failed ralf-bootstrap.service
  LAST_MUTATION='ralf-bootstrap.service einmalig starten'
  systemctl start ralf-bootstrap.service || fail 'ralf-bootstrap.service konnte nicht gestartet werden.'
  check_installed_permissions
  validate_service
  LAST_MUTATION='Reparaturmarkierung nach vollständiger Validierung entfernen'
  rm -f -- "$repair_marker"
  printf 'Venv-Reparaturfortsetzung erfolgreich; die vorhandene Venv wurde nicht neu erstellt.\n'
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

probe_service_http() {
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
            if payload['bootstrap']['version'] != '0.3.0':
                raise SystemExit('Status meldet falsche Bootstrap-Version.')
            if payload['bootstrap']['sqlite']['status'] != 'not_initialized':
                raise SystemExit('SQLite ist nicht im erwarteten not_initialized-Zustand.')
            if any(item['status'] != 'not_configured' for item in payload['components'][1:]):
                raise SystemExit('Modellkomponenten sind nicht not_configured.')
PY
}

validate_service() {
  local attempt=0
  systemctl is-enabled ralf-bootstrap.service >/dev/null || fail 'ralf-bootstrap.service ist nicht aktiviert.'
  while ((attempt < 20)); do
    ((attempt += 1))
    if systemctl is-active ralf-bootstrap.service >/dev/null 2>&1 && probe_service_http; then
      return 0
    fi
    sleep 1
  done
  fail 'ralf-bootstrap.service wurde nicht rechtzeitig aktiv oder die lokalen Endpunkte waren nicht erreichbar.'
}

main() {
  parse_args "$@"
  if ((CLASSIFY == 1)); then
    run_classification
    exit 0
  fi
  check_preflight
  print_plan
  if [[ $MODE == plan ]]; then
    exit 0
  fi
  if ((REPAIR_VENV == 1)); then
    if [[ $INSTALL_STATE == recoverable_venv_repair_validation_failure ]]; then
      repair_validation_apply
    else
      repair_venv_apply
    fi
    exit 0
  fi
  if [[ $INSTALL_STATE == complete ]]; then
    [[ $RESUME == 0 ]] || fail 'Eine vollständige Installation darf nicht im Resume-Modus erneut verarbeitet werden.'
    check_installed_permissions
    validate_service
    printf 'Bereits vollständige Installation erkannt; es wurden keine Dateien ersetzt.\n'
    exit 0
  fi
  if [[ $INSTALL_STATE == absent ]]; then
    ensure_user_group
    install -d -m 0750 -o root -g "$EXPECTED_GROUP" "$bootstrap_root"
  fi
  if [[ ! -e $install_marker ]]; then
    write_marker "$install_marker" 'install-venv'
  fi
  install_runtime
  install_files
  check_installed_permissions
  activate_service
  validate_service
  rm -f -- "$install_marker"
  printf 'Installation erfolgreich; ralf-bootstrap läuft als %s auf 127.0.0.1:8080.\n' "$EXPECTED_USER"
}

main "$@"
