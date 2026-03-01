# Phase 3/4 Runbook PostgreSQL

## Phase 3: OpenTofu Plan (Gate 2)

```bash
cd infrastructure/opentofu/postgresql-lxc
export TF_VAR_proxmox_endpoint="https://pve-deploy:8006/api2/json"
export TF_VAR_proxmox_api_token="${PROXMOX_API_TOKEN}"
tofu init
tofu plan
```

## Phase 4: Ansible Prepare/Deploy/Verify (Gate 3)

```bash
cd automation/ansible
ansible-galaxy collection install -r collections/requirements.yml

export RALF_POSTGRES_POSTGRES_PASSWORD="${INJECTED_SECRET}"
export RALF_POSTGRES_RALF_USER_PASSWORD="${INJECTED_SECRET}"

ansible-playbook -i inventory/hosts.ini playbooks/postgresql/prepare.yml
ansible-playbook -i inventory/hosts.ini playbooks/postgresql/deploy.yml
ansible-playbook -i inventory/hosts.ini playbooks/postgresql/verify.yml
```

## Gate 3

- `OK`: alle 3 Playbooks gruen
- `Warnung`: prepare/deploy gruen, verify instabil
- `Blocker`: deploy oder verify fehlschlaegt
