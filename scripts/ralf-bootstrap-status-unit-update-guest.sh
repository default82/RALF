#!/usr/bin/env bash

set -Eeuo pipefail

readonly EXPECTED_VERSION='0.1.0'
readonly EXPECTED_USER='ralf-bootstrap'
readonly EXPECTED_GROUP='ralf-bootstrap'
readonly EXPECTED_SOURCE_SHA256='8f5b30c7d9335824dfabb19cab5b338337860a45e785a6985370da9b8f6f48d7'
readonly ROOT_PREFIX="${RALF_UNIT_UPDATE_ROOT:-}"

MODE=''
BUNDLE=''
TARGET_SHA256=''
UPDATE_STATE='unit_update_conflict'
LAST_DIAGNOSTIC='keine'
LAST_MUTATION='keine'
UNIT_REPLACED=0
DAEMON_RELOADED=0
RESTART_EXECUTED=0
INITIAL_MAIN_PID=''
SERVICE_UID=''
SERVICE_GID=''
JOURNAL_CURSOR=''
BEFORE_SNAPSHOT=''

target_path() {
  printf '%s%s' "$ROOT_PREFIX" "$1"
}

BOOTSTRAP_ROOT=$(target_path '/opt/ralf/bootstrap'); readonly BOOTSTRAP_ROOT
APP_DIR=$(target_path '/opt/ralf/bootstrap/app'); readonly APP_DIR
VENV_DIR=$(target_path '/opt/ralf/bootstrap/venv'); readonly VENV_DIR
VERSION_FILE=$(target_path '/opt/ralf/bootstrap/VERSION'); readonly VERSION_FILE
CONFIG_FILE=$(target_path '/etc/ralf/bootstrap/config.toml'); readonly CONFIG_FILE
STATE_DIR=$(target_path '/var/lib/ralf/bootstrap'); readonly STATE_DIR
STATE_DB=$(target_path '/var/lib/ralf/bootstrap/state.db'); readonly STATE_DB
UNIT_DIR=$(target_path '/etc/systemd/system'); readonly UNIT_DIR
UNIT_FILE=$(target_path '/etc/systemd/system/ralf-bootstrap.service'); readonly UNIT_FILE
DROPIN_DIR=$(target_path '/etc/systemd/system/ralf-bootstrap.service.d'); readonly DROPIN_DIR
INSTALL_MARKER=$(target_path '/opt/ralf/bootstrap/.venv-install-in-progress'); readonly INSTALL_MARKER
REPAIR_MARKER=$(target_path '/opt/ralf/bootstrap/.venv-repair-in-progress'); readonly REPAIR_MARKER
OS_RELEASE=$(target_path '/etc/os-release'); readonly OS_RELEASE

usage() {
  cat >&2 <<'EOF'
Aufruf:
  ralf-bootstrap-status-unit-update-guest.sh --classify --target-sha256 <SHA256>
  ralf-bootstrap-status-unit-update-guest.sh --plan --target-sha256 <SHA256>
  ralf-bootstrap-status-unit-update-guest.sh --apply --target-sha256 <SHA256> --bundle /run/ralf-bootstrap-unit-update
EOF
  exit 2
}

diagnose() {
  LAST_DIAGNOSTIC=$1
  printf 'diagnostic=%s\n' "$1" >&2
}

failure_state() {
  local unit_hash='unavailable' service_state='unavailable' main_pid='unavailable' port_state='unknown' http_state='unknown' current_snapshot
  [[ -f $UNIT_FILE ]] && unit_hash=$(sha256sum "$UNIT_FILE" 2>/dev/null | awk '{print $1}' || printf unavailable)
  service_state=$(systemctl show ralf-bootstrap.service -p ActiveState -p SubState -p Result -p ExecMainStatus -p MainPID --no-pager 2>/dev/null | paste -sd, - || printf unavailable)
  main_pid=$(systemctl show ralf-bootstrap.service -p MainPID --value --no-pager 2>/dev/null || printf unavailable)
  if listener_is_loopback_only >/dev/null 2>&1; then port_state='loopback-only'; else port_state='free-or-conflict'; fi
  if http_probe no >/dev/null 2>&1; then http_state='HTTP-200'; else http_state='nicht-erreichbar-oder-ungueltig'; fi
  printf '  Zustand: %s\n' "$UPDATE_STATE" >&2
  printf '  Letzte Diagnose: %s\n' "$LAST_DIAGNOSTIC" >&2
  printf '  Letzter mutierender Schritt: %s\n' "$LAST_MUTATION" >&2
  printf '  Unit ersetzt: %s; daemon-reload: %s; Restart: %s\n' "$UNIT_REPLACED" "$DAEMON_RELOADED" "$RESTART_EXECUTED" >&2
  printf '  Aktueller Unit-Hash: %s\n' "$unit_hash" >&2
  printf '  Dienst: %s; MainPID: %s; Port: %s; HTTP: %s\n' "$service_state" "$main_pid" "$port_state" "$http_state" >&2
  if [[ -n $BEFORE_SNAPSHOT ]]; then
    current_snapshot=$(application_snapshot 2>/dev/null || true)
    printf '  Anwendungssnapshot unverändert: %s\n' "$([[ -n $current_snapshot && $current_snapshot == "$BEFORE_SNAPSHOT" ]] && printf ja || printf nein)" >&2
  fi
  if [[ $RESTART_EXECUTED == 1 ]]; then
    printf '  Neue Journaleinträge (höchstens 30):\n' >&2
    if [[ -n $JOURNAL_CURSOR ]]; then
      journalctl -u ralf-bootstrap.service --after-cursor "$JOURNAL_CURSOR" --no-pager -n 30 2>/dev/null >&2 || true
    else
      journalctl -u ralf-bootstrap.service --since '-2 minutes' --no-pager -n 30 2>/dev/null >&2 || true
    fi
  fi
  printf '  Bundle: %s (%s)\n' "${BUNDLE:-nicht angegeben}" "$([[ -n $BUNDLE && -d $BUNDLE ]] && printf vorhanden || printf nicht-vorhanden)" >&2
}

