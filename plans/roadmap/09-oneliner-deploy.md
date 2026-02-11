# Phase 9 – One-Liner Deploy (Terragrunt + Master-Pipeline)

Ziel: Das gesamte RALF-Homelab kann mit einem einzigen Befehl
von Grund auf deployed werden. Terragrunt orchestriert alle
OpenTofu-Stacks in der richtigen Reihenfolge, Semaphore fuehrt
Ansible-Konfiguration und Tests aus.

---

## 9.1 Terragrunt vollstaendig einrichten

### Root-Konfiguration: `iac/terragrunt.hcl`
- [ ] Gemeinsame Provider-Konfiguration (Proxmox)
- [ ] Gemeinsame Backend-Konfiguration (State-Speicherung)
- [ ] Gemeinsame Variablen (Gateway, DNS, Domain, Template)
- [ ] Remote State Konfiguration (lokal → spaeter PostgreSQL/S3)

### Stack-Terragrunt-Dateien erstellen

Jeder Stack erhaelt eine `terragrunt.hcl` mit Dependencies:

```
iac/stacks/
├── postgresql-fz/terragrunt.hcl      # Keine Dependencies
├── semaphore-pg/terragrunt.hcl        # Keine Dependencies
├── vaultwarden-fz/terragrunt.hcl      # depends: postgresql-fz
├── mail-fz/terragrunt.hcl             # Keine Dependencies
├── netbox-fz/terragrunt.hcl           # depends: postgresql-fz
├── snipeit-fz/terragrunt.hcl          # Keine Dependencies
├── prometheus-fz/terragrunt.hcl       # Keine Dependencies
├── grafana-fz/terragrunt.hcl          # Keine Dependencies
├── loki-fz/terragrunt.hcl             # Keine Dependencies
├── n8n-pg/terragrunt.hcl              # depends: postgresql-fz
├── synapse-fz/terragrunt.hcl          # depends: postgresql-fz
├── element-fz/terragrunt.hcl          # depends: synapse-fz
└── gitea-fz/terragrunt.hcl            # depends: postgresql-fz
```

### Fuer jeden Stack:
- [ ] `terragrunt.hcl` mit:
  ```hcl
  include "root" {
    path = find_in_parent_folders()
  }

  terraform {
    source = "./tofu"
  }

  dependency "postgresql" {
    config_path = "../postgresql-fz"
  }

  inputs = {
    # Stack-spezifische Variablen
  }
  ```

### Testen
- [ ] `cd iac/stacks && terragrunt run-all validate`
- [ ] `cd iac/stacks && terragrunt run-all plan`
- [ ] `cd iac/stacks && terragrunt graph-dependencies` (Abhaengigkeitsbaum anzeigen)

---

## 9.2 Master-Pipeline erstellen

### Semaphore Master-Pipeline: `pipelines/semaphore/deploy-all.yaml`

```yaml
name: deploy-all
description: "RALF Komplett-Deployment (One-Liner)"
jobs:
  # Phase 0: Vorpruefung
  - name: network-health
    command: "bash healthchecks/run-network-health.sh"

  - name: toolchain-check
    command: "bash tests/bootstrap/toolchain.sh"

  # Phase 1: Infrastruktur (Terragrunt)
  - name: terragrunt-plan
    command: "cd iac/stacks && terragrunt run-all plan --non-interactive"

  - name: terragrunt-apply
    command: "cd iac/stacks && terragrunt run-all apply --non-interactive"

  # Phase 2: Basis-Konfiguration (Ansible)
  - name: ansible-bootstrap-all
    command: >
      cd iac/ansible &&
      ansible-playbook -i inventory/hosts.yml playbooks/bootstrap-base.yml

  - name: ansible-deploy-postgresql
    command: >
      cd iac/ansible &&
      ansible-playbook -i inventory/hosts.yml playbooks/deploy-postgresql.yml

  - name: provision-databases
    command: >
      cd iac/ansible &&
      ansible-playbook -i inventory/hosts.yml playbooks/provision-databases.yml

  # Phase 3: Core Services
  - name: ansible-deploy-gitea
    command: >
      cd iac/ansible &&
      ansible-playbook -i inventory/hosts.yml playbooks/deploy-gitea.yml

  - name: ansible-deploy-vaultwarden
    command: >
      cd iac/ansible &&
      ansible-playbook -i inventory/hosts.yml playbooks/deploy-vaultwarden.yml

  - name: ansible-deploy-mail
    command: >
      cd iac/ansible &&
      ansible-playbook -i inventory/hosts.yml playbooks/deploy-mail.yml

  # Phase 4: Reverse Proxy (Caddy via OPNsense API)
  - name: configure-caddy-opnsense
    command: >
      cd iac/ansible &&
      ansible-playbook -i inventory/hosts.yml playbooks/configure-caddy.yml

  # Phase 5: Observability
  - name: ansible-deploy-prometheus
    command: >
      cd iac/ansible &&
      ansible-playbook -i inventory/hosts.yml playbooks/deploy-prometheus.yml

  - name: ansible-deploy-loki
    command: >
      cd iac/ansible &&
      ansible-playbook -i inventory/hosts.yml playbooks/deploy-loki.yml

  - name: ansible-deploy-grafana
    command: >
      cd iac/ansible &&
      ansible-playbook -i inventory/hosts.yml playbooks/deploy-grafana.yml

  # Phase 6: Plattform
  - name: ansible-deploy-netbox
    command: >
      cd iac/ansible &&
      ansible-playbook -i inventory/hosts.yml playbooks/deploy-netbox.yml

  - name: ansible-deploy-snipeit
    command: >
      cd iac/ansible &&
      ansible-playbook -i inventory/hosts.yml playbooks/deploy-snipeit.yml

  # Phase 7: Automatisierung
  - name: ansible-deploy-n8n
    command: >
      cd iac/ansible &&
      ansible-playbook -i inventory/hosts.yml playbooks/deploy-n8n.yml

  # Phase 8: Kommunikation
  - name: ansible-deploy-synapse
    command: >
      cd iac/ansible &&
      ansible-playbook -i inventory/hosts.yml playbooks/deploy-synapse.yml

  - name: ansible-deploy-element
    command: >
      cd iac/ansible &&
      ansible-playbook -i inventory/hosts.yml playbooks/deploy-element.yml

  # Phase 9: Smoke Tests (alle)
  - name: smoke-all
    command: |
      bash tests/bootstrap/smoke.sh
      bash tests/postgresql/smoke.sh
      bash tests/gitea/smoke.sh
      bash tests/vaultwarden/smoke.sh
      bash tests/mail/smoke.sh
      bash tests/caddy/smoke.sh
      bash tests/prometheus/smoke.sh
      bash tests/loki/smoke.sh
      bash tests/grafana/smoke.sh
      bash tests/netbox/smoke.sh
      bash tests/snipeit/smoke.sh
      bash tests/n8n/smoke.sh
      bash tests/synapse/smoke.sh
      bash tests/element/smoke.sh

  # Abschluss
  - name: deployment-report
    command: "echo 'RALF Deployment abgeschlossen. Alle Dienste laufen.'"
```

