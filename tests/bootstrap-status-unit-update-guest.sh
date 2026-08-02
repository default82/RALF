#!/usr/bin/env bash
# shellcheck disable=SC2016

set -Eeuo pipefail

PROJECT_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
readonly PROJECT_ROOT
readonly SCRIPT="$PROJECT_ROOT/scripts/ralf-bootstrap-status-unit-update-guest.sh"
readonly TARGET_UNIT="$PROJECT_ROOT/deploy/bootstrap-status/ralf-bootstrap.service"
readonly TARGET_SHA='a26c500a7e4180f5fc9145b12ab05c3c7d6d598b0cad5d73bd7f7074fae85378'
TEST_ROOT=$(mktemp -d)
readonly TEST_ROOT
SERVER_PID=''

cleanup() {
  if [[ -n $SERVER_PID ]]; then
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
  find "$TEST_ROOT" -type f -delete
  find "$TEST_ROOT" -type l -delete
  find "$TEST_ROOT" -depth -type d -empty -delete
}
trap cleanup EXIT

make_stub() {
  local path=$1
  shift
  mkdir -p "$(dirname "$path")"
  printf '%s\n' '#!/usr/bin/env bash' 'set -Eeuo pipefail' "$@" >"$path"
  chmod 0755 "$path"
}

make_stubs() {
  local bin=$1 state=$2 root=$3
  mkdir -p "$bin" "$state"
  make_stub "$bin/getent" '
case ${1:-} in
  passwd) printf "%s\n" "ralf-bootstrap:x:${TEST_PASSWD_UID:-999}:${TEST_PASSWD_GID:-988}::/nonexistent:/usr/sbin/nologin" ;;
  group)
    if [[ ${2:-} == sudo ]]; then printf "%s\n" "sudo:x:27:"; else printf "%s\n" "ralf-bootstrap:x:988:"; fi
    ;;
esac'
  make_stub "$bin/id" '
if [[ ${1:-} == -u ]]; then printf "0\n"; elif [[ ${1:-} == -Gn ]]; then printf "ralf-bootstrap\n"; else /usr/bin/id "$@"; fi'
  make_stub "$bin/dpkg" '[[ ${1:-} == --audit ]]'
  make_stub "$bin/pgrep" 'exit 1'
  make_stub "$bin/fuser" 'exit 1'
  make_stub "$bin/mountpoint" 'exit 1'
  make_stub "$bin/ss" 'printf "%s\n" "LISTEN 0 2048 127.0.0.1:8080 0.0.0.0:*"'
  make_stub "$bin/ps" '
pid=$(cat "$TEST_STATE/main-pid")
args="/opt/ralf/bootstrap/venv/bin/gunicorn --workers 1 --bind 127.0.0.1:8080"
if grep -Fq -- "--no-control-socket" "$TEST_ROOT_PATH/etc/systemd/system/ralf-bootstrap.service"; then args="$args --no-control-socket"; fi
printf "ps" >>"$TEST_LOG"; printf " %q" "$@" >>"$TEST_LOG"; printf "\n" >>"$TEST_LOG"
if [[ $* == "-ww -eo pid=,ppid=,uid=,gid=,comm=" ]]; then
  if [[ -n ${TEST_PS_TREE:-} ]]; then printf "%s\n" "$TEST_PS_TREE";
  else printf "%s\n" "$pid 1 999 988 gunicorn" "$((pid+1)) $pid 999 988 gunicorn"; fi
elif [[ ${1:-} == -ww && ${2:-} == -p && ${4:-} == -o && ${5:-} == args= ]]; then
  printf "%s\n" "${TEST_PS_ARGS:-$args ralf_bootstrap.wsgi:app}"
else
  printf "unexpected ps invocation: %s\n" "$*" >&2
  exit 90
fi'
  make_stub "$bin/stat" '
