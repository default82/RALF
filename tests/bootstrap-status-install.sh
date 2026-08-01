#!/usr/bin/env bash

# shellcheck disable=SC2016

set -Eeuo pipefail

PROJECT_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
readonly SCRIPT="$PROJECT_ROOT/scripts/ralf-bootstrap-status-install.sh"
TEST_ROOT=$(mktemp -d)
trap 'find "$TEST_ROOT" -type f -delete; find "$TEST_ROOT" -depth -type d -empty -delete' EXIT

make_stub() {
  local dir=$1 name=$2 body=$3
  mkdir -p "$dir"
  printf '#!/usr/bin/env bash\nset -Eeuo pipefail\n%s\n' "$body" >"$dir/$name"
  chmod +x "$dir/$name"
}

make_bundle() {
  local bundle=$1
  mkdir -p "$bundle"
  BUNDLE_PATH="$bundle" /usr/bin/python3 - <<'PY'
from pathlib import Path
from zipfile import ZipFile
import os
bundle = Path(os.environ["BUNDLE_PATH"])
wheel = bundle / "ralf_bootstrap-0.1.0-py3-none-any.whl"
with ZipFile(wheel, "w") as archive:
    archive.writestr("ralf_bootstrap-0.1.0.dist-info/METADATA", "Name: ralf-bootstrap\nVersion: 0.1.0\n")
    archive.writestr("ralf_bootstrap-0.1.0.dist-info/WHEEL", "Wheel-Version: 1.0\n")
PY
  printf '%s\n' '[storage]' 'database_path = "/var/lib/ralf/bootstrap/state.db"' >"$bundle/config.toml"
  printf '%s\n' 'Flask==3.1.3' 'Gunicorn==26.0.0' >"$bundle/runtime.lock"
  printf '%s\n' '[Unit]' 'Description=Test' >"$bundle/ralf-bootstrap.service"
  cp "$SCRIPT" "$bundle/ralf-bootstrap-status-install.sh"
  (cd "$bundle" && sha256sum ralf_bootstrap-0.1.0-py3-none-any.whl runtime.lock config.toml ralf-bootstrap.service ralf-bootstrap-status-install.sh >SHA256SUMS)
}

make_stubs() {
  local bin=$1
  mkdir -p "$bin"
  make_stub "$bin" id 'if [[ ${TEST_NON_ROOT:-0} == 1 ]]; then printf "1000\n"; elif [[ ${1:-} == -Gn ]]; then printf "ralf-bootstrap\n"; else printf "0\n"; fi'
  make_stub "$bin" uname 'printf "x86_64\n"'
  make_stub "$bin" systemctl 'case "$*" in "is-system-running") printf "running\n";; "is-enabled"*) printf "enabled\n";; "is-active"*) printf "active\n";; esac'
  make_stub "$bin" ip 'printf "default via 192.0.2.1 dev eth0\n"'
  make_stub "$bin" getent 'case "$1" in ahostsv4) printf "192.0.2.1 STREAM archive.ubuntu.com\n";; passwd) [[ -f "$TEST_STATE/user" ]] && printf "ralf-bootstrap:x:997:997::/nonexistent:/usr/sbin/nologin\n" || exit 2;; group) [[ -f "$TEST_STATE/group" ]] && printf "ralf-bootstrap:x:997:\n" || exit 2;; esac'
  make_stub "$bin" dpkg 'exit 0'
  make_stub "$bin" pgrep 'exit 1'
  make_stub "$bin" fuser 'exit 1'
  make_stub "$bin" wget 'exit 0'
  make_stub "$bin" groupadd 'touch "$TEST_STATE/group"'
  make_stub "$bin" useradd 'touch "$TEST_STATE/user"'
  make_stub "$bin" chown 'exit 0'
  make_stub "$bin" systemd-analyze 'exit 0'
  make_stub "$bin" stat 'case "$*" in *"VERSION"*) printf "root:ralf-bootstrap|640\n";; *"config.toml"*) printf "root:ralf-bootstrap|640\n";; *"runtime.lock"*|*".whl"*) printf "root:ralf-bootstrap|640\n";; *"ralf-bootstrap.service"*) printf "root:root|644\n";; *"/var/lib/ralf/bootstrap"*) printf "ralf-bootstrap:ralf-bootstrap|750\n";; *) printf "root:ralf-bootstrap|750\n";; esac'
  make_stub "$bin" install 'args=(); while (($#)); do case $1 in -o|-g) shift;; *) args+=("$1");; esac; shift; done; exec /usr/bin/install "${args[@]}"'
  make_stub "$bin" python3 'if [[ ${1:-} == -c && ${2:-} == *socket* && ${TEST_PORT_BUSY:-0} == 1 ]]; then exit 1; elif [[ ${1:-} == - && $# == 1 && ${TEST_PORT_BUSY:-0} == 1 ]]; then exit 1; elif [[ ${1:-} == -m && ${2:-} == venv && ${3:-} != --help ]]; then dir=$3; mkdir -p "$dir/bin"; printf "%s\n" "#!/usr/bin/env bash" "if [[ \${1:-} == -m || \${1:-} == - ]]; then exit 0; fi" >"$dir/bin/python"; printf "%s\n" "#!/usr/bin/env bash" "exit 0" >"$dir/bin/gunicorn"; chmod +x "$dir/bin/python" "$dir/bin/gunicorn"; elif [[ ${1:-} == - && $# == 1 ]]; then exit 0; else exec /usr/bin/python3 "$@"; fi'
}