fail() {
  printf 'Fehler: %s\n' "$1" >&2
  failure_state
  printf '  Kein automatischer Rollback, zweiter Restart oder zweiter Updateversuch.\n' >&2
  exit 1
}

select_mode() {
  [[ -z $MODE ]] || fail 'Es darf genau ein Ausführungsmodus angegeben werden.'
  MODE=$1
}

parse_args() {
  while (($#)); do
    case $1 in
      --classify) select_mode classify; shift ;;
      --plan) select_mode plan; shift ;;
      --apply) select_mode apply; shift ;;
      --target-sha256)
        (($# >= 2)) || fail '--target-sha256 benötigt einen Wert.'
        TARGET_SHA256=$2
        shift 2
        ;;
      --bundle)
        (($# >= 2)) || fail '--bundle benötigt einen Wert.'
        BUNDLE=$2
        shift 2
        ;;
      --help) usage ;;
      *) fail "Unbekannte Option: $1" ;;
    esac
  done
  [[ -n $MODE && $TARGET_SHA256 =~ ^[0-9a-f]{64}$ ]] || usage
  if [[ $MODE == apply ]]; then
    [[ $BUNDLE == /* && $BUNDLE != */ ]] || fail '--apply benötigt einen absoluten Bundle-Pfad ohne abschließenden Schrägstrich.'
  elif [[ -n $BUNDLE ]]; then
    fail '--bundle ist ausschließlich mit --apply zulässig.'
  fi
}

metadata_is() {
  local path=$1 expected=$2
  [[ -e $path ]] || { diagnose "missing:$path"; return 1; }
  local actual
  actual=$(stat -c '%F|%U:%G|%a' "$path" 2>/dev/null) || { diagnose "stat-failed:$path"; return 1; }
  [[ $actual == "$expected" ]] || { diagnose "metadata:$path:$actual:expected:$expected"; return 1; }
}

user_group_valid() {
  local passwd_line group_line user_name group_name uid gid group_gid home shell groups
  passwd_line=$(getent passwd "$EXPECTED_USER" 2>/dev/null || true)
  group_line=$(getent group "$EXPECTED_GROUP" 2>/dev/null || true)
  [[ -n $passwd_line && -n $group_line ]] || { diagnose 'identity:missing'; return 1; }
  IFS=: read -r user_name _ uid gid _ home shell <<<"$passwd_line"
  IFS=: read -r group_name _ group_gid _ <<<"$group_line"
  [[ $user_name == "$EXPECTED_USER" && $group_name == "$EXPECTED_GROUP" ]] || { diagnose "identity:names:$user_name:$group_name"; return 1; }
  [[ $uid =~ ^[0-9]+$ && $gid =~ ^[0-9]+$ && $group_gid =~ ^[0-9]+$ ]] || { diagnose "identity:non-numeric:$uid:$gid:$group_gid"; return 1; }
  [[ $uid -ge 100 && $uid -lt 1000 && $gid == "$group_gid" ]] || { diagnose 'identity:not-system-account'; return 1; }
  [[ $home == /nonexistent && $shell == /usr/sbin/nologin ]] || { diagnose "identity:home-or-shell:$home:$shell"; return 1; }
  groups=$(id -Gn "$EXPECTED_USER" 2>/dev/null || true)
  [[ $groups == "$EXPECTED_GROUP" ]] || { diagnose "identity:groups:$groups"; return 1; }
  if getent group sudo 2>/dev/null | grep -Eq '(^|,)'"$EXPECTED_USER"'(,|$)'; then
    diagnose 'identity:sudo-membership'
    return 1
  fi
  SERVICE_UID=$uid
  SERVICE_GID=$gid
}