format=${2:-}; shift 2
for path in "$@"; do
  kind="regular file"; owner="root:root"; mode=644
  case $path in
    */opt/ralf/bootstrap|*/opt/ralf/bootstrap/app|*/opt/ralf/bootstrap/venv|*/etc/ralf/bootstrap) kind=directory; owner=root:ralf-bootstrap; mode=750 ;;
    */opt/ralf/bootstrap/venv/*) owner=root:ralf-bootstrap ;;
    */opt/ralf/bootstrap/app/*) owner=root:ralf-bootstrap; mode=640 ;;
    */var/lib/ralf/bootstrap) kind=directory; owner=ralf-bootstrap:ralf-bootstrap; mode=750 ;;
    */bundle) kind=directory; owner=root:root; mode=700 ;;
    */opt/ralf/bootstrap/VERSION|*/etc/ralf/bootstrap/config.toml) owner=root:ralf-bootstrap; mode=640 ;;
    */.ralf-bootstrap.service.update.*) owner=root:root; mode=644 ;;
    */bundle/ralf-bootstrap.service|*/etc/systemd/system/ralf-bootstrap.service) owner=root:root; mode=644 ;;
  esac
  if [[ $format == "%F|%U:%G|%a" ]]; then printf "%s|%s|%s\n" "$kind" "$owner" "$mode";
  elif [[ $format == "%U:%G" ]]; then printf "%s\n" "$owner";
  elif [[ $format == meta=* ]]; then printf "meta=%s|%s|%s\n" "$path" "$owner" "$mode";
  else /usr/bin/stat -c "$format" "$path"; fi
done'
  make_stub "$bin/systemctl" '
cmd=${1:-}; shift || true
printf "systemctl %s" "$cmd" >>"$TEST_LOG"; printf " %q" "$@" >>"$TEST_LOG"; printf "\n" >>"$TEST_LOG"
case $cmd in
  is-system-running) printf "running\n" ;;
  show)
    pid=$(cat "$TEST_STATE/main-pid")
    printf "%s\n" \
      "FragmentPath=$TEST_ROOT_PATH/etc/systemd/system/ralf-bootstrap.service" \
      "DropInPaths=${TEST_DROPINS:-}" "LoadState=loaded" "UnitFileState=enabled" \
      "ActiveState=active" "SubState=running" "Result=success" "ExecMainStatus=0" "NRestarts=0" "MainPID=$pid"
    ;;
  cat) cat "$TEST_ROOT_PATH/etc/systemd/system/ralf-bootstrap.service" ;;
  is-active) exit 0 ;;
  daemon-reload) touch "$TEST_STATE/daemon-reload" ;;
  restart)
    touch "$TEST_STATE/restart"
    printf "222\n" >"$TEST_STATE/main-pid"
    printf "configured\n" >"$TEST_HTTP_STATE"
    ;;
  *) exit 1 ;;
esac'
  make_stub "$bin/systemd-analyze" 'printf "verify\n" >>"$TEST_LOG"; [[ ${TEST_VERIFY_FAIL:-0} != 1 ]]'
  make_stub "$bin/journalctl" '
if [[ " $* " == *" --show-cursor "* ]]; then printf "%s\n" "-- cursor: fixture-cursor";
elif [[ ${TEST_JOURNAL_ERROR:-0} == 1 ]]; then printf "%s\n" "Control server error: /nonexistent Read-only file system";
else printf "%s\n" "Gunicorn booted without control socket"; fi'
  make_stub "$bin/sleep" ':'
}

