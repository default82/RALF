# Service-Steckbrief – Semaphore

## Kurzbeschreibung

Semaphore ist der **Runner/Operator** im RALF-Setup. Er führt automatisierte Jobs aus (z. B. OpenTofu/Ansible/Scripts), zieht Code aus einem Git-Repository und erzeugt Logs/Ergebnisse.

Semaphore ist der **erste Dienst**, weil ohne Runner keine reproduzierbaren Deployments möglich sind.

---

## Zweck (Warum existiert der Dienst?)

* Ausführung der RALF-Pipelines: Bootstrap → Deploy → Tests → Doku
* Zentraler Ort für Job-Logs und Run-Historie
* Freigabe-Gate: Plan genehmigt → Run starten (später via Chat/Commands)

---

## Zone / Kritikalität

* **Zone:** Playground (Bootstrap-Phase)
* **Kritikalität:** P1 (Automatisierungs-Kern)

Später möglich:

* Migration/Neuaufsetzen in Functional, sobald DB/Backup/Monitoring sauber stehen.

---

## Netzwerk

* IP-Bereich: **100 (Automatisierung)** gemäß `docs/network-baseline.md`
* Erreichbarkeit: intern (Web UI)
* Extern: **nein** (kein Direkt-Publishing; falls später benötigt, nur über OPNsense/Caddy)

---

## Abhängigkeiten

Pflicht:

* P0 Netzwerk-Basis (OPNsense, DNS/DHCP, Routing)
* Git-Remote (Bootstrap: GitHub; später: Gitea)

Optional (später):

* PostgreSQL (für Persistenz/Skalierung)
* Monitoring/Logging (z. B. Loki/Grafana)

---

## Datenhaltung

Bootstrap (MVP):

* interne Datenbank: **lokal** (z. B. SQLite/embedded) – ausreichend für Start

Später:

* Umzug auf PostgreSQL (Functional)

Wichtig:

* Semaphore ist **nicht** der Source of Truth für IaC.
* IaC liegt im Git-Repo; der **OpenTofu-State** ist anfangs lokal, später migrierbar.

---

## Eingaben (Inputs)

* Repository URL (GitHub → später Gitea)
* Runner-Secrets (z. B. Proxmox API Token)
* Variablen (z. B. Ziel-Node, CT-ID, IP, Zone)

---

## Ausgaben (Outputs)

* Job-Logs
* Run-Status (grün/rot)
* Artefakte (geplant):

  * aktualisierte Change-Dokumente
  * Test-Reports

---

## Pipeline-Phasen (Soll-Verhalten)

1. **Smoke:** Repo checkout + Skript ausführen (`tests/bootstrap/smoke.sh`)
2. **Toolchain:** benötigte Tools installieren/prüfen (z. B. OpenTofu)
3. **Plan:** `tofu plan` + menschliche Freigabe
4. **Apply:** `tofu apply`
5. **Tests:** Smoke/Acceptance Tests pro Service
6. **Doku:** Change/Service-Doku aktualisieren

---

## Tests (Definition of Done)

Minimal (MVP):

* UI intern erreichbar
* Job „bootstrap smoke“ läuft grün
* Job „toolchain“ läuft grün

Erweitert:

* Proxmox API Reachability Test läuft grün

---

## Rollback / Recovery

* Container-Snapshot **vor** Installation (`pre-install`)
* Bei Fehlschlag: **rollback snapshot**, kein Repair
* RALF darf im Notfall Rollback triggern (Policy)

---

## Sicherheits-Policy

* Keine Secrets im Git
* Secrets ausschließlich in Semaphore-Variablen
* Externe Erreichbarkeit nur über OPNsense/Caddy (wenn überhaupt)

---

## Offene Punkte

* Persistenz-Strategie (lokal → PostgreSQL)
* Standard-Job-Templates (Bootstrap, Toolchain, Apply)
* Naming/IDs/IPs final mit `docs/conventions.md` abgleichen

---

## Referenzen

* `docs/network-baseline.md`
* `healthchecks/network-health.yml`
* `docs/conventions.md`
* `pipelines/semaphore/` (Blueprints)
* `tests/bootstrap/`

---

## Änderungslog

* Initialer Steckbrief erstellt
