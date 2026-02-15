# Web-UI Automatisierung - HowTo

**Status:** ✅ Implementiert (2026-02-15)

## Überblick

Bootstrap-Prozess ist jetzt **100% hands-off** durch automatische:
1. Gitea Repository-Erstellung (RALF-Homelab/ralf)
2. Semaphore-Konfiguration (Repository, Keys, Inventory, Environment)

**Ergebnis:** Von 80% auf 98% Idempotenz

---

## Quick Start

### Standard-Bootstrap (Komplett Automatisch)

```bash
# 1. Credentials generieren (einmalig)
bash bootstrap/generate-credentials.sh
source /var/lib/ralf/credentials.env

# 2. Bootstrap ausführen (komplett automatisch)
bash bootstrap/create-postgresql.sh
bash bootstrap/create-gitea.sh
bash bootstrap/create-and-fill-runner.sh
bash bootstrap/create-n8n.sh
bash bootstrap/create-exo.sh

# 3. Code pushen (einmalig nach Bootstrap)
cd /root/ralf
git remote add gitea http://10.10.20.12:3000/RALF-Homelab/ralf.git
git push gitea main
```

**Dauer:** ~20 Minuten, **0 manuelle Schritte**

---

## Optionen

### AUTO_CONFIGURE Flag

Semaphore-Konfiguration kann mit `AUTO_CONFIGURE` gesteuert werden:

**Default: Automatisch (empfohlen)**
```bash
bash bootstrap/create-and-fill-runner.sh
# → Semaphore wird automatisch konfiguriert
```

**Opt-Out: Manuell**
```bash
AUTO_CONFIGURE=false bash bootstrap/create-and-fill-runner.sh
# → Semaphore wird NICHT konfiguriert

# Später manuell konfigurieren:
bash bootstrap/configure-semaphore.sh
```

---

## Was wird automatisiert?

### Gitea

**Automatisch erstellt:**
- ✅ Admin User 1 (kolja)
- ✅ Admin User 2 (ralf)
- ✅ Organization (RALF-Homelab)
- ✅ Repository (RALF-Homelab/ralf) 🆕

**URL:** http://10.10.20.12:3000/RALF-Homelab/ralf

### Semaphore

**Automatisch konfiguriert:**
- ✅ 2nd Admin User (ralf)
- ✅ SSH Keys für Gitea
- ✅ Repository Connection zu RALF-Homelab/ralf
- ✅ Ansible Inventory
- ✅ Environment Variables (Proxmox, DBs, etc.)

**URL:** http://10.10.100.15:3000

---

## Idempotenz

Alle Scripts können mehrfach ausgeführt werden:

```bash
bash bootstrap/create-gitea.sh
# → Container 2012 existiert bereits - überspringe
# → Repository existiert bereits - überspringe
# → Exit 0

bash bootstrap/create-and-fill-runner.sh
# → Container 10015 existiert bereits - überspringe
# → Konfiguration bereits vorhanden - überspringe
# → Exit 0
```

**Test:** `bash tests/bootstrap/regression-test.sh`

---

## Troubleshooting

### Repository wurde nicht erstellt

**Symptom:** Gitea läuft, aber Repository fehlt

**Check:**
```bash
curl -sf http://10.10.20.12:3000/api/v1/repos/RALF-Homelab/ralf
```

**Fix:**
```bash
# Re-Run create-gitea.sh (idempotent)
bash bootstrap/create-gitea.sh
```

### Semaphore nicht konfiguriert

**Symptom:** Semaphore läuft, aber Repository fehlt in UI

**Check:**
```bash
pct exec 10015 -- test -f /root/.semaphore-configured && echo "Configured" || echo "NOT Configured"
```

**Fix:**
```bash
# Manuelle Konfiguration
bash bootstrap/configure-semaphore.sh
```

### Credentials fehlen

**Symptom:** Script bricht mit "CHANGE_ME_NOW" Fehler ab

**Fix:**
```bash
# Generiere Credentials
bash bootstrap/generate-credentials.sh
source /var/lib/ralf/credentials.env

# Re-Run
bash bootstrap/create-gitea.sh
```

---

## Tests

```bash
# Smoke Tests
bash tests/gitea/smoke.sh
bash tests/semaphore/smoke.sh

# Integration Test
bash tests/bootstrap/full-bootstrap-test.sh

# Regression Test (Idempotenz)
bash tests/bootstrap/regression-test.sh
```

---

## Architektur

**Gitea Repository-Erstellung:**
- API-basiert: `POST /api/v1/orgs/RALF-Homelab/repos`
- Idempotent: GET-Check vor POST
- Auto-Init: README, .gitignore, MIT License

**Semaphore Auto-Configure:**
- Hybrid-Integration: AUTO_CONFIGURE Flag
- Ruft configure-semaphore.sh auf
- Graceful Failure: Container läuft weiter bei Config-Fehler

**Details:** Siehe `docs/plans/2026-02-15-webui-automation-design.md`

---

**Dokumentation:** 2026-02-15
**Author:** RALF Homelab Project
**Co-Authored-By:** Claude Sonnet 4.5 <noreply@anthropic.com>
