# Phase 6 – Plattform-Dienste (NetBox, Snipe-IT)

Ziel: Netzwerk- und Asset-Management sind zentral dokumentiert und
spiegeln den tatsaechlichen Zustand des Homelabs wider.

---

## 6.1 NetBox deployen

**Hostname:** svc-netbox | **IP:** 10.10.40.12 | **CT-ID:** 4012

NetBox ist die zentrale IPAM/DCIM-Instanz fuer RALF. Alle IPs, Container,
Netzwerke und Verkabelungen werden hier dokumentiert.

### Voraussetzungen
- [ ] PostgreSQL laeuft + DB `netbox` + User `netbox` existieren
- [ ] Redis als Cache (wird lokal im Container installiert)

### IaC erstellen

#### OpenTofu Stack: `iac/stacks/netbox-fz/`
- [ ] Standard-Stack
- [ ] ct_id=4012, ip=10.10.40.12/16, memory=2048, disk=16

#### Terragrunt: Dependency auf postgresql-fz

#### Ansible Role: `iac/ansible/roles/netbox/`
- [ ] `tasks/main.yml`:
  - Abhaengigkeiten installieren: python3, python3-pip, python3-venv,
    redis-server, libpq-dev, build-essential
  - NetBox herunterladen und entpacken (GitHub Release)
  - Python-venv erstellen, Requirements installieren
  - `configuration.py` deployen (DB-Verbindung, Redis, Secret-Key)
  - Datenbank migrieren: `python3 manage.py migrate`
  - Statische Dateien: `python3 manage.py collectstatic`
  - Superuser erstellen (Kolja):
    ```bash
    DJANGO_SUPERUSER_PASSWORD=<pw> python3 manage.py createsuperuser \
      --no-input --username kolja --email kolja@homelab.lan
    ```
  - Zweiten Superuser erstellen (Ralf):
    ```bash
    DJANGO_SUPERUSER_PASSWORD=<pw> python3 manage.py createsuperuser \
      --no-input --username ralf --email ralf@homelab.lan
    ```
  - Gunicorn-Konfiguration erstellen
  - Systemd-Services: netbox, netbox-rq
  - Aktivieren und starten
- [ ] `handlers/main.yml`: restart netbox
- [ ] `templates/configuration.py.j2`:
  ```python
  DATABASE = {
      'NAME': 'netbox',
      'USER': 'netbox',
      'PASSWORD': '{{ netbox_db_pass }}',
      'HOST': '10.10.20.10',
      'PORT': '5432',
  }
  REDIS = {
      'tasks': {'HOST': 'localhost', 'PORT': 6379, 'DATABASE': 0},
      'caching': {'HOST': 'localhost', 'PORT': 6379, 'DATABASE': 1},
  }
  SECRET_KEY = '{{ netbox_secret_key }}'
  ALLOWED_HOSTS = ['*']
  EMAIL = {
      'SERVER': '10.10.40.10',
      'PORT': 587,
      'FROM_EMAIL': 'netbox@homelab.lan',
  }
  ```

### Datenbank-Provisioning erweitern
- [ ] `provision-databases.yml` um NetBox-Eintrag ergaenzen:
  ```yaml
  - name: netbox
    owner: netbox
    password: "{{ netbox_db_pass }}"
  ```

### NetBox mit RALF-Daten befuellen
- [ ] Alle Netzwerke importieren (10.10.0.0/16, Subnets)
- [ ] Alle Container als Devices/VMs importieren
- [ ] IP-Adressen zuweisen
- [ ] Sites, Racks (logisch)
- [ ] Custom Fields fuer RALF-spezifische Daten:
  - `ralf_zone` (functional/playground)
  - `ralf_ct_id`
  - `ralf_priority` (P0-P4)

### Playbook + Bootstrap + Test + Pipeline
- [ ] `iac/ansible/playbooks/deploy-netbox.yml`
- [ ] `bootstrap/create-netbox.sh` (CT-ID: 4012)
- [ ] `tests/netbox/smoke.sh` (HTTP 8000, /api/)
- [ ] `pipelines/semaphore/deploy-netbox.yaml`

