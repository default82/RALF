#!/usr/bin/env bash
set -euo pipefail

SECRETS_DIR="${RALF_RUNTIME:-/opt/ralf/runtime}/secrets"
SEMAPHORE_ENV="${SECRETS_DIR}/semaphore.env"
RALF_REPO="${RALF_REPO:-/opt/ralf/repo}"
API_BASE="${SEMAPHORE_API_BASE:-http://127.0.0.1:3000}"

[[ -f "$SEMAPHORE_ENV" ]] || { echo "missing $SEMAPHORE_ENV" >&2; exit 1; }
[[ -d "$RALF_REPO" ]] || { echo "missing repo $RALF_REPO" >&2; exit 1; }

# shellcheck disable=SC1090
. "$SEMAPHORE_ENV"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
cookies="$tmpdir/cookies.txt"

changed=0

login() {
  curl -fsS -c "$cookies" \
    -X POST "$API_BASE/api/auth/login" \
    -H 'Content-Type: application/json' \
    -d "$(jq -nc --arg a "$SEMAPHORE_ADMIN_NAME" --arg p "$SEMAPHORE_ADMIN_PASSWORD" '{auth:$a,password:$p}')"
}

api_get() {
  curl -fsS -b "$cookies" "$API_BASE$1"
}

api_post() {
  local path="$1" body="$2"
  curl -fsS -L --post301 -X POST -b "$cookies" \
    -H 'Content-Type: application/json' \
    -d "$body" \
    "$API_BASE$path"
}

api_put() {
  local path="$1" body="$2"
  curl -fsS -X PUT -b "$cookies" \
    -H 'Content-Type: application/json' \
    -d "$body" \
    "$API_BASE$path" >/dev/null
}

norm_json() {
  jq -cS . <<<"${1:-null}"
}

mark_changed() {
  changed=1
  echo "[seed] $*" >&2
}

login >/dev/null

project_name="${SEMAPHORE_PROJECT_NAME:-RALF Bootstrap}"
projects_json="$(api_get /api/projects)"
project_id="$(jq -r --arg n "$project_name" '.[] | select(.name==$n) | .id' <<<"$projects_json" | head -n1)"
if [[ -z "$project_id" ]]; then
  project_body="$(jq -nc --arg n "$project_name" '{name:$n,alert:false}')"
  project_id="$(api_post /api/projects "$project_body" | jq -r '.id')"
  mark_changed "created project '$project_name' (id=$project_id)"
fi

inventory_name="RALF Inventory"
inventory_content="$(cat "$RALF_REPO/inventory/hosts.ini")"
inventories_json="$(api_get "/api/project/${project_id}/inventory")"
inventory_obj="$(jq -c --arg n "$inventory_name" '.[] | select(.name==$n)' <<<"$inventories_json" | head -n1)"
if [[ -z "$inventory_obj" ]]; then
  body="$(jq -nc --argjson pid "$project_id" --arg n "$inventory_name" --arg inv "$inventory_content" \
    '{project_id:$pid,name:$n,type:"static",inventory:$inv}')"
  inventory_id="$(api_post "/api/project/${project_id}/inventory" "$body" | jq -r '.id')"
  mark_changed "created inventory '$inventory_name'"
else
  inventory_id="$(jq -r '.id' <<<"$inventory_obj")"
  current_cmp="$(jq -cS '{name,type,inventory}' <<<"$inventory_obj")"
  desired_cmp="$(jq -nc --arg n "$inventory_name" --arg inv "$inventory_content" '{name:$n,type:"static",inventory:$inv}' | jq -cS .)"
  if [[ "$current_cmp" != "$desired_cmp" ]]; then
    body="$(jq -nc --argjson id "$inventory_id" --argjson pid "$project_id" --arg n "$inventory_name" --arg inv "$inventory_content" \
      '{id:$id,project_id:$pid,name:$n,type:"static",inventory:$inv}')"
    api_put "/api/project/${project_id}/inventory/${inventory_id}" "$body"
    mark_changed "updated inventory '$inventory_name'"
  fi
fi

repo_name="RALF Local"
repo_url="file:///opt/ralf/repo"
repos_json="$(api_get "/api/project/${project_id}/repositories")"
repo_obj="$(jq -c --arg n "$repo_name" '.[] | select(.name==$n)' <<<"$repos_json" | head -n1)"
if [[ -z "$repo_obj" ]]; then
  body="$(jq -nc --argjson pid "$project_id" --arg n "$repo_name" --arg u "$repo_url" \
    '{project_id:$pid,name:$n,git_url:$u,git_branch:"main",ssh_key_id:1}')"
  repo_id="$(api_post "/api/project/${project_id}/repositories" "$body" | jq -r '.id')"
  mark_changed "created repository '$repo_name'"
else
  repo_id="$(jq -r '.id' <<<"$repo_obj")"
  current_cmp="$(jq -cS '{name,git_url,git_branch,ssh_key_id}' <<<"$repo_obj")"
  desired_cmp="$(jq -nc --arg n "$repo_name" --arg u "$repo_url" '{name:$n,git_url:$u,git_branch:"main",ssh_key_id:1}' | jq -cS .)"
  if [[ "$current_cmp" != "$desired_cmp" ]]; then
    body="$(jq -nc --argjson id "$repo_id" --argjson pid "$project_id" --arg n "$repo_name" --arg u "$repo_url" \
      '{id:$id,project_id:$pid,name:$n,git_url:$u,git_branch:"main",ssh_key_id:1}')"
    api_put "/api/project/${project_id}/repositories/${repo_id}" "$body"
    mark_changed "updated repository '$repo_name'"
  fi