os_and_package_state_valid() {
  [[ -r $OS_RELEASE ]] || { diagnose 'os-release:missing'; return 1; }
  local id version process lock audit
  id=$(awk -F= '$1 == "ID" {gsub(/^"|"$/, "", $2); print $2}' "$OS_RELEASE")
  version=$(awk -F= '$1 == "VERSION_ID" {gsub(/^"|"$/, "", $2); print $2}' "$OS_RELEASE")
  [[ $id == ubuntu && $version == 26.04 ]] || { diagnose "os:$id:$version"; return 1; }
  audit=$(dpkg --audit 2>/dev/null) || { diagnose 'dpkg-audit:failed'; return 1; }
  [[ -z $audit ]] || { diagnose 'dpkg-audit:not-empty'; return 1; }
  for process in apt apt-get dpkg unattended-upgrade; do
    ! pgrep -x "$process" >/dev/null 2>&1 || { diagnose "package-process:$process"; return 1; }
  done
  for lock in /var/lib/dpkg/lock /var/lib/dpkg/lock-frontend /var/lib/apt/lists/lock /var/cache/apt/archives/lock; do
    lock=$(target_path "$lock")
    if [[ -e $lock ]] && fuser -s "$lock" >/dev/null 2>&1; then
      diagnose "package-lock:$lock"
      return 1
    fi
  done
}

venv_and_packages_valid() {
  [[ -d $VENV_DIR && ! -L $VENV_DIR && -f $VENV_DIR/pyvenv.cfg && -x $VENV_DIR/bin/python ]] || { diagnose 'venv:shape'; return 1; }
  ! mountpoint -q "$VENV_DIR" || { diagnose 'venv:mountpoint'; return 1; }
  "$VENV_DIR/bin/python" - "$VENV_DIR" "$APP_DIR/runtime.lock" <<'PY' >/dev/null 2>&1 || { diagnose 'venv:semantics-or-packages'; return 1; }
import importlib.metadata
import os
from pathlib import Path
import sys
import sysconfig

expected = Path(sys.argv[1]).resolve()
launcher = expected / "bin" / "python"
assert Path(sys.prefix).resolve() == expected
assert Path(sys.exec_prefix).resolve() == expected
assert sys.prefix != sys.base_prefix
assert sys.exec_prefix != sys.base_exec_prefix
assert os.path.samefile(sys.executable, launcher)
assert Path(sysconfig.get_paths()["purelib"]).resolve().is_relative_to(expected)
versions = {}
for line in Path(sys.argv[2]).read_text(encoding="utf-8").splitlines():
    line = line.strip()
    if line and not line.startswith("#"):
        name, version = line.split("==", 1)
        versions[name] = version
versions["ralf-bootstrap"] = "0.1.0"
for name, version in versions.items():
    assert importlib.metadata.version(name) == version
assert importlib.metadata.version("Flask") == "3.1.3"
assert importlib.metadata.version("Gunicorn") == "26.0.0"
PY
  [[ $(head -n 1 "$VENV_DIR/bin/gunicorn" 2>/dev/null) == "#!$VENV_DIR/bin/python" ]] || { diagnose 'venv:gunicorn-shebang'; return 1; }
}

files_and_permissions_valid() {
  local wheel_count wheel
  [[ $(cat "$VERSION_FILE" 2>/dev/null) == "$EXPECTED_VERSION" ]] || { diagnose 'version:not-0.1.0'; return 1; }
  [[ -f $UNIT_FILE && ! -L $UNIT_FILE ]] || { diagnose 'unit:not-regular-file'; return 1; }
  [[ ! -e $DROPIN_DIR ]] || { diagnose 'unit:dropin-directory-present'; return 1; }
  metadata_is "$BOOTSTRAP_ROOT" "directory|root:$EXPECTED_GROUP|750" || return 1
  metadata_is "$APP_DIR" "directory|root:$EXPECTED_GROUP|750" || return 1
  metadata_is "$VENV_DIR" "directory|root:$EXPECTED_GROUP|750" || return 1
  metadata_is "$VERSION_FILE" "regular file|root:$EXPECTED_GROUP|640" || return 1
  metadata_is "$(dirname "$CONFIG_FILE")" "directory|root:$EXPECTED_GROUP|750" || return 1
  metadata_is "$CONFIG_FILE" "regular file|root:$EXPECTED_GROUP|640" || return 1
  metadata_is "$STATE_DIR" "directory|$EXPECTED_USER:$EXPECTED_GROUP|750" || return 1
  metadata_is "$UNIT_FILE" 'regular file|root:root|644' || return 1
  wheel_count=$(find "$APP_DIR" -mindepth 1 -maxdepth 1 -type f -name 'ralf_bootstrap-0.1.0-*.whl' | wc -l)
  [[ $wheel_count == 1 && -f $APP_DIR/runtime.lock ]] || { diagnose "app-artifacts:wheel-count:$wheel_count"; return 1; }
  wheel=$(find "$APP_DIR" -mindepth 1 -maxdepth 1 -type f -name 'ralf_bootstrap-0.1.0-*.whl' -print -quit)
  metadata_is "$wheel" "regular file|root:$EXPECTED_GROUP|640" || return 1
  metadata_is "$APP_DIR/runtime.lock" "regular file|root:$EXPECTED_GROUP|640" || return 1
  local venv_path venv_owner
  while IFS= read -r -d '' venv_path; do
    venv_owner=$(stat -c '%U:%G' "$venv_path" 2>/dev/null) || { diagnose "venv:stat-failed:$venv_path"; return 1; }
    [[ $venv_owner == "root:$EXPECTED_GROUP" ]] || { diagnose "venv:owner:$venv_path:$venv_owner"; return 1; }
  done < <(find "$VENV_DIR" -print0)
  [[ ! -e $STATE_DB && ! -e $INSTALL_MARKER && ! -e $REPAIR_MARKER ]] || { diagnose 'unexpected-state-db-or-marker'; return 1; }
  ! find "$BOOTSTRAP_ROOT" -mindepth 1 -maxdepth 1 \( -name '.venv-build.*' -o -name '.app-build.*' -o -name '.venv-install-in-progress' -o -name '.venv-repair-in-progress' \) -print -quit | grep -q . || { diagnose 'temporary-build-path'; return 1; }
}