make_fixture() {
  local dir=$1 unit_kind=$2
  local root="$dir/root" bundle="$dir/bundle" bin="$dir/bin" state="$dir/state"
  mkdir -p "$root/etc/systemd/system" "$root/etc/ralf/bootstrap" "$root/opt/ralf/bootstrap/app" \
    "$root/opt/ralf/bootstrap/venv/bin" "$root/var/lib/ralf/bootstrap" "$root/var/lib/dpkg" \
    "$root/var/lib/apt/lists" "$root/var/cache/apt/archives" "$bundle" "$state"
  printf '%s\n' 'ID=ubuntu' 'VERSION_ID="26.04"' >"$root/etc/os-release"
  printf '0.1.0\n' >"$root/opt/ralf/bootstrap/VERSION"
  cp "$PROJECT_ROOT/requirements/runtime.lock" "$root/opt/ralf/bootstrap/app/runtime.lock"
  printf 'wheel\n' >"$root/opt/ralf/bootstrap/app/ralf_bootstrap-0.1.0-py3-none-any.whl"
  cp "$PROJECT_ROOT/deploy/bootstrap-status/config.toml" "$root/etc/ralf/bootstrap/config.toml"
  if [[ $unit_kind == old ]]; then
    python3 - "$TARGET_UNIT" "$root/etc/systemd/system/ralf-bootstrap.service" <<'PY'
from pathlib import Path
import sys
data = Path(sys.argv[1]).read_bytes()
data = data.replace(b"  --no-control-socket \\\n", b"", 1)
data = data.replace(b"RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6 AF_NETLINK\n", b"RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6\n", 1)
Path(sys.argv[2]).write_bytes(data)
PY
  else
    cp "$TARGET_UNIT" "$root/etc/systemd/system/ralf-bootstrap.service"
  fi
  printf 'home = /usr/bin\n' >"$root/opt/ralf/bootstrap/venv/pyvenv.cfg"
  make_stub "$root/opt/ralf/bootstrap/venv/bin/python" '
if [[ ${1:-} == -c && $2 == *importlib.metadata* ]]; then
  printf "%s\n" "$TEST_ROOT_PATH/opt/ralf/bootstrap/venv|$TEST_ROOT_PATH/opt/ralf/bootstrap/venv|26.0.0|0.1.0"
fi
exit 0'
  printf '#!%s/opt/ralf/bootstrap/venv/bin/python\n' "$root" >"$root/opt/ralf/bootstrap/venv/bin/gunicorn"
  chmod 0755 "$root/opt/ralf/bootstrap/venv/bin/gunicorn"
  cp "$TARGET_UNIT" "$bundle/ralf-bootstrap.service"
  cp "$SCRIPT" "$bundle/ralf-bootstrap-status-unit-update-guest.sh"
  chmod 0644 "$bundle/ralf-bootstrap.service"
  chmod 0750 "$bundle/ralf-bootstrap-status-unit-update-guest.sh"
  (cd "$bundle" && sha256sum ralf-bootstrap.service ralf-bootstrap-status-unit-update-guest.sh >SHA256SUMS)
  printf '111\n' >"$state/main-pid"
  printf '%s\n' "$([[ $unit_kind == current ]] && printf configured || printf degraded)" >"$state/http-state"
  : >"$state/commands.log"
  make_stubs "$bin" "$state" "$root"
}

start_http_server() {
  local state_file=$1
  python3 - "$state_file" <<'PY' &
import json
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
import sys

state = Path(sys.argv[1])
class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        configured = state.read_text().strip() == "configured"
        payload = {
            "bootstrap": {"version": "0.1.0", "sqlite": {"status": "not_initialized"}},
            "components": [
                {"id": "bootstrap-status", "status": "running"},
                {"id": "model-runtime", "status": "not_configured"},
                {"id": "model", "status": "not_configured"},
                {"id": "model-webui", "status": "not_configured"},
                {"id": "privileged-installer", "status": "not_configured"},
            ],
            "network": {
                "status": "configured" if configured else "degraded",
                "default_route": configured,
                "ipv4_addresses": ["10.10.200.11"] if configured else [],
            },
            "warnings": [] if configured else ["IPv4-Adresse oder Default-Route fehlt."],
        }
        body = json.dumps(payload).encode() if self.path.endswith("status") else b"ok"
        self.send_response(200)
        for name, value in {
            "Content-Type": "application/json" if self.path.endswith("status") else "text/plain",
            "X-Content-Type-Options": "nosniff", "X-Frame-Options": "DENY",
            "Referrer-Policy": "no-referrer", "Cache-Control": "no-store",
            "Content-Security-Policy": "default-src 'self'",
        }.items(): self.send_header(name, value)
        self.end_headers(); self.wfile.write(body)
    def log_message(self, *_): pass
HTTPServer(("127.0.0.1", 8080), Handler).serve_forever()
PY
  SERVER_PID=$!
  for _ in $(seq 1 30); do
    python3 -c 'from urllib.request import urlopen; urlopen("http://127.0.0.1:8080/", timeout=.2)' >/dev/null 2>&1 && return 0
    /usr/bin/sleep 0.05
  done
  return 1
}