### Inventory + Service-Steckbrief + Catalog
- [ ] hosts.yml: Gruppe `platform`, Host svc-netbox
- [ ] `services/netbox.md`
- [ ] catalog pruefen/aktualisieren

### Benoetigte Credentials
- [ ] **netbox DB-Passwort**
- [ ] **NetBox Secret-Key** (50+ Zeichen, zufaellig generiert)
- [ ] **NetBox Admin-Passwort** (Kolja)
- [ ] **NetBox Admin-Passwort** (Ralf)
- [ ] **NetBox API-Token** (fuer Automatisierung, z.B. n8n)

### Abnahmekriterien
- [ ] NetBox Web-UI erreichbar auf Port 8000
- [ ] Login mit Kolja + Ralf funktioniert
- [ ] Alle RALF-Hosts sind als Devices importiert
- [ ] IP-Adressen stimmen mit inventory/hosts.yaml ueberein
- [ ] API erreichbar: GET /api/

---

## 6.2 Snipe-IT deployen

**Hostname:** svc-snipeit | **IP:** 10.10.40.14 | **CT-ID:** 4014

Snipe-IT verwaltet physische und virtuelle Assets
(Hardware, Lizenzen, Verbrauchsmaterial).

### Voraussetzungen
- [ ] PostgreSQL laeuft (ACHTUNG: Snipe-IT nutzt MySQL/MariaDB!)
- [ ] Entscheidung: MariaDB lokal installieren ODER PostgreSQL-Support pruefen
- [ ] Empfehlung: MariaDB lokal im Container (Snipe-IT hat keine native PG-Unterstuetzung)

### IaC erstellen

#### OpenTofu Stack: `iac/stacks/snipeit-fz/`
- [ ] Standard-Stack
- [ ] ct_id=4014, ip=10.10.40.14/16, memory=2048, disk=16

#### Ansible Role: `iac/ansible/roles/snipeit/`
- [ ] `tasks/main.yml`:
  - Abhaengigkeiten: php, composer, mariadb-server, nginx/apache
  - MariaDB lokal einrichten (DB: snipeit, User: snipeit)
  - Snipe-IT herunterladen (Git oder Release)
  - Composer install
  - `.env` konfigurieren
  - `php artisan key:generate`
  - `php artisan migrate`
  - Webserver konfigurieren
  - Aktivieren und starten
- [ ] `templates/snipeit.env.j2`:
  ```
  APP_URL=https://snipeit.homelab.lan
  DB_CONNECTION=mysql
  DB_HOST=127.0.0.1
  DB_DATABASE=snipeit
  DB_USERNAME=snipeit
  DB_PASSWORD={{ snipeit_db_pass }}
  MAIL_DRIVER=smtp
  MAIL_HOST=10.10.40.10
  MAIL_PORT=587
  MAIL_FROM_ADDR=snipeit@homelab.lan
  ```

### Admin-Accounts
- [ ] Erstkonfiguration ueber Web-UI:
  - Admin 1: kolja / kolja@homelab.lan
  - Admin 2: ralf / ralf@homelab.lan

### Playbook + Bootstrap + Test + Pipeline
- [ ] `iac/ansible/playbooks/deploy-snipeit.yml`
- [ ] `bootstrap/create-snipeit.sh` (CT-ID: 4014)
- [ ] `tests/snipeit/smoke.sh` (HTTP 8080)
- [ ] `pipelines/semaphore/deploy-snipeit.yaml`

### Inventory + Service-Steckbrief + Catalog
- [ ] hosts.yml: Gruppe `platform`, Host svc-snipeit
- [ ] `services/snipeit.md`

### Benoetigte Credentials
- [ ] **Snipe-IT DB-Passwort** (MariaDB lokal)
- [ ] **Snipe-IT App-Key** (generiert via artisan)
- [ ] **Snipe-IT Admin-Passwort** (Kolja)
- [ ] **Snipe-IT Admin-Passwort** (Ralf)

### Abnahmekriterien
- [ ] Snipe-IT Web-UI erreichbar
- [ ] Login mit Kolja + Ralf funktioniert
- [ ] Asset-Erfassung moeglich
- [ ] E-Mail-Benachrichtigungen funktionieren