### One-Liner
- [ ] Der finale One-Liner (auf Semaphore oder lokal):
  ```bash
  # Via Semaphore API:
  curl -X POST http://10.10.100.15:3000/api/project/1/tasks \
    -H "Authorization: Bearer <token>" \
    -H "Content-Type: application/json" \
    -d '{"template_id": <deploy-all-template-id>}'
  ```
  ODER via CLI:
  ```bash
  cd iac/stacks && terragrunt run-all apply --non-interactive && \
  cd ../../iac/ansible && ansible-playbook -i inventory/hosts.yml playbooks/deploy-all.yml
  ```

---

## 9.3 Deploy-All Ansible Playbook

### `iac/ansible/playbooks/deploy-all.yml`
- [ ] Importiert alle einzelnen Playbooks in der richtigen Reihenfolge:
  ```yaml
  ---
  - import_playbook: deploy-postgresql.yml
  - import_playbook: provision-databases.yml
  - import_playbook: deploy-gitea.yml
  - import_playbook: deploy-vaultwarden.yml
  - import_playbook: deploy-mail.yml
  - import_playbook: configure-caddy.yml
  - import_playbook: deploy-prometheus.yml
  - import_playbook: deploy-loki.yml
  - import_playbook: deploy-grafana.yml
  - import_playbook: deploy-netbox.yml
  - import_playbook: deploy-snipeit.yml
  - import_playbook: deploy-n8n.yml
  - import_playbook: deploy-synapse.yml
  - import_playbook: deploy-element.yml
  ```

---

## 9.4 Idempotenz sicherstellen

### Alle Playbooks muessen idempotent sein:
- [ ] Mehrfaches Ausfuehren fuehrt zum gleichen Ergebnis
- [ ] Keine "changed"-Tasks wenn nichts zu aendern ist
- [ ] Handler werden nur bei echten Aenderungen getriggert
- [ ] Bootstrap-Scripts pruefen ob Container bereits existieren

### Tests fuer Idempotenz:
- [ ] Jedes Playbook zweimal hintereinander ausfuehren
- [ ] Beim zweiten Lauf: 0 changed Tasks erwartet
- [ ] `ansible-lint` auf alle Playbooks/Roles

---

## 9.5 Dokumentation

- [ ] `docs/deployment.md` – Vollstaendige Deployment-Anleitung
- [ ] `docs/disaster-recovery.md` – Wiederherstellungsplan
- [ ] `docs/runbook.md` – Operatives Handbuch fuer den Betrieb
- [ ] Alle Service-Steckbriefe aktuell
- [ ] Alle Smoke-Tests dokumentiert
- [ ] README.md aktualisieren (Bootstrap-Status, One-Liner Anleitung)

### Abnahmekriterien (Phase 9 – Endabnahme)
- [ ] `terragrunt run-all apply` erstellt alle Container fehlerfrei
- [ ] `ansible-playbook deploy-all.yml` konfiguriert alle Dienste fehlerfrei
- [ ] Alle Smoke-Tests bestehen
- [ ] Alle Dienste ueber Caddy/homelab.lan erreichbar
- [ ] Kolja kann ueber Element mit Ralf-Bot kommunizieren
- [ ] Ralf-Bot beantwortet "status" korrekt
- [ ] Alerts kommen in Matrix an
- [ ] Tagesbericht wird morgens gepostet
- [ ] Idempotenz: zweites `deploy-all` laeuft ohne Aenderungen durch