fi

ensure_env() {
  local env_name="$1" env_json="$2"
  local envs_json env_obj env_id current_cmp desired_cmp body
  envs_json="$(api_get "/api/project/${project_id}/environment")"
  env_obj="$(jq -c --arg n "$env_name" '.[] | select(.name==$n)' <<<"$envs_json" | head -n1)"
  if [[ -z "$env_obj" ]]; then
    body="$(jq -nc --argjson pid "$project_id" --arg n "$env_name" --arg e "$env_json" '{project_id:$pid,name:$n,json:"{}",env:$e}')"
    env_id="$(api_post "/api/project/${project_id}/environment" "$body" | jq -r '.id')"
    mark_changed "created environment '$env_name'"
  else
    env_id="$(jq -r '.id' <<<"$env_obj")"
    current_cmp="$(jq -cS '{name,json,env}' <<<"$env_obj")"
    desired_cmp="$(jq -nc --arg n "$env_name" --arg e "$env_json" '{name:$n,json:"{}",env:$e}' | jq -cS .)"
    if [[ "$current_cmp" != "$desired_cmp" ]]; then
      body="$(jq -nc --argjson id "$env_id" --argjson pid "$project_id" --arg n "$env_name" --arg e "$env_json" \
        '{id:$id,project_id:$pid,name:$n,json:"{}",env:$e}')"
      api_put "/api/project/${project_id}/environment/${env_id}" "$body"
      mark_changed "updated environment '$env_name'"
    fi
  fi
  printf '%s' "$env_id"
}

infra_env_json="$(jq -nc '{AUTO_APPLY:"1",START_AT:"000",ONLY_STACKS:"030-minio-lxc 020-postgres-lxc 034-gitea-lxc 040-semaphore-lxc"}')"
config_env_json="$(jq -nc '{AUTO_APPLY:"1",START_AT:"000",ONLY_STACKS:"031-minio-config 021-postgres-config 035-gitea-config 041-semaphore-config"}')"
smoke_env_json="$(jq -nc '{}')"

infra_env_id="$(ensure_env 'RALF Phase1 Infra Env' "$infra_env_json")"
config_env_id="$(ensure_env 'RALF Phase1 Config Env' "$config_env_json")"
smoke_env_id="$(ensure_env 'RALF Smoke Env' "$smoke_env_json")"

ensure_template() {
  local tpl_name="$1" playbook="$2" args_json="$3" env_id="$4"
  local templates_json tpl_obj tpl_id current_cmp desired_cmp body
  templates_json="$(api_get "/api/project/${project_id}/templates")"
  tpl_obj="$(jq -c --arg n "$tpl_name" '.[] | select(.name==$n)' <<<"$templates_json" | head -n1)"
  if [[ -z "$tpl_obj" ]]; then
    body="$(jq -nc \
      --argjson pid "$project_id" \
      --argjson inv "$inventory_id" \
      --argjson repo "$repo_id" \
      --argjson env "$env_id" \
      --arg n "$tpl_name" \
      --arg p "$playbook" \
      --arg a "$args_json" \
      '{project_id:$pid,inventory_id:$inv,repository_id:$repo,environment_id:$env,name:$n,playbook:$p,arguments:$a,app:"bash"}')"
    tpl_id="$(api_post "/api/project/${project_id}/templates" "$body" | jq -r '.id')"
    mark_changed "created template '$tpl_name'"
  else
    tpl_id="$(jq -r '.id' <<<"$tpl_obj")"
    current_cmp="$(jq -cS '{name,playbook,arguments,app,inventory_id,repository_id,environment_id}' <<<"$tpl_obj")"
    desired_cmp="$(jq -nc \
      --arg n "$tpl_name" --arg p "$playbook" --arg a "$args_json" \
      --argjson inv "$inventory_id" --argjson repo "$repo_id" --argjson env "$env_id" \
      '{name:$n,playbook:$p,arguments:$a,app:"bash",inventory_id:$inv,repository_id:$repo,environment_id:$env}' | jq -cS .)"
    if [[ "$current_cmp" != "$desired_cmp" ]]; then
      body="$(jq -nc \
        --argjson id "$tpl_id" \
        --argjson pid "$project_id" \
        --argjson inv "$inventory_id" \
        --argjson repo "$repo_id" \
        --argjson env "$env_id" \
        --arg n "$tpl_name" \
        --arg p "$playbook" \
        --arg a "$args_json" \
        '{id:$id,project_id:$pid,inventory_id:$inv,repository_id:$repo,environment_id:$env,name:$n,playbook:$p,arguments:$a,app:"bash"}')"
      api_put "/api/project/${project_id}/templates/${tpl_id}" "$body"
      mark_changed "updated template '$tpl_name'"
    fi
  fi
}

ensure_template "RALF Phase1 Infra Apply" "/usr/local/bin/ralf-semaphore-run" "[]" "$infra_env_id"
ensure_template "RALF Phase1 Config Apply" "/usr/local/bin/ralf-semaphore-run" "[]" "$config_env_id"
ensure_template "RALF Phase1 Smoke" "/usr/local/bin/ralf-semaphore-smoke" "[\"phase1\"]" "$smoke_env_id"

echo "PROJECT_ID=${project_id}"
echo "CHANGED=${changed}"