read_service_snapshot() {
  systemctl show ralf-bootstrap.service \
    -p FragmentPath -p DropInPaths -p LoadState -p UnitFileState -p ActiveState -p SubState \
    -p Result -p ExecMainStatus -p NRestarts -p MainPID --no-pager 2>/dev/null
}

snapshot_value() {
  local snapshot=$1 key=$2
  awk -F= -v key="$key" '$1 == key {sub(/^[^=]*=/, ""); print; exit}' <<<"$snapshot"
}

service_snapshot_valid() {
  local snapshot fragment dropins load enabled active sub result exec_status restarts main_pid
  snapshot=$(read_service_snapshot) || { diagnose 'systemd:snapshot-failed'; return 1; }
  fragment=$(snapshot_value "$snapshot" FragmentPath)
  dropins=$(snapshot_value "$snapshot" DropInPaths)
  load=$(snapshot_value "$snapshot" LoadState)
  enabled=$(snapshot_value "$snapshot" UnitFileState)
  active=$(snapshot_value "$snapshot" ActiveState)
  sub=$(snapshot_value "$snapshot" SubState)
  result=$(snapshot_value "$snapshot" Result)
  exec_status=$(snapshot_value "$snapshot" ExecMainStatus)
  restarts=$(snapshot_value "$snapshot" NRestarts)
  main_pid=$(snapshot_value "$snapshot" MainPID)
  [[ $fragment == "$UNIT_FILE" && -z $dropins ]] || { diagnose "systemd:fragment-or-dropins:$fragment:$dropins"; return 1; }
  [[ $load == loaded && $enabled == enabled && $active == active && $sub == running && $result == success && $exec_status == 0 && $restarts == 0 ]] || {
    diagnose "systemd:state:$load:$enabled:$active:$sub:$result:$exec_status:$restarts"
    return 1
  }
  [[ $main_pid =~ ^[1-9][0-9]*$ ]] || { diagnose "systemd:mainpid:$main_pid"; return 1; }
  INITIAL_MAIN_PID=$main_pid
}

gunicorn_processes_valid() {
  local snapshot tree_rows tree_count master_rows master_count worker_rows worker_count
  local pid ppid uid gid comm
  [[ $SERVICE_UID =~ ^[0-9]+$ && $SERVICE_GID =~ ^[0-9]+$ ]] || { diagnose 'gunicorn:service-identity-unavailable'; return 1; }
  snapshot=$(LC_ALL=C ps -ww -eo pid=,ppid=,uid=,gid=,comm= 2>/dev/null) || {
    diagnose 'gunicorn:process-snapshot-failed'
    return 1
  }
  tree_rows=$(awk -v main_pid="$INITIAL_MAIN_PID" '$1 == main_pid || $2 == main_pid {print}' <<<"$snapshot")
  tree_count=$(awk 'NF {count++} END {print count+0}' <<<"$tree_rows")
  [[ $tree_count == 2 ]] || { diagnose "gunicorn:service-tree-count:$tree_count:expected:2"; return 1; }

  master_rows=$(awk -v main_pid="$INITIAL_MAIN_PID" '$1 == main_pid {print}' <<<"$tree_rows")
  master_count=$(awk 'NF {count++} END {print count+0}' <<<"$master_rows")
  [[ $master_count == 1 ]] || { diagnose "gunicorn:master-count:$master_count:expected:1"; return 1; }
  read -r pid ppid uid gid comm <<<"$master_rows"
  [[ $uid == "$SERVICE_UID" && $gid == "$SERVICE_GID" && $comm == gunicorn ]] || {
    diagnose "gunicorn:master-identity:$pid:$uid:$gid:$comm"
    return 1
  }

  worker_rows=$(awk -v main_pid="$INITIAL_MAIN_PID" '$1 != main_pid && $2 == main_pid {print}' <<<"$tree_rows")
  worker_count=$(awk 'NF {count++} END {print count+0}' <<<"$worker_rows")
  [[ $worker_count == 1 ]] || { diagnose "gunicorn:worker-count:$worker_count:expected:1"; return 1; }
  read -r pid ppid uid gid comm <<<"$worker_rows"
  [[ $ppid == "$INITIAL_MAIN_PID" && $uid == "$SERVICE_UID" && $gid == "$SERVICE_GID" && $comm == gunicorn ]] || {
    diagnose "gunicorn:worker-identity:$pid:$ppid:$uid:$gid:$comm"
    return 1
  }
}

