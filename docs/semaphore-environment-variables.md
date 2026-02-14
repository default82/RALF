# Semaphore Environment Variables

## Task #49: Environment Variables konfigurieren

Environment Variables in Semaphore erlauben es, Secrets und Konfiguration zentral zu verwalten, ohne sie im Repository zu speichern.

---

## Übersicht der benötigten Variables

### PostgreSQL (CT 2010)

| Variable | Wert | Beschreibung |
|----------|------|--------------|
| `POSTGRES_MASTER_PASS` | *(aus credentials.env)* | PostgreSQL root password |

### MariaDB (CT 2011)

| Variable | Wert | Beschreibung |
|----------|------|--------------|
| `MARIADB_ROOT_PASS` | *(aus credentials.env)* | MariaDB root password |

### Gitea (CT 2012)

| Variable | Wert | Beschreibung |
|----------|------|--------------|
| `GITEA_PG_PASS` | *(aus credentials.env)* | Gitea PostgreSQL password |
| `GITEA_ADMIN1_USER` | kolja | Primary admin username |
| `GITEA_ADMIN1_EMAIL` | kolja@homelab.lan | Primary admin email |
| `GITEA_ADMIN1_PASS` | *(aus credentials.env)* | Primary admin password |

### NetBox (CT 4030)

| Variable | Wert | Beschreibung |
|----------|------|--------------|
| `NETBOX_PG_PASS` | *(aus credentials.env)* | NetBox PostgreSQL password |
| `NETBOX_SECRET_KEY` | *(aus credentials.env)* | Django secret key |
| `NETBOX_SUPERUSER_PASS` | *(aus credentials.env)* | Admin password |

### Snipe-IT (CT 4040)

| Variable | Wert | Beschreibung |
|----------|------|--------------|
| `SNIPEIT_MYSQL_PASS` | *(aus credentials.env)* | Snipe-IT MySQL password |
| `SNIPEIT_APP_KEY` | *(aus credentials.env)* | Laravel app key |
| `SNIPEIT_ADMIN_USER` | admin | Admin username |
| `SNIPEIT_ADMIN_EMAIL` | admin@homelab.lan | Admin email |
| `SNIPEIT_ADMIN_PASS` | *(aus credentials.env)* | Admin password |

### Vaultwarden (CT 2013)

| Variable | Wert | Beschreibung |
|----------|------|--------------|
| `VAULTWARDEN_ADMIN_TOKEN` | *(aus credentials.env)* | Admin panel token |
| `VAULTWARDEN_PG_PASS` | *(aus credentials.env)* | PostgreSQL password |

---

## Credentials aus credentials.env extrahieren

```bash
source /var/lib/ralf/credentials.env

# Alle relevanten Variablen anzeigen
echo "=== PostgreSQL ==="
echo "POSTGRES_MASTER_PASS=${POSTGRES_MASTER_PASS}"

echo -e "\n=== MariaDB ==="
echo "MARIADB_ROOT_PASS=${MARIADB_ROOT_PASS}"

echo -e "\n=== Gitea ==="
echo "GITEA_PG_PASS=${GITEA_PG_PASS}"
echo "GITEA_ADMIN1_USER=${GITEA_ADMIN1_USER}"
echo "GITEA_ADMIN1_EMAIL=${GITEA_ADMIN1_EMAIL}"
echo "GITEA_ADMIN1_PASS=${GITEA_ADMIN1_PASS}"

echo -e "\n=== NetBox ==="
echo "NETBOX_PG_PASS=${NETBOX_PG_PASS}"
echo "NETBOX_SECRET_KEY=${NETBOX_SECRET_KEY}"
echo "NETBOX_SUPERUSER_PASS=${NETBOX_SUPERUSER_PASS}"

echo -e "\n=== Snipe-IT ==="
echo "SNIPEIT_MYSQL_PASS=${SNIPEIT_MYSQL_PASS}"
echo "SNIPEIT_APP_KEY=${SNIPEIT_APP_KEY}"
echo "SNIPEIT_ADMIN_USER=${SNIPEIT_ADMIN_USER}"
echo "SNIPEIT_ADMIN_EMAIL=${SNIPEIT_ADMIN_EMAIL}"
echo "SNIPEIT_ADMIN_PASS=${SNIPEIT_ADMIN_PASS}"

echo -e "\n=== Vaultwarden ==="
echo "VAULTWARDEN_ADMIN_TOKEN=${VAULTWARDEN_ADMIN_TOKEN}"
echo "VAULTWARDEN_PG_PASS=${VAULTWARDEN_PG_PASS}"
```