run_guest() {
  local dir=$1
  shift
  TEST_ROOT_PATH="$dir/root" TEST_STATE="$dir/state" TEST_LOG="$dir/state/commands.log" \
    TEST_HTTP_STATE="$dir/state/http-state" RALF_UNIT_UPDATE_ROOT="$dir/root" \
    PATH="$dir/bin:/usr/bin:/bin" "$SCRIPT" "$@"
}

classify_tree_case() {
  local name=$1 tree=$2 diagnostic=$3
  local dir="$TEST_ROOT/tree-$name" output
  make_fixture "$dir" old
  output=$(TEST_PS_TREE="$tree" run_guest "$dir" --classify --target-sha256 "$TARGET_SHA" 2>"$dir/state/stderr")
  [[ $output == 'RALF_BOOTSTRAP_UNIT_STATE_V1=unit_update_conflict' ]]
  grep -Fq "$diagnostic" "$dir/state/stderr"
}

classify_args_case() {
  local name=$1 args=$2 diagnostic=$3
  local dir="$TEST_ROOT/args-$name" output
  make_fixture "$dir" current
  output=$(TEST_PS_ARGS="$args" run_guest "$dir" --classify --target-sha256 "$TARGET_SHA" 2>"$dir/state/stderr")
  [[ $output == 'RALF_BOOTSTRAP_UNIT_STATE_V1=unit_update_conflict' ]]
  grep -Fq "$diagnostic" "$dir/state/stderr"
}

old="$TEST_ROOT/old"; make_fixture "$old" old; start_http_server "$old/state/http-state"
output=$(run_guest "$old" --classify --target-sha256 "$TARGET_SHA" 2>"$old/state/stderr")
[[ $output == 'RALF_BOOTSTRAP_UNIT_STATE_V1=unit_update_required' && ! -s "$old/state/stderr" ]]
printf 'PASS guest-classify-old-required\n'

classify_tree_case master-uid $'111 1 998 988 gunicorn\n112 111 999 988 gunicorn' 'gunicorn:master-identity:111:998:988:gunicorn'
classify_tree_case master-gid $'111 1 999 987 gunicorn\n112 111 999 988 gunicorn' 'gunicorn:master-identity:111:999:987:gunicorn'
classify_tree_case worker-uid $'111 1 999 988 gunicorn\n112 111 998 988 gunicorn' 'gunicorn:worker-identity:112:111:998:988:gunicorn'
classify_tree_case worker-gid $'111 1 999 988 gunicorn\n112 111 999 987 gunicorn' 'gunicorn:worker-identity:112:111:999:987:gunicorn'
classify_tree_case missing-worker '111 1 999 988 gunicorn' 'gunicorn:service-tree-count:1:expected:2'
classify_tree_case two-workers $'111 1 999 988 gunicorn\n112 111 999 988 gunicorn\n113 111 999 988 gunicorn' 'gunicorn:service-tree-count:3:expected:2'
classify_tree_case wrong-worker-ppid $'111 1 999 988 gunicorn\n112 999 999 988 gunicorn' 'gunicorn:service-tree-count:1:expected:2'
classify_tree_case wrong-master-comm $'111 1 999 988 python\n112 111 999 988 gunicorn' 'gunicorn:master-identity:111:999:988:python'
classify_tree_case wrong-worker-comm $'111 1 999 988 gunicorn\n112 111 999 988 python' 'gunicorn:worker-identity:112:111:999:988:python'
classify_tree_case extra-child $'111 1 999 988 gunicorn\n112 111 999 988 gunicorn\n113 111 999 988 helper' 'gunicorn:service-tree-count:3:expected:2'