run_case() {
  local mode=$1 name=$2
  local root="$TEST_ROOT/$name/root" bundle="$TEST_ROOT/$name/bundle" bin="$TEST_ROOT/$name/bin" state="$TEST_ROOT/$name/state"
  mkdir -p "$root/etc" "$root/var/lib/dpkg/updates" "$root/var/run" "$state"
  printf '%s\n' 'ID=ubuntu' 'VERSION_ID="26.04"' >"$root/etc/os-release"
  make_bundle "$bundle"
  make_stubs "$bin"
  local output status
  set +e
  output=$(TEST_NON_ROOT="$([[ $name == non-root ]] && printf 1 || printf 0)" TEST_STATE="$state" RALF_INSTALL_ROOT="$root" PATH="$bin:/usr/bin:/bin" "$SCRIPT" "--$mode" --bundle "$bundle" 2>&1)
  status=$?
  set -e
  if [[ $name == non-root ]]; then
    [[ $status == 1 ]] && grep -Fq 'root ausgeführt' <<<"$output"
    printf 'PASS non-root\n'
  elif [[ $mode == plan ]]; then
    [[ $status == 0 ]] && grep -Fq 'es wurden noch keine Installationsmutationen ausgeführt' <<<"$output"
    [[ ! -e "$root/opt" ]]
    printf 'PASS plan-no-mutation\n'
  else
    [[ $status == 0 ]] && grep -Fq 'Installation erfolgreich' <<<"$output"
    [[ -d "$root/opt/ralf/bootstrap/app" && -d "$root/opt/ralf/bootstrap/venv" ]]
    [[ -f "$root/etc/ralf/bootstrap/config.toml" && ! -e "$root/var/lib/ralf/bootstrap/state.db" ]]
    printf 'PASS apply-installation\n'
    output=$(TEST_STATE="$state" RALF_INSTALL_ROOT="$root" PATH="$bin:/usr/bin:/bin" "$SCRIPT" --apply --bundle "$bundle" 2>&1)
    grep -Fq 'Bereits vollständige Installation erkannt' <<<"$output"
    printf 'PASS apply-idempotent\n'
  fi
}

run_bundle_failure() {
  local name=$1
  local root="$TEST_ROOT/$name/root" bundle="$TEST_ROOT/$name/bundle" bin="$TEST_ROOT/$name/bin" state="$TEST_ROOT/$name/state"
  mkdir -p "$root/etc" "$root/var/lib/dpkg/updates" "$root/var/run" "$state"
  printf '%s\n' 'ID=ubuntu' 'VERSION_ID="26.04"' >"$root/etc/os-release"
  make_bundle "$bundle"
  make_stubs "$bin"
  if [[ $name == bad-checksum ]]; then printf '%s\n' 'broken' >"$bundle/SHA256SUMS"; fi
  if [[ $name == partial ]]; then mkdir -p "$root/opt/ralf/bootstrap"; fi
  local output status
  set +e
  output=$(TEST_PORT_BUSY="$([[ $name == busy-port ]] && printf 1 || printf 0)" TEST_STATE="$state" RALF_INSTALL_ROOT="$root" PATH="$bin:/usr/bin:/bin" "$SCRIPT" --plan --bundle "$bundle" 2>&1)
  status=$?
  set -e
  [[ $status == 1 ]]
  grep -Fq 'Fehler:' <<<"$output"
  printf 'PASS %s\n' "$name"
}

run_case plan plan
run_case apply apply
run_case apply non-root
run_bundle_failure bad-checksum
run_bundle_failure busy-port
run_bundle_failure partial