---

## Environment Variables in Semaphore hinzufügen

### Methode 1: Via Web-UI (Empfohlen)

#### Pro Project (für alle Tasks im Project)

1. **Login:** http://10.10.100.15:3000
2. **Project** auswählen (RALF Infrastructure)
3. **Environment** Tab
4. **+ New Environment Variable**

**Für jede Variable:**
- **Name:** `VARIABLE_NAME` (z.B. `POSTGRES_MASTER_PASS`)
- **Value:** *(Wert aus credentials.env)*
- **Secret:** ✅ (Checkbox aktivieren für sensible Werte)
5. **Create** klicken

**Vorteile:**
- Variables sind verfügbar für alle Tasks im Project
- Secrets werden verschlüsselt gespeichert
- Zentrale Verwaltung

#### Pro Task Template (für einzelne Tasks)

1. **Task Templates** → Template auswählen
2. **Environment** Section
3. **+ Add Variable**
4. Name/Value eingeben
5. **Save Template**

**Vorteile:**
- Task-spezifische Konfiguration
- Überschreibt Project-Level Variables bei Konflikten

### Methode 2: Via Environment File im Repository

**Datei erstellen:** `iac/ansible/env/production.env`

```bash
# PostgreSQL
POSTGRES_MASTER_PASS={{ vault_postgres_master_pass }}

# MariaDB
MARIADB_ROOT_PASS={{ vault_mariadb_root_pass }}

# Gitea
GITEA_PG_PASS={{ vault_gitea_pg_pass }}
GITEA_ADMIN1_USER=kolja
GITEA_ADMIN1_EMAIL=kolja@homelab.lan
GITEA_ADMIN1_PASS={{ vault_gitea_admin1_pass }}

# NetBox
NETBOX_PG_PASS={{ vault_netbox_pg_pass }}
NETBOX_SECRET_KEY={{ vault_netbox_secret_key }}
NETBOX_SUPERUSER_PASS={{ vault_netbox_superuser_pass }}

# Snipe-IT
SNIPEIT_MYSQL_PASS={{ vault_snipeit_mysql_pass }}
SNIPEIT_APP_KEY={{ vault_snipeit_app_key }}
SNIPEIT_ADMIN_USER=admin
SNIPEIT_ADMIN_EMAIL=admin@homelab.lan
SNIPEIT_ADMIN_PASS={{ vault_snipeit_admin_pass }}
```

**Hinweis:** Secrets mit Ansible Vault verschlüsseln!

```bash
ansible-vault create iac/ansible/env/secrets.yml
```

---

## Ansible Playbook Integration

### Playbook mit Environment Variables

```yaml
---
- name: Deploy Service
  hosts: target
  become: yes

  vars:
    # Variables werden aus Semaphore Environment übernommen
    db_password: "{{ lookup('env', 'SERVICE_DB_PASS') }}"
    admin_password: "{{ lookup('env', 'SERVICE_ADMIN_PASS') }}"

  tasks:
    - name: Configure service
      ansible.builtin.template:
        src: config.j2
        dest: /etc/service/config.yml
      vars:
        database_password: "{{ db_password }}"
```

### Environment Variables in Templates

**Template:** `roles/service/templates/config.j2`

```yaml
database:
  password: {{ database_password }}

admin:
  username: {{ lookup('env', 'SERVICE_ADMIN_USER') }}
  password: {{ admin_password }}
```

---

## Verifikation

### Test ob Variables verfügbar sind

**Task Template erstellen:** `Environment Test`

**Playbook:** `tests/env-test.yml`