foreign="$TEST_ROOT/tree-foreign"; make_fixture "$foreign" old
output=$(TEST_PS_TREE=$'111 1 999 988 gunicorn\n112 111 999 988 gunicorn\n900 1 500 500 gunicorn\n901 900 500 500 gunicorn' run_guest "$foreign" --classify --target-sha256 "$TARGET_SHA" 2>"$foreign/state/stderr")
[[ $output == 'RALF_BOOTSTRAP_UNIT_STATE_V1=unit_update_required' ]]
if grep -Eq 'user=|group=' "$foreign/state/commands.log"; then exit 1; fi
grep -Fq 'ps -ww -eo pid=\,ppid=\,uid=\,gid=\,comm=' "$foreign/state/commands.log"
printf 'PASS guest-numeric-service-tree-validation\n'

invalid_identity="$TEST_ROOT/invalid-identity"; make_fixture "$invalid_identity" old
output=$(TEST_PASSWD_UID=not-numeric run_guest "$invalid_identity" --classify --target-sha256 "$TARGET_SHA" 2>"$invalid_identity/state/stderr")
[[ $output == 'RALF_BOOTSTRAP_UNIT_STATE_V1=unit_update_conflict' ]]
grep -Fq 'identity:non-numeric' "$invalid_identity/state/stderr"
if grep -Fq 'ps ' "$invalid_identity/state/commands.log"; then exit 1; fi
printf 'PASS guest-invalid-numeric-identity-before-process-check\n'

current="$TEST_ROOT/current"; make_fixture "$current" current
printf 'configured\n' >"$old/state/http-state"
output=$(run_guest "$current" --classify --target-sha256 "$TARGET_SHA" 2>"$current/state/stderr")
[[ $output == 'RALF_BOOTSTRAP_UNIT_STATE_V1=unit_already_current' ]]
printf 'PASS guest-classify-current\n'

long_padding='python launcher with deliberately long harmless prefix tokens that exceed a traditional terminal width before the required gunicorn flags'
long_args="$long_padding --workers 1 --bind 127.0.0.1:8080 --no-control-socket ralf_bootstrap.wsgi:app"
long="$TEST_ROOT/args-long"; make_fixture "$long" current
output=$(TEST_PS_ARGS="$long_args" run_guest "$long" --classify --target-sha256 "$TARGET_SHA" 2>"$long/state/stderr")
[[ $output == 'RALF_BOOTSTRAP_UNIT_STATE_V1=unit_already_current' ]]
grep -Fq 'ps -ww -p 111 -o args=' "$long/state/commands.log"
classify_args_case missing-control '/venv/bin/gunicorn --workers 1 --bind 127.0.0.1:8080 ralf_bootstrap.wsgi:app' 'gunicorn:main-args:no-control-socket:0:expected:1'
classify_args_case duplicate-control '/venv/bin/gunicorn --workers 1 --bind 127.0.0.1:8080 --no-control-socket --no-control-socket ralf_bootstrap.wsgi:app' 'gunicorn:main-args:no-control-socket:2:expected:1'
classify_args_case wrong-bind '/venv/bin/gunicorn --workers 1 --bind 0.0.0.0:8080 --no-control-socket ralf_bootstrap.wsgi:app' 'gunicorn:main-args:bind:0:expected:1'
classify_args_case wrong-workers '/venv/bin/gunicorn --workers 2 --bind 127.0.0.1:8080 --no-control-socket ralf_bootstrap.wsgi:app' 'gunicorn:main-args:workers:0:expected:1'
printf 'PASS guest-wide-main-argument-validation\n'

foreign="$TEST_ROOT/foreign"; make_fixture "$foreign" old; printf '# foreign\n' >>"$foreign/root/etc/systemd/system/ralf-bootstrap.service"
output=$(run_guest "$foreign" --classify --target-sha256 "$TARGET_SHA" 2>"$foreign/state/stderr")
[[ $output == 'RALF_BOOTSTRAP_UNIT_STATE_V1=unit_update_conflict' ]]
grep -Fq 'unit-hash:' "$foreign/state/stderr"
printf 'PASS guest-foreign-unit-conflict\n'

