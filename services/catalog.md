# Service-Katalog (RALF)

Dieser Katalog ist die **zentrale Übersicht** über geplante und existierende Dienste im Homelab.
Er dient als:

* Reihenfolge- und Prioritätsliste
* Abhängigkeitsmatrix für RALF
* Grundlage für Automatisierung (Intent → Plan → Change)

## Legende

### Priorität

* **P0** – Existenzkritisch (Basis, ohne die nichts anderes geht)
* **P1** – Automatisierungs-Kern (macht reproduzierbares Deploy möglich)
* **P2** – Plattform & Verwaltung (nutzt Kernservices)
* **P3** – Fach-/Komfortdienste
* **P4** – Experimente / KI

### Zone

* **Functional** – muss stabil laufen
* **Playground** – darf brechen

### IP-Bereiche (bindend)

Bezieht sich auf das **3. Oktett** im Netz `10.10.0.0/16` gemäß `docs/network-baseline.md`:

| Bereich | Bedeutung               |
| ------: | ----------------------- |
|       0 | Core / OPNsense         |
|      10 | Netzwerk-Infrastruktur  |
|      20 | Datenbanken             |
|      30 | Backup & Sicherheit     |
|      40 | Web & Admin             |
|      50 | Verzeichnisdienste      |
|      60 | Medien                  |
|      70 | Dokumentation & Wissen  |
|      80 | Monitoring & Logging    |
|      90 | KI & Datenverarbeitung  |
|     100 | Automatisierung         |
|     110 | Medien & Downloader     |
|     200 | Funktionale Sonderfälle |

**Gatekeeper-Regel:** Ohne grüne Network Health Checklist findet **kein Deploy** statt.

---

## P0 – Basis / Infrastruktur (außerhalb von RALF)

| Service                            | Zone       | IP-Bereich | Abhängigkeiten               | Status    |
| ---------------------------------- | ---------- | ---------: | ---------------------------- | --------- |
| OPNsense (inkl. DNS/DHCP)          | Functional |          0 | Internet/WAN, HW             | aktiv     |
| Reverse Proxy (Caddy auf OPNsense) | Functional |          0 | OPNsense                     | aktiv     |
| TP-Link (Switches/AP/Controller)   | Functional |         10 | OPNsense, Strom, Verkabelung | vorhanden |
| Proxmox Hosts (Cluster-Nodes)      | Functional |         10 | OPNsense, TP-Link            | teilweise |

**Notiz:** P0 wird von RALF **beobachtet**, aber nicht autonom verändert.

---

## P1 – Automatisierungs-Kern (RALF wird „handlungsfähig“)

| Service    | Zone       | IP-Bereich | Abhängigkeiten                                     | Status  |
| ---------- | ---------- | ---------: | -------------------------------------------------- | ------- |
| Semaphore  | Playground |        100 | P0, Git-Remote (Bootstrap: GitHub)                 | geplant |
| PostgreSQL | Functional |         20 | P0                                                 | geplant |
| Gitea      | Functional |         40 | PostgreSQL, Reverse Proxy (extern via `otta.zone`) | geplant |

**Wichtig:** „extern erreichbar“ bedeutet: **nur über OPNsense/Caddy**, der Dienst selbst bleibt intern.

---

## P2 – Plattform & Verwaltung

| Service                 | Zone       | IP-Bereich | Abhängigkeiten                                                              | Status  |
| ----------------------- | ---------- | ---------: | --------------------------------------------------------------------------- | ------- |
| NetBox                  | Functional |         40 | PostgreSQL, Gitea (Doku/SoT)                                                | geplant |
| Snipe-IT                | Functional |         40 | PostgreSQL, Mail (optional)                                                 | geplant |
| n8n                     | Playground |        100 | PostgreSQL, Git (Workflows als Code)                                        | geplant |
| Vaultwarden             | Functional |         30 | PostgreSQL (oder interner DB-Mode), Reverse Proxy intern/extern nach Policy | geplant |
| Foreman (falls genutzt) | Playground |         40 | DNS/DHCP-Policy beachten (OPNsense bleibt Authority)                        | geplant |

---

## P3 – Fach- & Komfortdienste

| Service         | Zone       | IP-Bereich | Abhängigkeiten                                     | Status  |
| --------------- | ---------- | ---------: | -------------------------------------------------- | ------- |
| sabNZBd         | Playground |        110 | P0 (Netz), optional Storage                        | geplant |
| Sonarr          | Playground |        110 | sabNZBd                                            | geplant |
| Radarr          | Playground |        110 | sabNZBd                                            | geplant |
| Paperless(-ngx) | Functional |         70 | PostgreSQL, Storage, Reverse Proxy (intern)        | geplant |
| Mail-Server     | Functional |         40 | DNS, Reverse Proxy/Ports, ggf. Postfix/DKIM Policy | geplant |

**Hinweis zum IP-Schema:** Kommunikation/Collaboration-Dienste (Mail/Chat) haben keinen eigenen Bereich in der Baseline.
Für MVP werden sie **unter 40 (Web & Admin)** geführt, weil sie primär Web-/Admin-Oberflächen und Gateways sind.

---

## P4 – KI / Experimente

| Service                   | Zone       | IP-Bereich | Abhängigkeiten                                                 | Status  |
| ------------------------- | ---------- | ---------: | -------------------------------------------------------------- | ------- |
| EXO                       | Playground |         90 | GPU, Storage, Netzwerk                                         | geplant |
| RALF (Orchestrator/Brain) | Playground |         90 | Semaphore, Gitea, PostgreSQL (mind. eine Grund-KI)             | vision  |
| Synapse (Matrix)          | Functional |         40 | PostgreSQL, Reverse Proxy (extern via `otta.zone`), Monitoring | geplant |

**Flüchtigkeitsfehler korrigiert:** Synapse gehört **nicht** in 110 (Medien & Downloader). Für MVP wird Synapse unter **40 (Web & Admin)** geführt.

---

## Grundregeln (bindend)

* Kein Service wird deployed, wenn eine Abhängigkeit fehlt.
* Reihenfolge ist **P0 → P1 → P2 → P3 → P4**.
* Zonen sind Flags (keine eigenen Netze). „Playground“ darf nicht automatisch zu „Functional“ werden.
* Externe Erreichbarkeit erfolgt ausschließlich über **OPNsense/Caddy**.
* Jeder Service erhält später:

  * einen eigenen Steckbrief: `services/<name>.md`
  * mindestens einen Smoke-Test: `tests/<name>/...`
  * eine Rollback-Strategie (Snapshots)

## Änderungslog

* Initialer Katalog erstellt
* Korrigiert: Synapse-IP-Bereich (110 → 40) gemäß Network Baseline
