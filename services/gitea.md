# Service-Steckbrief – Gitea

## Kurzbeschreibung

Gitea ist das **selbst-gehostete Git-Repository** im RALF-Homelab. Es ersetzt GitHub als Remote und wird zur Single Source of Truth fuer IaC-Stacks, Pipelines, Dokumentation und Konfigurationen.

Gitea laeuft in der **Functional Zone** und ist ein **P1 Core-Service**.

---

## Zweck (Warum existiert der Dienst?)

* Eigenstaendiges Git-Hosting (Unabhaengigkeit von GitHub)
* Single Source of Truth fuer alle RALF-Repositories
* Integration mit Semaphore (Webhooks, Repository-Zugriff)
* Spaeter: externe Erreichbarkeit ueber OPNsense/Caddy (otta.zone)

---

## Zone / Kritikalitaet

* **Zone:** Functional
* **Kritikalitaet:** P1 (Automatisierungs-Kern, Source of Truth)

---

## Netzwerk

* IP-Bereich: **20 (Datenbanken/DevTools)** gemaess `docs/network-baseline.md`
* IP: 10.10.20.12
* HTTP-Port: 3000 (intern)
* SSH-Port: 2222 (intern)
* Extern: spaeter ueber OPNsense/Caddy (gitea.otta.zone)

Netzwerk-Policy:

* Statische IP
* Zugriff nur aus erlaubten Netzen/Zonen (Firewall via OPNsense)

---

## Abhaengigkeiten

Pflicht:

* P0 Netzwerk-Basis (OPNsense, DNS, Routing)
* PostgreSQL (svc-postgres, 10.10.20.10:5432) – Datenbank-Backend

Optional (spaeter):

* Monitoring/Logging (Bereich 80)
* Reverse Proxy (Caddy auf OPNsense) fuer externe Erreichbarkeit
* LDAP/OIDC (Bereich 50) fuer Single Sign-On

---

## Datenhaltung

* Repositories: `/var/lib/gitea/data/gitea-repositories`
* Datenbank: PostgreSQL (extern, svc-postgres)
* LFS: aktiviert, lokal gespeichert

MVP-Anforderung:

* Regelmaessige Backups der Repositories + DB-Dumps

---

## Eingaben (Inputs)

* PostgreSQL-Verbindungsdaten (Host, Port, DB, User, Pass)
* SSH-Keys fuer Semaphore-Zugriff
* Konfiguration (app.ini)

---

## Ausgaben (Outputs)

* Git-Repositories (HTTP + SSH)
* Web UI (intern :3000)
* Webhooks fuer Semaphore-Trigger

---

## Betriebsmodell (Soll-Verhalten)

Bootstrap (MVP):

* Single-Instance Gitea mit PostgreSQL-Backend
* RALF-Repository von GitHub migriert
* Semaphore nutzt Gitea als Repository-Quelle

Spaeter:

* Externe Erreichbarkeit (otta.zone)
* Backup-Automatisierung
* LDAP/OIDC-Integration

---

## Tests (Definition of Done)

Minimal (MVP):

* Gitea Web UI erreichbar (HTTP :3000)
* SSH-Clone funktioniert (:2222)
* PostgreSQL-Verbindung aktiv
* Ein Test-Repository kann erstellt werden

Erweitert:

* Webhook an Semaphore funktioniert
* Migration von GitHub erfolgreich

---

## Rollback / Recovery

* Container-Snapshot `pre-install` vor Konfiguration
* Bei fehlerhaften Aenderungen: Rollback auf Snapshot
* Daten-Recovery ueber PostgreSQL-Backup + Repository-Backup

---

## Sicherheits-Policy

* Keine externe Erreichbarkeit ohne Caddy/OPNsense
* Auth-Policy: starke Passwoerter, spaeter LDAP/OIDC
* Credentials ausschliesslich in Runner-Secrets, nicht im Git
* SSH-Keys: nur autorisierte Keys

---

## Offene Punkte

* Migration-Workflow GitHub -> Gitea definieren
* Backup-Medium/Ziel (Bereich 30)
* Webhook-Integration mit Semaphore konfigurieren
* Externe Domain (gitea.otta.zone) in Caddy einrichten

---

## Referenzen

* `docs/network-baseline.md`
* `healthchecks/network-health.yml`
* `docs/conventions.md`
* `services/catalog.md`
* `iac/stacks/gitea-fz/`

---

## Aenderungslog

* Initialer Steckbrief erstellt
