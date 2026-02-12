# Terragrunt Setup - RALF Infrastructure

## Status: ✅ ABGESCHLOSSEN

**Datum:** 2026-02-12
**Task:** #15 - Terragrunt-Grundstruktur einrichten

## Übersicht

Terragrunt ist jetzt vollständig konfiguriert für die Orchestrierung aller OpenTofu Stacks.

## Erstellt

### 1. Root-Konfiguration: `iac/terragrunt.hcl`
- **Remote State:** Local backend (später MinIO)
- **Provider Generation:** Proxmox Provider (bpg/proxmox >= 0.66.0)
- **Common Inputs:** Proxmox API, Netzwerk, Template
- **State Location:** `terraform.tfstate.d/<stack>/terraform.tfstate`

### 2. Stack-Konfigurationen

#### PostgreSQL (`stacks/postgresql-fz/terragrunt.hcl`)
- **CT-ID:** 2010
- **IP:** 10.10.20.10/16
- **Dependencies:** Keine (Foundation Service)
- **Hooks:** Pre/Post-apply Logging

#### Semaphore (`stacks/semaphore-pg/terragrunt.hcl`)
- **CT-ID:** 10015
- **IP:** 10.10.100.15/16
- **Dependencies:** `../postgresql-fz`
- **Hooks:** PostgreSQL Dependency Check

#### Gitea (`stacks/gitea-fz/terragrunt.hcl`)
- **CT-ID:** 2012
- **IP:** 10.10.20.12/16
- **Dependencies:** `../postgresql-fz`
- **Hooks:** PostgreSQL Dependency Check

## Dependency Graph

```
postgresql-fz (2010)
    ├── semaphore-pg (10015)
    └── gitea-fz (2012)
```

## Wichtige Änderungen

### ✅ Behobene Probleme

1. **Duplicate Provider Configuration**
   - Problem: Stacks hatten eigene `versions.tf` mit Provider-Config
   - Lösung: `versions.tf` aus allen Stacks entfernt
   - Grund: Terragrunt generiert `provider.tf` automatisch

2. **Duplicate Terraform Block**
   - Problem: Mehrere `terraform {}` Blöcke pro Stack
   - Lösung: Zusammengeführt zu einem Block mit `source` + `hooks`

## Terraform/OpenTofu Versionen

- **OpenTofu:** 1.11.4 (installiert in CT 10015)
- **Terragrunt:** 0.99.1 (installiert in CT 10015)
- **Proxmox Provider:** 0.95.0 (automatisch installiert)

## Verwendung

### Einzelner Stack initialisieren

```bash
# Im Semaphore Container (CT 10015)
cd /opt/iac/stacks/postgresql-fz

export PROXMOX_API_URL='https://10.10.10.10:8006/api2/json'
export PROXMOX_API_TOKEN='root@pam!ralf-tofu=<secret>'

terragrunt init
terragrunt plan
terragrunt apply
```

### Alle Stacks orchestrieren

**ACHTUNG:** Noch nicht getestet! Container existieren bereits via Bootstrap-Skripte.

```bash
cd /opt/iac

# Alle Stacks initialisieren (respektiert Dependencies)
terragrunt graph-dependencies

# Plan für alle Stacks
terragrunt plan

# Apply für alle Stacks (respektiert Reihenfolge)
terragrunt apply
```

## Nächste Schritte

### Für Production-Einsatz:

1. **Remote State Backend**
   - MinIO oder S3-kompatiblen Storage deployen
   - `remote_state` in `terragrunt.hcl` umstellen
   - State migrieren: `terragrunt init -migrate-state`

2. **State Import**
   - Bestehende Container in OpenTofu State importieren
   - Oder: Container via Bootstrap → dann OpenTofu für neue Container

3. **CI/CD Integration**
   - Semaphore Pipeline für `terragrunt plan`
   - Semaphore Pipeline für `terragrunt apply`
   - Approval-Gate vor apply

4. **Root Config umbenennen**
   - `terragrunt.hcl` → `root.hcl` (neue Best Practice)
   - Warnung: "Using `terragrunt.hcl` as root is anti-pattern"

## Bekannte Einschränkungen

### Container bereits deployed
Die Container wurden via Bootstrap-Skripte erstellt. Terragrunt/OpenTofu kennt sie nicht (kein State).

**Optionen:**
- **A) Import:** Bestehende Container in State importieren
  ```bash
  terragrunt import proxmox_virtual_environment_container.postgresql 2010
  ```
- **B) Hybrid:** Bootstrap für P1, Terragrunt für P2+
- **C) Neu aufsetzen:** Container löschen, via Terragrunt neu deployen

**Empfehlung:** Option B für jetzt, später auf C umstellen

## Test-Ergebnisse

```bash
# PostgreSQL Stack
✓ terragrunt init successful
✓ Provider bpg/proxmox v0.95.0 installed

# Gitea Stack
✓ terragrunt init successful
✓ Dependencies resolved

# Semaphore Stack
✓ terragrunt init successful
✓ Dependencies resolved
```

## Rollback

Falls Probleme auftreten:

```bash
# State löschen
cd /opt/iac
rm -rf terraform.tfstate.d/

# Cache löschen
cd /opt/iac/stacks
find . -name '.terragrunt-cache' -type d -exec rm -rf {} +

# Neu initialisieren
terragrunt init
```

## Dokumentation

- **Terragrunt Docs:** https://terragrunt.gruntwork.io/
- **OpenTofu Docs:** https://opentofu.org/docs/
- **Proxmox Provider:** https://registry.terraform.io/providers/bpg/proxmox/latest/docs

## Lessons Learned

1. **Provider-Generierung:** Terragrunt übernimmt Provider-Config vollständig
2. **State Management:** Local State ist OK für Entwicklung, nicht für Production
3. **Dependencies:** Terragrunt respektiert `dependencies {}` Block automatisch
4. **Hooks:** Before/After Hooks für Logging und Checks sehr nützlich
