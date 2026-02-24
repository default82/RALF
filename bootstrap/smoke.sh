#!/usr/bin/env bash
set -euo pipefail

PHASE="${1:-phase1}"

log() { printf '%s\n' "[smoke] $*"; }
need() { command -v "$1" >/dev/null 2>&1 || { echo "missing command: $1" >&2; exit 1; }; }

need bash
need curl

tcp_check() {
  local host="$1" port="$2" name="$3"
  if timeout 5 bash -lc "</dev/tcp/${host}/${port}" >/dev/null 2>&1; then
    log "OK tcp ${name} ${host}:${port}"
  else
    log "FAIL tcp ${name} ${host}:${port}"
    return 1
  fi
}

http_check() {
  local url="$1" name="$2"
  local i
  for i in $(seq 1 15); do
    if curl -fsS -m 8 -o /dev/null "$url" 2>/dev/null; then
      log "OK http ${name} ${url}"
      return 0
    fi
    sleep 2
  done
  log "FAIL http ${name} ${url}"
  return 1
}

https_check_insecure() {
  local url="$1" name="$2"
  local i
  for i in $(seq 1 15); do
    if curl -kfsS -m 8 -o /dev/null "$url" 2>/dev/null; then
      log "OK https ${name} ${url}"
      return 0
    fi
    sleep 2
  done
  log "FAIL https ${name} ${url}"
  return 1
}

case "$PHASE" in
  minio)
    tcp_check 10.10.30.10 9000 minio-api
    http_check http://10.10.30.10:9000/minio/health/live minio-live
    ;;
  postgres)
    tcp_check 10.10.20.10 5432 postgres
    ;;
  gitea)
    tcp_check 10.10.40.40 443 gitea-https
    https_check_insecure https://10.10.40.40/ gitea-nginx
    ;;
  semaphore)
    tcp_check 10.10.40.10 443 semaphore-https
    https_check_insecure https://10.10.40.10/ semaphore-nginx
    ;;
  vaultwarden)
    tcp_check 10.10.40.20 443 vaultwarden-https
    https_check_insecure https://10.10.40.20/ vaultwarden-nginx
    ;;
  n8n)
    tcp_check 10.10.40.30 443 n8n-https
    https_check_insecure https://10.10.40.30/ n8n-nginx
    ;;
  exo)
    tcp_check 10.10.90.10 443 exo-https
    https_check_insecure https://10.10.90.10/ exo-nginx
    ;;
  synapse)
    tcp_check 10.10.110.10 8008 synapse-http
    http_check http://10.10.110.10:8008/_matrix/client/versions synapse-client-versions
    ;;
  mail)
    tcp_check 10.10.110.20 25 mail-smtp
    tcp_check 10.10.110.20 587 mail-submission
    tcp_check 10.10.110.20 993 mail-imaps
    ;;
  vault)
    "$0" vaultwarden
    ;;
  automation)
    "$0" n8n
    ;;
  ai)
    "$0" exo
    ;;
  communication)
    "$0" synapse
    "$0" mail
    ;;
  phase1)
    "$0" minio
    "$0" postgres
    "$0" gitea
    "$0" semaphore
    ;;
  platform)
    "$0" phase1
    "$0" vault
    "$0" automation
    "$0" communication
    "$0" ai
    ;;
  *)
    echo "usage: $0 [minio|postgres|gitea|semaphore|vaultwarden|n8n|exo|synapse|mail|vault|automation|ai|communication|phase1|platform]" >&2
    exit 2
    ;;
esac

log "Done (${PHASE})"
