# Credential-Liste – Vollstaendig

Alle Passwoerter und Secrets, die fuer das RALF-Deployment benoetigt werden.
Alle Passwoerter werden in Vaultwarden gespeichert (sobald Phase 2 abgeschlossen).

**WICHTIG:** Keine Passwoerter im Git-Repository! Alle Secrets werden
ueber Semaphore-Variablen oder --extra-vars uebergeben.

---

## Infrastruktur-Credentials

| # | Secret                         | Wo anlegen                   | Wofuer                     |
|---|--------------------------------|------------------------------|----------------------------|
| 1 | Proxmox API Token ID           | Proxmox UI                   | OpenTofu Provider          |
| 2 | Proxmox API Token Secret       | Proxmox UI                   | OpenTofu Provider          |
| 3 | SSH-Keypair (ralf-ansible)     | ssh-keygen auf Semaphore     | Ansible-Zugriff            |
| 38| OPNsense API Key               | OPNsense UI                  | Caddy + DNS via API        |
| 39| OPNsense API Secret            | OPNsense UI                  | Caddy + DNS via API        |

## Datenbank-Credentials (PostgreSQL)

| # | Secret                         | Wo anlegen                   | Wofuer                     |
|---|--------------------------------|------------------------------|----------------------------|
| 4 | PostgreSQL Superuser-Passwort  | bootstrap/create-postgresql  | DB-Administration          |
| 5 | semaphore DB-Passwort          | provision-databases.yml      | Semaphore → PostgreSQL     |
| 6 | gitea DB-Passwort              | provision-databases.yml      | Gitea → PostgreSQL         |
| 7 | vaultwarden DB-Passwort        | provision-databases.yml      | Vaultwarden → PostgreSQL   |
| 8 | netbox DB-Passwort             | provision-databases.yml      | NetBox → PostgreSQL        |
| 9 | synapse DB-Passwort            | provision-databases.yml      | Synapse → PostgreSQL       |
| 10| n8n DB-Passwort                | provision-databases.yml      | n8n → PostgreSQL           |

## Service-Admin-Credentials (Kolja)

| # | Secret                         | Dienst         | User                |
|---|--------------------------------|----------------|---------------------|
| 11| Semaphore Admin-Passwort       | Semaphore      | kolja               |
| 12| Gitea Admin-Passwort           | Gitea          | kolja               |
| 13| Vaultwarden Master-Passwort    | Vaultwarden    | kolja@homelab.lan   |
| 14| NetBox Admin-Passwort          | NetBox         | kolja               |
| 15| Snipe-IT Admin-Passwort        | Snipe-IT       | kolja               |
| 16| Grafana Admin-Passwort         | Grafana        | kolja               |
| 17| n8n Admin-Passwort             | n8n            | kolja               |
| 18| Synapse Admin-Passwort         | Synapse        | kolja               |
| 19| Mail-Account-Passwort          | Maddy          | kolja@homelab.lan   |

## Service-Admin-Credentials (Ralf / Bot)

| # | Secret                         | Dienst         | User                |
|---|--------------------------------|----------------|---------------------|
| 20| Semaphore Admin-Passwort       | Semaphore      | ralf                |
| 21| Gitea Admin-Passwort           | Gitea          | ralf                |
| 22| Vaultwarden Master-Passwort    | Vaultwarden    | ralf@homelab.lan    |
| 23| NetBox Admin-Passwort          | NetBox         | ralf                |
| 24| Snipe-IT Admin-Passwort        | Snipe-IT       | ralf                |
| 25| Grafana Admin-Passwort         | Grafana        | ralf                |
| 26| n8n Admin-Passwort             | n8n            | ralf                |
| 27| Synapse Admin-Passwort         | Synapse        | ralf                |
| 28| Mail-Account-Passwort          | Maddy          | ralf@homelab.lan    |

## API-Tokens und Service-Secrets

| # | Secret                         | Wo anlegen           | Wofuer                          |
|---|--------------------------------|----------------------|---------------------------------|
| 29| Vaultwarden Admin-Token        | Deploy-Playbook      | Admin-Panel Zugriff             |
| 30| NetBox Secret-Key              | Deploy-Playbook      | Django Crypto                   |
| 31| NetBox API-Token               | NetBox UI            | n8n → NetBox Integration        |
| 32| Gitea API-Token                | Gitea UI             | n8n → Gitea, Semaphore          |
| 33| Grafana API-Token              | Grafana UI           | n8n → Grafana                   |
| 34| Synapse Registration Secret    | Deploy-Playbook      | User-Registrierung              |
| 35| Matrix Bot Access Token        | Matrix Login API     | n8n → Matrix Bot                |
| 36| Snipe-IT App-Key               | artisan key:generate | Laravel Encryption              |
| 37| Claude API Key                 | console.anthropic.com| KI-Integration in n8n           |

## Semaphore-Variablen (alle Secrets zentral)

Folgende Variablen muessen in Semaphore unter "Environment" angelegt werden:

```
PROXMOX_API_URL=https://10.10.10.10:8006/api2/json
PROXMOX_API_TOKEN_ID=root@pam!ralf-tofu
PROXMOX_API_TOKEN_SECRET=<secret>

PG_SUPERUSER_PASS=<secret>
SEMAPHORE_DB_PASS=<secret>
GITEA_DB_PASS=<secret>
VAULTWARDEN_DB_PASS=<secret>
NETBOX_DB_PASS=<secret>
SYNAPSE_DB_PASS=<secret>
N8N_DB_PASS=<secret>

VAULTWARDEN_ADMIN_TOKEN=<secret>
NETBOX_SECRET_KEY=<secret>
SYNAPSE_REGISTRATION_SECRET=<secret>
SNIPEIT_APP_KEY=<secret>

KOLJA_GITEA_PASS=<secret>
KOLJA_GRAFANA_PASS=<secret>
KOLJA_NETBOX_PASS=<secret>
KOLJA_SNIPEIT_PASS=<secret>
KOLJA_N8N_PASS=<secret>
KOLJA_SYNAPSE_PASS=<secret>
KOLJA_MAIL_PASS=<secret>

RALF_GITEA_PASS=<secret>
RALF_GRAFANA_PASS=<secret>
RALF_NETBOX_PASS=<secret>
RALF_SNIPEIT_PASS=<secret>
RALF_N8N_PASS=<secret>
RALF_SYNAPSE_PASS=<secret>
RALF_MAIL_PASS=<secret>

CLAUDE_API_KEY=<secret>
```

---

## Passwort-Generierung

Empfohlene Methode fuer sichere Passwoerter:
```bash
# 32 Zeichen, alphanumerisch + Sonderzeichen:
openssl rand -base64 32

# Fuer DB-Passwoerter (ohne Sonderzeichen, vermeidet Escape-Probleme):
openssl rand -hex 24

# Fuer Tokens (64 Zeichen):
openssl rand -hex 32
```

---

## Checkliste

- [ ] Alle Passwoerter (#1-#37) generiert
- [ ] Alle Passwoerter in Vaultwarden gespeichert
- [ ] Alle Semaphore-Variablen angelegt
- [ ] Proxmox API Token erstellt und getestet
- [ ] SSH-Key erstellt und auf allen Containern hinterlegt
- [ ] Kein einziges Passwort im Git-Repository