dropin="$TEST_ROOT/dropin"; make_fixture "$dropin" old
output=$(TEST_DROPINS=/etc/systemd/system/ralf-bootstrap.service.d/override.conf run_guest "$dropin" --classify --target-sha256 "$TARGET_SHA" 2>"$dropin/state/stderr")
[[ $output == 'RALF_BOOTSTRAP_UNIT_STATE_V1=unit_update_conflict' ]]
grep -Fq 'systemd:fragment-or-dropins' "$dropin/state/stderr"
printf 'PASS guest-dropin-conflict\n'

dropin_dir="$TEST_ROOT/dropin-dir"; make_fixture "$dropin_dir" old
mkdir -p "$dropin_dir/root/etc/systemd/system/ralf-bootstrap.service.d"
output=$(run_guest "$dropin_dir" --classify --target-sha256 "$TARGET_SHA" 2>"$dropin_dir/state/stderr")
[[ $output == 'RALF_BOOTSTRAP_UNIT_STATE_V1=unit_update_conflict' ]]
grep -Fq 'unit:dropin-directory-present' "$dropin_dir/state/stderr"
printf 'PASS guest-dropin-directory-conflict\n'

symlink="$TEST_ROOT/symlink"; make_fixture "$symlink" old
mv "$symlink/root/etc/systemd/system/ralf-bootstrap.service" "$symlink/root/etc/systemd/system/real.service"
ln -s real.service "$symlink/root/etc/systemd/system/ralf-bootstrap.service"
output=$(run_guest "$symlink" --classify --target-sha256 "$TARGET_SHA" 2>"$symlink/state/stderr")
[[ $output == 'RALF_BOOTSTRAP_UNIT_STATE_V1=unit_update_conflict' ]]
printf 'PASS guest-unit-symlink-conflict\n'

printf 'degraded\n' >"$old/state/http-state"
before=$(find "$old/root" -type f -exec sha256sum {} + | sort | sha256sum)
run_guest "$old" --plan --target-sha256 "$TARGET_SHA" >"$old/state/plan"
after=$(find "$old/root" -type f -exec sha256sum {} + | sort | sha256sum)
[[ $before == "$after" ]]
if grep -Eq 'systemctl (daemon-reload|restart|stop|start|enable)' "$old/state/commands.log"; then exit 1; fi
grep -Fq 'Klassifikation: unit_update_required' "$old/state/plan"
printf 'PASS guest-plan-read-only\n'

run_guest "$old" --apply --target-sha256 "$TARGET_SHA" --bundle "$old/bundle" >"$old/state/apply"
[[ $(sha256sum "$old/root/etc/systemd/system/ralf-bootstrap.service" | awk '{print $1}') == "$TARGET_SHA" ]]
[[ $(grep -c '^systemctl daemon-reload' "$old/state/commands.log") == 1 ]]
[[ $(grep -c '^systemctl restart' "$old/state/commands.log") == 1 ]]
if grep -Eq '^systemctl (stop|start|enable|disable)' "$old/state/commands.log"; then exit 1; fi
grep -Fq 'Unit-Update erfolgreich' "$old/state/apply"
printf 'PASS guest-atomic-update-once\n'

: >"$current/state/commands.log"
run_guest "$current" --apply --target-sha256 "$TARGET_SHA" --bundle "$current/bundle" >"$current/state/apply"
grep -Fq 'bereits aktuell' "$current/state/apply"
if grep -Eq '^systemctl (daemon-reload|restart|stop|start|enable)' "$current/state/commands.log"; then exit 1; fi
printf 'PASS guest-idempotent-apply\n'