```yaml
---
- name: Test Environment Variables
  hosts: localhost
  connection: local
  gather_facts: no

  tasks:
    - name: Check PostgreSQL Password
      ansible.builtin.debug:
        msg: "POSTGRES_MASTER_PASS is {{ 'set' if lookup('env', 'POSTGRES_MASTER_PASS') else 'NOT set' }}"

    - name: Check MariaDB Password
      ansible.builtin.debug:
        msg: "MARIADB_ROOT_PASS is {{ 'set' if lookup('env', 'MARIADB_ROOT_PASS') else 'NOT set' }}"

    - name: Check Gitea Password
      ansible.builtin.debug:
        msg: "GITEA_PG_PASS is {{ 'set' if lookup('env', 'GITEA_PG_PASS') else 'NOT set' }}"
```

**Task ausführen:**
- Sollte "set" für alle konfigurierten Variables zeigen
- "NOT set" bedeutet Variable fehlt

---

## Best Practices

### Security

1. ✅ **Secrets als "Secret" markieren** - werden im UI verschleiert
2. ✅ **Keine Secrets im Repository** - nur in Semaphore Environment
3. ✅ **Ansible Vault für sensitive Dateien** - verschlüsselte Secrets
4. ❌ **Nie Secrets in Task-Logs ausgeben** - `no_log: true` verwenden

### Organization

1. **Naming Convention:**
   - Service-Prefix: `SERVICENAME_*`
   - Type-Suffix: `*_PASS`, `*_TOKEN`, `*_KEY`
   - Beispiel: `GITEA_PG_PASS`, `NETBOX_SECRET_KEY`

2. **Gruppierung:**
   - Pro Service ein Comment/Section
   - Zusammengehörige Variables gruppieren

3. **Dokumentation:**
   - Description-Feld in Semaphore nutzen
   - Referenz zu `credentials.env` Location

---

## Troubleshooting

### Variable not found in playbook

**Fehler:** "POSTGRES_MASTER_PASS is not defined"

**Lösung:**
```bash
# 1. Prüfe ob Variable in Semaphore Environment ist
# Project → Environment → sollte Variable sehen

# 2. Prüfe Playbook
ansible.builtin.debug:
  var: lookup('env', 'POSTGRES_MASTER_PASS')

# 3. Prüfe ob Task die Environment übernimmt
# Task Settings → Environment → sollte vom Project erben
```

### Secret wird im Log angezeigt

**Problem:** Passwort erscheint im Task-Log

**Lösung:**
```yaml
- name: Sensitive Task
  ansible.builtin.shell: |
    echo "{{ db_password }}" > /tmp/config
  no_log: true  # ← Verhindert Log-Output
```

### Environment Variable überschreibt nicht

**Problem:** Project-Variable wird nicht von Task-Variable überschrieben

**Priorität:**
1. Task Template Environment (höchste)
2. Task Run Environment
3. Project Environment (niedrigste)

**Fix:** Variable auf höherer Ebene definieren

---

## Migration zu Ansible Vault

Für Produktiv-Einsatz: Secrets aus Semaphore → Ansible Vault

```bash
# 1. Vault-Datei erstellen
ansible-vault create iac/ansible/vault/production.yml

# 2. Secrets hinzufügen
vault_postgres_master_pass: "actual_password_here"
vault_mariadb_root_pass: "actual_password_here"

# 3. In Playbook verwenden
- name: Deploy with Vault
  hosts: target
  vars_files:
    - vault/production.yml
  vars:
    db_pass: "{{ vault_postgres_master_pass }}"
```

---

## Nächste Schritte

Nach Konfiguration der Environment Variables:

1. ✅ Variables in Semaphore hinterlegt
2. Test-Playbook ausführen zur Verifikation
3. Erste echte Deployment-Pipeline erstellen
4. Migration zu Ansible Vault planen (optional)

---

## Reference

- **credentials.env Location:** `/var/lib/ralf/credentials.env`
- **Semaphore Environment:** http://10.10.100.15:3000 → Project → Environment
- **Ansible Lookup:** https://docs.ansible.com/ansible/latest/plugins/lookup/env.html
- **Ansible Vault:** https://docs.ansible.com/ansible/latest/user_guide/vault.html
