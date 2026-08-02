#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
readonly PROJECT_ROOT
readonly LOCK_FILE="$PROJECT_ROOT/deploy/secure-ingress/caddy/caddy.lock.toml"
TEST_ROOT=$(mktemp -d)
readonly TEST_ROOT

cleanup() {
  find "$TEST_ROOT" -type f -delete
  find "$TEST_ROOT" -type l -delete
  find "$TEST_ROOT" -depth -type d -empty -delete
}
trap cleanup EXIT

mapfile -t lock_values < <(python3 - "$LOCK_FILE" <<'PY'
from pathlib import Path
import re
import sys
import tomllib

path = Path(sys.argv[1])
data = tomllib.loads(path.read_text(encoding="utf-8"))
expected = {"schema_version", "version", "asset", "url", "sha256", "sha512", "checksums_url"}
if set(data) != expected or data["schema_version"] != 1:
    raise SystemExit("ungültige Caddy-Lockdatei")
if data["version"] != "2.11.4" or data["asset"] != "caddy_2.11.4_linux_amd64.tar.gz":
    raise SystemExit("unerwartete Caddy-Version oder Artefakt")
if not re.fullmatch(r"[0-9a-f]{64}", data["sha256"]):
    raise SystemExit("ungültiger SHA-256-Wert")
if not re.fullmatch(r"[0-9a-f]{128}", data["sha512"]):
    raise SystemExit("ungültiger SHA-512-Wert")
for key in ("version", "asset", "url", "sha256", "sha512", "checksums_url"):
    print(data[key])
PY
)

readonly VERSION=${lock_values[0]}
readonly ASSET=${lock_values[1]}
readonly URL=${lock_values[2]}
readonly SHA256=${lock_values[3]}
readonly SHA512=${lock_values[4]}
readonly CHECKSUMS_URL=${lock_values[5]}

if [[ -n ${RALF_CADDY_BIN:-} ]]; then
  CADDY_BIN=$RALF_CADDY_BIN
  [[ -f $CADDY_BIN && -x $CADDY_BIN ]] || {
    printf 'Fehler: RALF_CADDY_BIN ist kein ausführbares Binary.\n' >&2
    exit 1
  }
else
  readonly ARCHIVE="$TEST_ROOT/$ASSET"
  readonly CHECKSUMS="$TEST_ROOT/caddy-checksums.txt"
  curl -fsSL --proto '=https' --tlsv1.2 -o "$ARCHIVE" "$URL"
  curl -fsSL --proto '=https' --tlsv1.2 -o "$CHECKSUMS" "$CHECKSUMS_URL"
  printf '%s  %s\n' "$SHA256" "$ARCHIVE" | sha256sum -c -
  printf '%s  %s\n' "$SHA512" "$ARCHIVE" | sha512sum -c -
  grep -Fq "$SHA512  $ASSET" "$CHECKSUMS" || {
    printf 'Fehler: Offizielle SHA-512-Prüfsumme stimmt nicht.\n' >&2
    exit 1
  }
  tar -xzf "$ARCHIVE" -C "$TEST_ROOT" caddy
  CADDY_BIN="$TEST_ROOT/caddy"
  chmod 0755 "$CADDY_BIN"
fi
readonly CADDY_BIN

version_output=$($CADDY_BIN version)
[[ $version_output == "v${VERSION} "* ]] || {
  printf 'Fehler: Unerwartete Caddy-Version.\n' >&2
  exit 1
}

module_output=$($CADDY_BIN list-modules --packages)
if grep -Fq 'Non-standard modules' <<<"$module_output"; then
  printf 'Fehler: Caddy-Binary enthält nicht standardmäßige Module.\n' >&2
  exit 1
fi
grep -Fq 'http.authentication.hashes.argon2id github.com/caddyserver/caddy/v2' <<<"$module_output"
grep -Fq 'http.matchers.remote_ip github.com/caddyserver/caddy/v2' <<<"$module_output"
grep -Fq 'tls.issuance.internal github.com/caddyserver/caddy/v2' <<<"$module_output"

readonly TEST_PYTHON=${RALF_TEST_PYTHON:-python3}
RALF_CADDY_BIN="$CADDY_BIN" "$TEST_PYTHON" -m pytest -q "$PROJECT_ROOT/tests/secure_ingress"