for mutation in public af-packet capability extra; do
  dir="$TEST_ROOT/semantic-$mutation"; make_fixture "$dir" old
  case $mutation in
    public) sed -i 's/127\.0\.0\.1:8080/0.0.0.0:8080/' "$dir/bundle/ralf-bootstrap.service" ;;
    af-packet) sed -i 's/AF_NETLINK/AF_NETLINK AF_PACKET/' "$dir/bundle/ralf-bootstrap.service" ;;
    capability) sed -i 's/^AmbientCapabilities=$/AmbientCapabilities=CAP_NET_RAW/' "$dir/bundle/ralf-bootstrap.service" ;;
    extra) printf '# extra\n' >>"$dir/bundle/ralf-bootstrap.service" ;;
  esac
  (cd "$dir/bundle" && sha256sum ralf-bootstrap.service ralf-bootstrap-status-unit-update-guest.sh >SHA256SUMS)
  bad_hash=$(sha256sum "$dir/bundle/ralf-bootstrap.service" | awk '{print $1}')
  set +e
  run_guest "$dir" --apply --target-sha256 "$bad_hash" --bundle "$dir/bundle" >"$dir/state/output" 2>&1
  status=$?
  set -e
  [[ $status == 1 ]]
  [[ $(sha256sum "$dir/root/etc/systemd/system/ralf-bootstrap.service" | awk '{print $1}') == '8f5b30c7d9335824dfabb19cab5b338337860a45e785a6985370da9b8f6f48d7' ]]
  if grep -Eq '^systemctl (daemon-reload|restart)' "$dir/state/commands.log"; then exit 1; fi
done
printf 'PASS guest-semantic-conflicts-before-mutation\n'

checksum="$TEST_ROOT/checksum"; make_fixture "$checksum" old
printf 'broken\n' >"$checksum/bundle/SHA256SUMS"
set +e
run_guest "$checksum" --apply --target-sha256 "$TARGET_SHA" --bundle "$checksum/bundle" >"$checksum/state/output" 2>&1
status=$?
set -e
[[ $status == 1 ]]
[[ $(sha256sum "$checksum/root/etc/systemd/system/ralf-bootstrap.service" | awk '{print $1}') == '8f5b30c7d9335824dfabb19cab5b338337860a45e785a6985370da9b8f6f48d7' ]]
if grep -Eq '^systemctl (daemon-reload|restart)' "$checksum/state/commands.log"; then exit 1; fi
printf 'PASS guest-invalid-bundle-before-mutation\n'

journal="$TEST_ROOT/journal-error"; make_fixture "$journal" old
set +e
TEST_JOURNAL_ERROR=1 run_guest "$journal" --apply --target-sha256 "$TARGET_SHA" --bundle "$journal/bundle" >"$journal/state/output" 2>&1
status=$?
set -e
[[ $status == 1 ]]
[[ $(grep -c '^systemctl restart' "$journal/state/commands.log") == 1 ]]
[[ $(sha256sum "$journal/root/etc/systemd/system/ralf-bootstrap.service" | awk '{print $1}') == "$TARGET_SHA" ]]
grep -Fq 'Kein automatischer Rollback' "$journal/state/output"
printf 'PASS guest-post-replace-failure-no-retry-no-rollback\n'

grep -Fq 'mv -f -- "$temp_unit" "$UNIT_FILE"' "$SCRIPT"
grep -Fq "systemctl daemon-reload" "$SCRIPT"
grep -Fq "systemctl restart ralf-bootstrap.service" "$SCRIPT"
if grep -Eq 'systemctl (stop|start|enable|disable)' "$SCRIPT"; then exit 1; fi
if grep -Eq 'pip install|python3 -m venv|apt-get (install|update|upgrade|full-upgrade|autoremove)' "$SCRIPT"; then exit 1; fi
if grep -Eq 'user=|group=' "$SCRIPT"; then exit 1; fi
grep -Fq 'LC_ALL=C ps -ww -eo pid=,ppid=,uid=,gid=,comm=' "$SCRIPT"
grep -Fq 'LC_ALL=C ps -ww -p "$pid" -o args=' "$SCRIPT"
printf 'PASS guest-scope-source-checks\n'