main_process_args() {
  local pid=$1
  LC_ALL=C ps -ww -p "$pid" -o args= 2>/dev/null
}

main_process_arguments_valid() {
  local pid=$1 args token index
  local no_control=0 workers=0 bind=0 app=0
  local -a argv=()
  args=$(main_process_args "$pid") || { diagnose 'gunicorn:main-args-snapshot-failed'; return 1; }
  read -r -a argv <<<"$args"
  for ((index = 0; index < ${#argv[@]}; index += 1)); do
    token=${argv[index]}
    [[ $token == --no-control-socket ]] && ((no_control += 1))
    [[ $token == ralf_bootstrap.wsgi:app ]] && ((app += 1))
    if [[ $token == --workers && ${argv[index + 1]:-} == 1 ]]; then ((workers += 1)); fi
    if [[ $token == --bind && ${argv[index + 1]:-} == 127.0.0.1:8080 ]]; then ((bind += 1)); fi
  done
  [[ $no_control == 1 ]] || { diagnose "gunicorn:main-args:no-control-socket:$no_control:expected:1"; return 1; }
  [[ $workers == 1 ]] || { diagnose "gunicorn:main-args:workers:$workers:expected:1"; return 1; }
  [[ $bind == 1 ]] || { diagnose "gunicorn:main-args:bind:$bind:expected:1"; return 1; }
  [[ $app == 1 ]] || { diagnose "gunicorn:main-args:wsgi:$app:expected:1"; return 1; }
}

listener_is_loopback_only() {
  local listeners
  listeners=$(ss -H -ltn 'sport = :8080' 2>/dev/null | awk '{print $4}' | sort -u)
  [[ $listeners == '127.0.0.1:8080' ]]
}

http_probe() {
  local require_configured=$1
  python3 - "$require_configured" <<'PY'
import json
import sys
from urllib.request import Request, urlopen

require_configured = sys.argv[1] == "yes"
for path in ("/", "/healthz", "/api/v1/status"):
    with urlopen(Request("http://127.0.0.1:8080" + path), timeout=5) as response:
        body = response.read()
        assert response.status == 200
        expected_headers = {
            "X-Content-Type-Options": "nosniff",
            "X-Frame-Options": "DENY",
            "Referrer-Policy": "no-referrer",
            "Cache-Control": "no-store",
        }
        for name, value in expected_headers.items():
            assert response.headers.get(name) == value
        assert response.headers.get("Content-Security-Policy")
        if path == "/api/v1/status":
            payload = json.loads(body)
            assert payload["bootstrap"]["version"] == "0.1.0"
            assert payload["bootstrap"]["sqlite"]["status"] == "not_initialized"
            components = {item["id"]: item["status"] for item in payload["components"]}
            for component in ("model-runtime", "model", "model-webui", "privileged-installer"):
                assert components[component] == "not_configured"
            if require_configured:
                assert payload["network"]["status"] == "configured"
                assert payload["network"]["default_route"] is True
                assert payload["network"]["ipv4_addresses"]
                warnings = payload.get("warnings", [])
                assert "IPv4-Adresse oder Default-Route fehlt." not in warnings
                assert not any("Statusabfrage meldete einen Fehler: ip" in warning for warning in warnings)
PY
}

complete_installation_valid() {
  LAST_DIAGNOSTIC='keine'
  os_and_package_state_valid || return 1
  [[ $(systemctl is-system-running 2>/dev/null) == running ]] || { diagnose 'systemd:not-running'; return 1; }
  user_group_valid || return 1
  files_and_permissions_valid || return 1
  venv_and_packages_valid || return 1
  service_snapshot_valid || return 1
  gunicorn_processes_valid || return 1
  listener_is_loopback_only || { diagnose 'listener:not-loopback-only'; return 1; }
  http_probe no >/dev/null 2>&1 || { diagnose 'http:pre-update'; return 1; }
}

validate_target_unit() {
  local unit=$1
  python3 - "$unit" "$EXPECTED_SOURCE_SHA256" "$TARGET_SHA256" <<'PY'
from pathlib import Path
import hashlib
import re
import sys

path = Path(sys.argv[1])
source_hash = sys.argv[2]
target_hash = sys.argv[3]
if not path.is_file() or path.is_symlink():
    raise SystemExit("target unit is not a regular file")
data = path.read_bytes()
if hashlib.sha256(data).hexdigest() != target_hash:
    raise SystemExit("target unit hash mismatch")
control_line = b"  --no-control-socket \\\n"
old_families = b"RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6\n"
new_families = b"RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6 AF_NETLINK\n"
if data.count(control_line) != 1 or data.count(new_families) != 1:
    raise SystemExit("required unit delta is not exact")
if b"--control-socket" in data or b"AF_PACKET" in data or b"CAP_NET_ADMIN" in data or b"CAP_NET_RAW" in data:
    raise SystemExit("forbidden network or control-socket setting")
for exact in (
    b"User=ralf-bootstrap\n",
    b"Group=ralf-bootstrap\n",
    b"WorkingDirectory=/opt/ralf/bootstrap/app\n",
    b"Environment=RALF_BOOTSTRAP_CONFIG=/etc/ralf/bootstrap/config.toml\n",
    b"ExecStart=/opt/ralf/bootstrap/venv/bin/gunicorn \\\n",
    b"  --workers 1 \\\n",
    b"  --bind 127.0.0.1:8080 \\\n",
    b"  ralf_bootstrap.wsgi:app\n",
    b"NoNewPrivileges=true\n",
    b"ProtectSystem=strict\n",
    b"PrivateDevices=true\n",
    b"ProtectHome=true\n",
    b"CapabilityBoundingSet=\n",
    b"AmbientCapabilities=\n",
    b"WantedBy=multi-user.target\n",
):
    if data.count(exact) != 1:
        raise SystemExit(f"required directive missing or duplicated: {exact!r}")
for forbidden in (b"0.0.0.0", b"RuntimeDirectory=", b"Environment=HOME=", b"sudo", b"ExecStartPre=", b"ExecStartPost="):
    if forbidden in data:
        raise SystemExit(f"forbidden unit content: {forbidden!r}")
if re.search(rb"^AmbientCapabilities=\S+", data, re.MULTILINE) or re.search(rb"^CapabilityBoundingSet=\S+", data, re.MULTILINE):
    raise SystemExit("capability set is not empty")
reconstructed = data.replace(control_line, b"", 1).replace(new_families, old_families, 1)
if hashlib.sha256(reconstructed).hexdigest() != source_hash:
    raise SystemExit("target contains changes beyond the approved semantic delta")
PY
}

classify_state() {
  UPDATE_STATE='unit_update_conflict'
  if ! complete_installation_valid; then
    return 0
  fi
  local installed_hash
  installed_hash=$(sha256sum "$UNIT_FILE" | awk '{print $1}')
  if [[ $installed_hash == "$EXPECTED_SOURCE_SHA256" ]]; then
    UPDATE_STATE='unit_update_required'
  elif [[ $installed_hash == "$TARGET_SHA256" ]]; then
    if http_probe yes >/dev/null 2>&1 && main_process_arguments_valid "$INITIAL_MAIN_PID"; then
      UPDATE_STATE='unit_already_current'
    else
      diagnose 'current-unit-runtime:not-healthy'
    fi
  else
    diagnose "unit-hash:$installed_hash"
  fi
}

emit_classification() {
  classify_state
  printf 'RALF_BOOTSTRAP_UNIT_STATE_V1=%s\n' "$UPDATE_STATE"
  if [[ $UPDATE_STATE == unit_update_conflict ]]; then
    printf 'state=unit_update_conflict\nfailed_check=%s\n' "$LAST_DIAGNOSTIC" >&2
  fi
}

validate_bundle() {
  [[ -d $BUNDLE && ! -L $BUNDLE ]] || fail 'Updatebundle fehlt oder ist ein Symlink.'
  local files manifest_names
  files=$(find "$BUNDLE" -mindepth 1 -maxdepth 1 -type f -printf '%f\n' | sort | paste -sd, -)
  [[ $files == 'SHA256SUMS,ralf-bootstrap-status-unit-update-guest.sh,ralf-bootstrap.service' ]] || fail "Updatebundle enthält nicht exakt drei Dateien: $files"
  manifest_names=$(awk '{print $2}' "$BUNDLE/SHA256SUMS" | sort | paste -sd, -)
  [[ $manifest_names == 'ralf-bootstrap-status-unit-update-guest.sh,ralf-bootstrap.service' ]] || fail 'SHA256SUMS enthält nicht exakt die beiden Nutzartefakte.'
  (cd "$BUNDLE" && sha256sum -c SHA256SUMS >/dev/null) || fail 'Updatebundle-Prüfsumme ist ungültig.'
  metadata_is "$BUNDLE" 'directory|root:root|700' || fail 'Updatebundle-Verzeichnis besitzt nicht root:root/0700.'
  metadata_is "$BUNDLE/ralf-bootstrap.service" 'regular file|root:root|644' || fail 'Ziel-Unit besitzt im Bundle nicht root:root/0644.'
  validate_target_unit "$BUNDLE/ralf-bootstrap.service" || fail 'Ziel-Unit verletzt Hash- oder Semantikgrenzen.'
}

application_snapshot() {
  local wheel
  wheel=$(find "$APP_DIR" -mindepth 1 -maxdepth 1 -type f -name 'ralf_bootstrap-0.1.0-*.whl' -print -quit)
  [[ -n $wheel ]] || fail 'Installiertes Wheel fehlt.'
  printf 'wheel=%s\n' "$(sha256sum "$wheel" | awk '{print $1}')"
  printf 'lock=%s\n' "$(sha256sum "$APP_DIR/runtime.lock" | awk '{print $1}')"
  printf 'version=%s\n' "$(sha256sum "$VERSION_FILE" | awk '{print $1}')"
  printf 'config=%s\n' "$(sha256sum "$CONFIG_FILE" | awk '{print $1}')"
  printf 'gunicorn=%s\n' "$(sha256sum "$VENV_DIR/bin/gunicorn" | awk '{print $1}')"
  printf 'venv=%s\n' "$("$VENV_DIR/bin/python" -c 'import importlib.metadata as m,sys; print("|".join((sys.prefix,sys.exec_prefix,m.version("Gunicorn"),m.version("ralf-bootstrap"))))')"
  printf 'state_db=%s\n' "$([[ -e $STATE_DB ]] && printf present || printf absent)"
  stat -c 'meta=%n|%U:%G|%a' "$BOOTSTRAP_ROOT" "$APP_DIR" "$VENV_DIR" "$VERSION_FILE" "$(dirname "$CONFIG_FILE")" "$CONFIG_FILE" "$STATE_DIR"
}

verify_target_before_mutation() {
  validate_bundle
  [[ -x $VENV_DIR/bin/gunicorn ]] || fail 'Produktiver Gunicorn-Pfad ist nicht ausführbar.'
  "$VENV_DIR/bin/python" -c 'import ralf_bootstrap.wsgi' >/dev/null 2>&1 || fail 'WSGI-Einstiegspunkt ist nicht importierbar.'
  systemd-analyze verify "$BUNDLE/ralf-bootstrap.service" >/dev/null || fail 'systemd-analyze lehnt die Ziel-Unit ab.'
}

wait_for_ready() {
  local attempt=0
  while ((attempt < 20)); do
    ((attempt += 1))
    if systemctl is-active --quiet ralf-bootstrap.service && http_probe yes >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  fail 'Dienst oder HTTP-Status wurde nach dem einmaligen Restart nicht rechtzeitig bereit.'
}

new_journal_is_clean() {
  local journal
  if [[ -n $JOURNAL_CURSOR ]]; then
    journal=$(journalctl -u ralf-bootstrap.service --after-cursor "$JOURNAL_CURSOR" --no-pager 2>/dev/null || true)
  else
    journal=$(journalctl -u ralf-bootstrap.service --since '-2 minutes' --no-pager 2>/dev/null || true)
  fi
  ! grep -E 'Control server error|/nonexistent|Read-only file system' <<<"$journal"
}

validate_updated_service() {
  local old_pid=$1 snapshot new_pid unit_text
  complete_installation_valid || fail 'Vollständige Installation ist nach dem Update nicht gesund.'
  snapshot=$(read_service_snapshot)
  new_pid=$(snapshot_value "$snapshot" MainPID)
  [[ $new_pid =~ ^[1-9][0-9]*$ && $new_pid != "$old_pid" ]] || fail "MainPID wurde nicht durch genau den Restart ersetzt: $old_pid -> $new_pid"
  main_process_arguments_valid "$new_pid" || fail "Gunicorn-Prozessargumente sind ungültig: $LAST_DIAGNOSTIC"
  listener_is_loopback_only || fail 'Port 8080 lauscht nicht ausschließlich auf 127.0.0.1.'
  http_probe yes || fail 'HTTP-/Statusvalidierung nach dem Update ist fehlgeschlagen.'
  new_journal_is_clean || fail 'Neue Journaleinträge enthalten weiterhin den Control-Socket-Schreibfehler.'
  unit_text=$(systemctl cat ralf-bootstrap.service 2>/dev/null)
  [[ $(grep -o -- '--no-control-socket' <<<"$unit_text" | wc -l) == 1 ]] || fail 'Geladene Unit enthält --no-control-socket nicht exakt einmal.'
  grep -Fxq 'RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6 AF_NETLINK' <<<"$unit_text" || fail 'Geladene Unit enthält nicht die erwartete Adressfamilienliste.'
  ! grep -Fq 'AF_PACKET' <<<"$unit_text" || fail 'Geladene Unit enthält AF_PACKET.'
  grep -Fxq 'CapabilityBoundingSet=' <<<"$unit_text" || fail 'CapabilityBoundingSet ist nicht leer.'
  grep -Fxq 'AmbientCapabilities=' <<<"$unit_text" || fail 'AmbientCapabilities ist nicht leer.'
  grep -Fxq 'NoNewPrivileges=true' <<<"$unit_text" || fail 'NoNewPrivileges ist nicht wirksam.'
  grep -Fxq 'ProtectSystem=strict' <<<"$unit_text" || fail 'ProtectSystem=strict ist nicht wirksam.'
  grep -Fxq 'PrivateDevices=true' <<<"$unit_text" || fail 'PrivateDevices=true ist nicht wirksam.'
  grep -Fxq 'ProtectHome=true' <<<"$unit_text" || fail 'ProtectHome=true ist nicht wirksam.'
}

print_plan() {
  classify_state
  local installed_hash
  installed_hash=$(sha256sum "$UNIT_FILE" 2>/dev/null | awk '{print $1}' || printf unavailable)
  printf 'RALF Bootstrap Unit-Update-Plan\n'
  printf '  Bootstrap-Version: %s\n' "$(cat "$VERSION_FILE" 2>/dev/null || printf unbekannt)"
  printf '  Installierte Unit: %s\n' "$UNIT_FILE"
  printf '  Installierter Hash: %s\n' "$installed_hash"
  printf '  Ziel-Hash: %s\n' "$TARGET_SHA256"
  printf '  Klassifikation: %s\n' "$UPDATE_STATE"
  printf '  Erlaubte Differenz 1: genau --no-control-socket ergänzen.\n'
  printf '  Erlaubte Differenz 2: RestrictAddressFamilies ausschließlich um AF_NETLINK ergänzen.\n'
  if [[ $UPDATE_STATE == unit_update_required ]]; then
    printf '  Apply: Unit atomar ersetzen; genau ein daemon-reload und genau ein Restart; danach Journal, Loopback, HTTP, Netzwerkstatus und Härtung prüfen.\n'
  elif [[ $UPDATE_STATE == unit_already_current ]]; then
    printf '  Apply: keine Übertragung oder Mutation; aktuellen Zustand ausschließlich read-only bestätigen.\n'
  else
    printf '  Update gesperrt: %s\n' "$LAST_DIAGNOSTIC"
  fi
  printf '  Ausgeschlossen: Anwendung, Wheel, Lock, Venv, Konfiguration, Benutzer, Daten, Pakete, enable, Stop/Start, Containerneustart, Rollback.\n'
}

apply_update() {
  [[ $(id -u) == 0 ]] || fail '--apply muss als root ausgeführt werden.'
  validate_bundle
  classify_state
  if [[ $UPDATE_STATE == unit_already_current ]]; then
    printf 'Unit ist bereits aktuell; keine Mutation ausgeführt.\n'
    return 0
  fi
  [[ $UPDATE_STATE == unit_update_required ]] || fail "Unit-Update ist für den Zustand $UPDATE_STATE nicht zulässig."
  verify_target_before_mutation
  BEFORE_SNAPSHOT=$(application_snapshot)
  local old_pid temp_unit after_snapshot
  old_pid=$INITIAL_MAIN_PID
  temp_unit=$(mktemp "$UNIT_DIR/.ralf-bootstrap.service.update.XXXXXX") || fail 'Temporäre Unit konnte nicht im Zielverzeichnis angelegt werden.'
  LAST_MUTATION="Ziel-Unit in temporäre Datei schreiben: $temp_unit"
  install -m 0644 -o root -g root "$BUNDLE/ralf-bootstrap.service" "$temp_unit" || fail 'Temporäre Ziel-Unit konnte nicht geschrieben werden.'
  metadata_is "$temp_unit" 'regular file|root:root|644' || fail 'Temporäre Ziel-Unit besitzt falsche Metadaten.'
  [[ $(sha256sum "$temp_unit" | awk '{print $1}') == "$TARGET_SHA256" ]] || fail 'Temporäre Ziel-Unit besitzt den falschen Hash.'
  validate_target_unit "$temp_unit" || fail 'Temporäre Ziel-Unit verletzt die Semantikgrenzen.'
  LAST_MUTATION='systemd-Unit atomar ersetzen'
  mv -f -- "$temp_unit" "$UNIT_FILE" || fail 'Atomarer Unit-Austausch ist fehlgeschlagen.'
  UNIT_REPLACED=1
  LAST_MUTATION='systemctl daemon-reload'
  systemctl daemon-reload || fail 'systemctl daemon-reload ist fehlgeschlagen.'
  DAEMON_RELOADED=1
  JOURNAL_CURSOR=$(journalctl -u ralf-bootstrap.service -n 0 --show-cursor --no-pager 2>/dev/null | sed -n 's/^-- cursor: //p' | tail -n 1)
  LAST_MUTATION='systemctl restart ralf-bootstrap.service'
  systemctl restart ralf-bootstrap.service || fail 'Der einmalige Dienstrestart ist fehlgeschlagen.'
  RESTART_EXECUTED=1
  wait_for_ready
  validate_updated_service "$old_pid"
  after_snapshot=$(application_snapshot)
  [[ $after_snapshot == "$BEFORE_SNAPSHOT" ]] || fail 'Anwendungsartefakte, Venv, Konfiguration, Datenzustand oder Zielrechte haben sich verändert.'
  [[ $(sha256sum "$UNIT_FILE" | awk '{print $1}') == "$TARGET_SHA256" ]] || fail 'Installierte Unit besitzt nach dem Update nicht den Ziel-Hash.'
  printf 'Unit-Update erfolgreich; ausschließlich Unit und Dienstprozess wurden geändert.\n'
}

main() {
  parse_args "$@"
  case $MODE in
    classify) emit_classification ;;
    plan)
      print_plan
      [[ $UPDATE_STATE != unit_update_conflict ]] || exit 1
      ;;
    apply) apply_update ;;
  esac
}

main "$@"
