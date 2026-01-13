# Service-Steckbrief – PostgreSQL

## Kurzbeschreibung

PostgreSQL ist der **zentrale Datenbankdienst** im RALF-Homelab und bildet den stabilen Kern für viele Plattform- und Verwaltungsdienste (z. B. Gitea, NetBox, Snipe-IT, n8n, Synapse).

PostgreSQL läuft in der **Functional Zone** und gilt als **Core-Service**, der zuverlässig, dokumentiert und reproduzierbar betrieben werden muss.

---

## Zweck (Warum existiert der Dienst?)

* Bereitstellung einer stabilen relationalen Datenbank für RALF-Dienste
* Standardisierte Datenhaltung statt „jede App eigene DB“
* Grundlage für spätere Automatisierung (Provisioning von DBs/Users/Policies)

---

## Zone / Kritikalität

* **Zone:** Functional
* **Kritikalität:** P1 (Automatisierungs-Kern, Datenfundament)

---

## Netzwerk

* IP-Bereich: **20 (Datenbanken)** gemäß `docs/network-baseline.md`
* Erreichbarkeit: **intern**
* Extern: **nein** (keine Veröffentlichung nach außen)

Netzwerk-Policy:

* Statische IP
* Zugriff nur aus erlaubten Netzen/Zonen (Firewall-Regeln über OPNsense)

---

## Abhängigkeiten

Pflicht:

* P0 Netzwerk-Basis (OPNsense, DNS, Routing)
* Storage (ausreichend, zuverlässig)

Optional (später):

* Monitoring/Logging (Bereich 80)
* Backup-Ziel/Repository (Bereich 30)

---

## Datenhaltung

* Datenverzeichnis auf persistentem Storage
* Klare Trennung:

  * Daten (`PGDATA`)
  * Backups (separat)

MVP-Anforderung:

* Ein definiertes Backup-Verfahren existiert (mindestens logisch: Dump)

---

## Eingaben (Inputs)

* Konfigurationsparameter (Port, Listen-Adresse, Auth-Policy)
* Provisioning-Liste (geplant):

  * Datenbanken
  * Benutzer/Rollen
  * Zugriffsmatrizen pro Dienst

---

## Ausgaben (Outputs)

* Dienst erreichbar (TCP/5432 intern)
* Datenbanken/Users für Konsumentenservices
* Metriken/Logs (später an Monitoring/Logging)

---

## Betriebsmodell (Soll-Verhalten)

Bootstrap (MVP):

* Single-Instance PostgreSQL
* Stabile Konfiguration
* Geplante Backups (mindestens täglich)

Später:

* Backup/Restore automatisiert
* Optional HA/Replication (nicht MVP)

---

## Tests (Definition of Done)

Minimal (MVP):

* PostgreSQL läuft und akzeptiert Verbindungen
* DNS-Namenauflösung funktioniert (sofern genutzt)
* Ein Test-DB + Test-User kann erstellt werden
* Ein Test-Connect aus einem Playground-Container ist möglich (wenn policy erlaubt)

Erweitert:

* Backup läuft erfolgreich
* Restore-Test erfolgreich (mindestens einmal)

---

## Rollback / Recovery

* Container-Snapshot `pre-install` vor Konfiguration
* Bei fehlerhaften Änderungen: Rollback
* Datenbezogene Recovery basiert auf Backups (Snapshot ersetzt kein Backup)

---

## Sicherheits-Policy

* Keine externe Erreichbarkeit
* Auth-Policy: keine „trust“-Netze ohne explizite Freigabe
* Credentials ausschließlich in Runner-Secrets/Secret-Store, nicht im Git
* Principle of Least Privilege:

  * pro Dienst eigener DB-User
  * minimale Rechte

---

## Offene Punkte

* Backup-Medium/Ziel (Functional/Backup-Bereich 30)
* Monitoring-Integration (80)
* Naming/IDs/IPs final mit `docs/conventions.md` abgleichen

---

## Referenzen

* `docs/network-baseline.md`
* `healthchecks/network-health.yml`
* `docs/conventions.md`
* `services/catalog.md`

---

## Änderungslog

* Initialer Steckbrief erstellt
