# RALF Roadmap – Gesamtuebersicht

Ziel: RALF ist vollstaendig automatisiert deploybar (One-Liner) und kommuniziert
mit dem Operator (Kolja) ueber Matrix/Element. Alle Dienste laufen in LXC-Containern
auf Proxmox, orchestriert durch Semaphore, provisioniert mit OpenTofu + Terragrunt,
konfiguriert mit Ansible.

---

## Phasen

| Phase | Name                        | Status     | Abhaengigkeit |
|-------|-----------------------------|------------|---------------|
| 1     | Core Bootstrap              | In Arbeit  | P0 Netzwerk   |
| 2     | Sicherheit & Secrets        | Offen      | Phase 1       |
| 3     | Mail-Server                 | Offen      | Phase 1       |
| 4     | Reverse Proxy & DNS         | Offen      | Phase 1       |
| 5     | Observability               | Offen      | Phase 1, 4    |
| 6     | Plattform-Dienste           | Offen      | Phase 1, 2, 3 |
| 7     | Automatisierung & KI        | Offen      | Phase 1-6     |
| 8     | Kommunikation (Matrix/KI)   | Offen      | Phase 3, 7    |
| 9     | One-Liner Deploy            | Offen      | Phase 1-8     |

---

## Netzwerk-Plan (alle Dienste)

| Dienst        | Hostname        | IP            | CT-ID | Zone       | Oktett | Ports              |
|---------------|-----------------|---------------|-------|------------|--------|--------------------|
| OPNsense      | opnsense        | 10.10.0.1     | —     | Infra      | 0      | —                  |
| Proxmox       | pve-deploy      | 10.10.10.10   | —     | Mgmt       | 10     | 8006               |
| PostgreSQL    | svc-postgres    | 10.10.20.10   | 2010  | Functional | 20     | 5432               |
| Gitea         | svc-gitea       | 10.10.20.12   | 2012  | Functional | 20     | 3000, 2222         |
| Vaultwarden   | svc-vaultwarden | 10.10.30.10   | 3010  | Functional | 30     | 8080               |
| Mail (Maddy)  | svc-mail        | 10.10.40.10   | 4010  | Functional | 40     | 25, 587, 993       |
| NetBox        | svc-netbox      | 10.10.40.12   | 4012  | Functional | 40     | 8000               |
| Snipe-IT      | svc-snipeit     | 10.10.40.14   | 4014  | Functional | 40     | 8080               |
| Caddy         | (OPNsense)      | 10.10.0.1     | —     | Infra      | 0      | 80, 443            |
| Synapse       | svc-synapse     | 10.10.40.30   | 4030  | Functional | 40     | 8008, 8448         |
| Element       | svc-element     | 10.10.40.32   | 4032  | Functional | 40     | 8080               |
| Prometheus    | svc-prometheus  | 10.10.80.10   | 8010  | Functional | 80     | 9090               |
| Grafana       | svc-grafana     | 10.10.80.12   | 8012  | Functional | 80     | 3000               |
| Loki          | svc-loki        | 10.10.80.14   | 8014  | Functional | 80     | 3100               |
| Semaphore     | ops-semaphore   | 10.10.100.15  | 10015 | Playground | 100    | 3000               |
| n8n           | ops-n8n         | 10.10.100.20  | 10020 | Playground | 100    | 5678               |

---

## Admin-Benutzer (pro Dienst)

Jeder Dienst erhaelt zwei Admin-Accounts:

| Benutzer | E-Mail               | Rolle       |
|----------|----------------------|-------------|
| Kolja    | kolja@homelab.lan    | Admin/Owner |
| Ralf     | ralf@homelab.lan     | Admin/Bot   |

---

## Toolchain

| Tool       | Zweck                                    | Version     |
|------------|------------------------------------------|-------------|
| OpenTofu   | LXC-Container erstellen (deklarativ)     | >= 1.6.0    |
| Terragrunt | OpenTofu-Stacks orchestrieren            | >= 0.55.0   |
| Ansible    | Konfiguration innerhalb der Container    | >= 2.15     |
| Semaphore  | Pipeline-Ausfuehrung (Ansible + Scripts) | Latest      |
| Bash       | Bootstrap-Scripts, Health-Checks         | >= 5.0      |

---

## Dateien pro Phase

- `01-core-bootstrap.md` – Semaphore, PostgreSQL, Gitea
- `02-sicherheit.md` – Vaultwarden, Secrets-Management
- `03-mail.md` – Maddy Mail-Server
- `04-reverse-proxy.md` – Caddy, DNS, TLS
- `05-observability.md` – Prometheus, Grafana, Loki
- `06-plattform.md` – NetBox, Snipe-IT
- `07-automatisierung-ki.md` – n8n, KI-Anbindung
- `08-kommunikation.md` – Matrix/Synapse, Element
- `09-oneliner-deploy.md` – Terragrunt, Master-Pipeline
- `10-credentials.md` – Vollstaendige Credential-Liste
