# Web-UI Automatisierung für Bootstrap - Design

**Datum:** 2026-02-15
**Status:** ✅ Approved
**Ziel:** 100% Hands-Off Bootstrap ohne manuelle Web-UI-Schritte

---

## Executive Summary

**Problem:** Bootstrap-Prozess benötigt aktuell 2 manuelle Web-UI-Schritte:
1. Gitea: Repository `RALF-Homelab/ralf` manuell erstellen
2. Semaphore: `configure-semaphore.sh` manuell ausführen

**Lösung:** API-basierte Automatisierung:
- Gitea Repository-Erstellung via REST API
- Semaphore Auto-Configure via Hybrid-Integration (AUTO_CONFIGURE Flag)

**Ergebnis:**
- Von **80% idempotent** → **98% idempotent**
- Von **2 manuelle Schritte** → **0 manuelle Schritte**
- Bootstrap-Zeit: ~20 Minuten (unverändert), aber komplett automatisch

---

## Architecture Overview

### Bootstrap-Flow (Neu)

```
┌─────────────────────────────────────────────────────────┐
│ Phase 1: Infrastructure                                  │
└─────────────────────────────────────────────────────────┘
  bash bootstrap/create-postgresql.sh
  → CT 2010 @ 10.10.20.10 ✅

┌─────────────────────────────────────────────────────────┐
│ Phase 2: Git Repository (NEU: Vollständig automatisch)  │
└─────────────────────────────────────────────────────────┘
  bash bootstrap/create-gitea.sh
  → CT 2012 @ 10.10.20.12
  → Admin Users (kolja, ralf) ✅
  → Organization (RALF-Homelab) ✅
  → Repository (RALF-Homelab/ralf) 🆕 AUTOMATISCH

┌─────────────────────────────────────────────────────────┐
│ Phase 3: Automation Engine (NEU: Auto-Configure)        │
└─────────────────────────────────────────────────────────┘
  bash bootstrap/create-and-fill-runner.sh
  → CT 10015 @ 10.10.100.15
  → Semaphore Installation ✅
  → Auto-Configure (wenn AUTO_CONFIGURE=true):
     ├── Repository Connection 🆕 AUTOMATISCH
     ├── SSH Keys 🆕 AUTOMATISCH
     ├── Inventory 🆕 AUTOMATISCH
     └── Environment Variables 🆕 AUTOMATISCH

┌─────────────────────────────────────────────────────────┐
│ Phase 4: Orchestration Layer                            │
└─────────────────────────────────────────────────────────┘
  bash bootstrap/create-n8n.sh
  bash bootstrap/create-exo.sh

Ergebnis: RALF ist Self-Orchestration Ready! 🚀
```

### Änderungen an Bootstrap-Scripts

```
bootstrap/
├── create-gitea.sh              # +30 Zeilen (Repository-Erstellung)
├── create-and-fill-runner.sh    # +15 Zeilen (Auto-Configure Hook)
└── configure-semaphore.sh       # Unverändert (bereits vollständig)
```

---

## Component Details

### A) Änderungen in `create-gitea.sh`

**Einfügepunkt:** Nach Organization-Erstellung (Line ~389), vor Snapshot

**Neue Section: Repository-Erstellung**

```bash
### =========================
### 13) Erstelle Repository 'ralf'
### =========================

log "Erstelle Repository: RALF-Homelab/ralf"

pct_exec "$CTID" "
set -euo pipefail

# Prüfe ob Repository bereits existiert (via API)
if curl -sf http://localhost:${GITEA_HTTP_PORT}/api/v1/repos/RALF-Homelab/ralf 2>/dev/null | grep -q '\"name\":\"ralf\"'; then
  echo 'Repository RALF-Homelab/ralf existiert bereits'
else
  # Erstelle Repository via API
  RESPONSE=\$(curl -s -w \"\\n%{http_code}\" \
    -X POST http://localhost:${GITEA_HTTP_PORT}/api/v1/orgs/RALF-Homelab/repos \
    -u '${GITEA_ADMIN1_USER}:${GITEA_ADMIN1_PASS}' \
    -H 'Content-Type: application/json' \
    -d '{
      \"name\": \"ralf\",
      \"description\": \"RALF Homelab - Self-orchestrating infrastructure platform\",
      \"private\": true,
      \"auto_init\": true,
      \"default_branch\": \"main\",
      \"gitignores\": \"Go,Python,Terraform\",
      \"license\": \"MIT\",
      \"readme\": \"Default\"
    }')

  HTTP_CODE=\$(echo \"\$RESPONSE\" | tail -n1)
  BODY=\$(echo \"\$RESPONSE\" | head -n-1)

  if [[ \"\$HTTP_CODE\" == \"201\" ]]; then
    echo 'Repository RALF-Homelab/ralf erfolgreich erstellt'
  elif [[ \"\$HTTP_CODE\" == \"409\" ]]; then
    echo 'Repository existiert bereits (409 Conflict) - OK'
  elif [[ \"\$HTTP_CODE\" == \"401\" ]]; then
    echo 'ERROR: Authentifizierung fehlgeschlagen (401)'
    echo 'Prüfe GITEA_ADMIN1_USER und GITEA_ADMIN1_PASS'
    exit 1
  else
    echo \"ERROR: Unerwarteter HTTP Code: \$HTTP_CODE\"
    echo \"Response: \$BODY\"
    exit 1
  fi
fi
"
```

**Eigenschaften:**
- ✅ **Idempotent:** GET-Check vor POST
- ✅ **Error Handling:** HTTP-Status-Code-Validierung
- ✅ **Auto-Init:** Repository hat README.md und .gitignore
- ✅ **Credentials:** Aus credentials.env

---

### B) Änderungen in `create-and-fill-runner.sh`

**Einfügepunkt:** Ganz am Ende (Line ~320), vor "FERTIG"

**Neue Section: Auto-Configure**

```bash
### =========================
### 11) Auto-Configure Semaphore (Optional)
### =========================

if [[ "${AUTO_CONFIGURE:-true}" == "true" ]]; then
  log "Auto-Configure: Starte Semaphore-Konfiguration"
  log "  - Repository Connection"
  log "  - SSH Keys"
  log "  - Inventory"
  log "  - Environment Variables"

  # Führe configure-semaphore.sh aus
  SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
  if bash "${SCRIPT_DIR}/configure-semaphore.sh"; then
    log "✅ Semaphore-Konfiguration erfolgreich"
  else
    EXIT_CODE=$?
    log "❌ Semaphore-Konfiguration fehlgeschlagen (Exit: $EXIT_CODE)"
    log "Manuell beheben mit: bash bootstrap/configure-semaphore.sh"
    log "Container läuft weiter, aber Konfiguration unvollständig"
    # NICHT exit - Container ist deployed, nur Config fehlt
  fi
else
  log "AUTO_CONFIGURE=false - Überspringe Semaphore-Konfiguration"
  log "Für manuelle Konfiguration später:"
  log "  bash bootstrap/configure-semaphore.sh"
fi
```

**Eigenschaften:**
- ✅ **Opt-In per Default:** `AUTO_CONFIGURE=true`
- ✅ **Opt-Out möglich:** `AUTO_CONFIGURE=false` für manuelle Kontrolle
- ✅ **Graceful Failure:** Container läuft weiter bei Config-Fehler
- ✅ **Klares Logging:** Nutzer sieht was passiert

---

### C) Keine Änderungen in `configure-semaphore.sh`

**Status:** ✅ Script ist bereits vollständig und idempotent

**Funktionalität:**
1. Login via Semaphore API (Session Cookie)
2. Erstellt 2nd Admin Account (ralf)
3. Prüft/Erstellt SSH Keys für Gitea
4. Prüft/Erstellt Repository-Connection zu `RALF-Homelab/ralf.git`
5. Prüft/Erstellt Ansible Inventory
6. Prüft/Erstellt Environment Variables

**Benötigt:** Credentials aus `/var/lib/ralf/credentials.env`

---

## Data Flow & Execution Sequence

### Kompletter Bootstrap-Ablauf

```
┌─────────────────────────────────────────────────────────┐
│ Vorbereitung (Einmalig)                                  │
└─────────────────────────────────────────────────────────┘
  $ bash bootstrap/generate-credentials.sh
  → Erstellt: /var/lib/ralf/credentials.env
  $ source /var/lib/ralf/credentials.env

┌─────────────────────────────────────────────────────────┐
│ Phase 1: PostgreSQL                                      │
└─────────────────────────────────────────────────────────┘
  $ bash bootstrap/create-postgresql.sh

  1. Prüft: CT 2010 existiert? → Skip/Create
  2. Installiert PostgreSQL 16
  3. Erstellt Snapshot

┌─────────────────────────────────────────────────────────┐
│ Phase 2: Gitea (mit Repository-Erstellung) 🆕           │
└─────────────────────────────────────────────────────────┘
  $ bash bootstrap/create-gitea.sh

  1. Prüft: CT 2012 existiert? → Skip/Create
  2. Installiert Gitea 1.22.6
  3. Erstellt PostgreSQL-Datenbank (idempotent)
  4. Schreibt /etc/gitea/app.ini (mit Backup)
  5. Startet Gitea Service
  6. Erstellt Admin-User 1 (kolja) 🔁 Idempotent
  7. Erstellt Admin-User 2 (ralf) 🔁 Idempotent
  8. Erstellt Organization (RALF-Homelab) 🔁 Idempotent
  9. 🆕 Erstellt Repository (RALF-Homelab/ralf) 🔁 Idempotent:
     GET /api/v1/repos/RALF-Homelab/ralf
     → Existiert? Skip : POST /api/v1/orgs/RALF-Homelab/repos
  10. Erstellt Snapshot

  ✅ Ergebnis: Gitea komplett + Repository verfügbar

┌─────────────────────────────────────────────────────────┐
│ Phase 3: Semaphore (mit Auto-Configure) 🆕              │
└─────────────────────────────────────────────────────────┘
  $ bash bootstrap/create-and-fill-runner.sh

  1. Prüft: CT 10015 existiert? → Skip/Create
  2. Installiert Semaphore 2.16.51
  3. Installiert Ansible 2.17
  4. Kopiert SSH Keys von Host
  5. Erstellt Initial Admin User (kolja)

  6. 🆕 Prüft: AUTO_CONFIGURE=true?
     → Ja: Ruft configure-semaphore.sh auf

  7. 🆕 configure-semaphore.sh Ausführung:
     a) Login via API → Session Cookie
     b) Erstellt 2nd Admin (ralf) 🔁
     c) SSH Key für Gitea 🔁
     d) HTTP Login für Gitea 🔁
     e) Repository Connection 🔁:
        GET /api/project/1/repositories
        → "ralf" existiert? Skip : POST
     f) Ansible Inventory 🔁
     g) Environment Variables 🔁

  8. Erstellt Snapshot

  ✅ Ergebnis: Semaphore komplett + Repository connected

┌─────────────────────────────────────────────────────────┐
│ Phase 4: n8n & exo                                       │
└─────────────────────────────────────────────────────────┘
  $ bash bootstrap/create-n8n.sh
  $ bash bootstrap/create-exo.sh

  (Bereits vollständig automatisiert)

┌─────────────────────────────────────────────────────────┐
│ Finale: Code Push (Einmalig nach Bootstrap)             │
└─────────────────────────────────────────────────────────┘
  $ cd /root/ralf
  $ git remote add gitea http://10.10.20.12:3000/RALF-Homelab/ralf.git
  $ git push gitea main

  ✅ RALF ist Self-Orchestration Ready!
```

### Credentials-Flow

```
/var/lib/ralf/credentials.env
  ↓
  ├─ create-gitea.sh
  │   ├─ GITEA_ADMIN1_USER
  │   ├─ GITEA_ADMIN1_PASS
  │   ├─ GITEA_ADMIN2_USER
  │   ├─ GITEA_ADMIN2_PASS
  │   └─ POSTGRES_MASTER_PASS
  │
  ├─ create-and-fill-runner.sh
  │   └─ AUTO_CONFIGURE=true (default)
  │
  └─ configure-semaphore.sh
      ├─ ADMIN1_USER / ADMIN1_PASS
      ├─ ADMIN2_USER / ADMIN2_PASS
      ├─ GITEA_USER / GITEA_PASS
      ├─ GIT_REPO_URL
      ├─ PROXMOX_API_TOKEN_ID / SECRET
      └─ Alle DB-Passwörter
```

---

## Error Handling & Idempotency

### Idempotenz-Garantien

**Gitea Repository-Erstellung:**

```
GET /api/v1/repos/RALF-Homelab/ralf
  ↓
  Existiert (HTTP 200)?
    → Log "Repository existiert bereits"
    → Exit 0 (Success)

  Nicht gefunden (HTTP 404)?
    → POST /api/v1/orgs/RALF-Homelab/repos
    → Prüfe Response:
       - HTTP 201: Success → Exit 0
       - HTTP 409: Already exists → Exit 0
       - HTTP 401: Auth failed → Exit 1
       - Andere: Error → Exit 1
```

**Semaphore configure-semaphore.sh:**

Bereits idempotent durch GET-vor-POST Pattern:
- ✅ Users: `GET /api/users` → Existiert? Skip
- ✅ Keys: `GET /api/keys` → Existiert? Skip
- ✅ Repository: `GET /api/project/1/repositories` → Existiert? Skip
- ✅ Inventory: `GET /api/project/1/inventory` → Existiert? Skip
- ✅ Environment: `GET /api/project/1/environment` → Existiert? Skip

### Re-Run Szenarien

| Szenario | Verhalten | Ergebnis |
|----------|-----------|----------|
| Bootstrap komplett wiederholen | Alle Checks schlagen an | ✅ Keine Änderungen, Exit 0 |
| Nur Gitea neu deployen | Container wird neu erstellt | ✅ Alle Configs neu geschrieben |
| Nur Semaphore re-configure | configure-semaphore.sh aufrufen | ✅ Fehlende Items erstellt |
| Repository manuell gelöscht | GET schlägt fehl | ✅ POST erstellt es neu |
| Credentials geändert | APIs verwenden neue Credentials | ✅ Neue User/Repos mit neuen Creds |

### Error Handling Strategien

**1. Credential Validation (Früh scheitern)**

```bash
# In configure-semaphore.sh (bereits vorhanden):
if [[ "$ADMIN1_PASS" == "CHANGE_ME_NOW" ]]; then
  echo "ERROR: ADMIN1_PASS ist noch CHANGE_ME_NOW."
  exit 1
fi
```

**2. API Response Validation**

Alle API-Calls validieren HTTP-Status-Codes:
- 200/201: Success
- 409: Already exists (OK für Idempotenz)
- 401: Auth failed (Critical)
- 404: Not found (Expected bei GET-vor-POST)
- Andere: Unerwarteter Fehler

**3. Network Availability**

Services müssen laufen bevor API-Calls gemacht werden:
- Gitea API: Warte bis `/api/v1/version` antwortet (max 30s)
- Semaphore API: Warte bis `/api/ping` antwortet (max 30s)

**4. Graceful Failure**

Bei AUTO_CONFIGURE Fehler:
- Container läuft weiter (Semaphore ist installiert)
- Nutzer wird informiert über manuelle Option
- Exit Code = 0 (Container-Deployment war erfolgreich)

### Rollback-Strategie

**Snapshots als Safety Net:**

```
create-postgresql.sh    → post-install (CT 2010)
create-gitea.sh         → post-install (CT 2012)
create-and-fill-runner.sh → post-install (CT 10015)
```

**Manuelle Rollback-Steps:**

```bash
# Gitea Repository löschen:
curl -X DELETE \
  http://10.10.20.12:3000/api/v1/repos/RALF-Homelab/ralf \
  -u "kolja:$GITEA_ADMIN1_PASS"

# Dann re-run:
bash bootstrap/create-gitea.sh

# Semaphore re-configure:
bash bootstrap/configure-semaphore.sh
```

---

## Testing Strategy

### Unit Tests

**Test 1: Gitea Repository-Erstellung (Idempotenz)**

```bash
test_gitea_repository_idempotency() {
  source /var/lib/ralf/credentials.env

  # Erster Durchlauf
  bash bootstrap/create-gitea.sh

  # Verify Repository existiert
  REPO=$(curl -sf http://10.10.20.12:3000/api/v1/repos/RALF-Homelab/ralf)
  [[ -n "$REPO" ]] || exit 1

  # Zweiter Durchlauf (idempotent)
  bash bootstrap/create-gitea.sh

  # Verify Repository existiert noch
  REPO2=$(curl -sf http://10.10.20.12:3000/api/v1/repos/RALF-Homelab/ralf)
  [[ -n "$REPO2" ]] || exit 1
}
```

**Test 2: Semaphore Auto-Configure**

```bash
test_semaphore_auto_configure() {
  source /var/lib/ralf/credentials.env

  # Mit AUTO_CONFIGURE=true (default)
  bash bootstrap/create-and-fill-runner.sh

  # Verify configure wurde ausgeführt
  pct exec 10015 -- test -f /root/.semaphore-configured
}

test_semaphore_auto_configure_opt_out() {
  # Mit AUTO_CONFIGURE=false
  AUTO_CONFIGURE=false bash bootstrap/create-and-fill-runner.sh

  # Verify configure wurde NICHT ausgeführt
  ! pct exec 10015 -- test -f /root/.semaphore-configured
}
```

### Integration Tests

**Test 3: Full Bootstrap End-to-End**

```bash
#!/usr/bin/env bash
# tests/bootstrap/full-bootstrap-test.sh

# Cleanup
for ctid in 2010 2012 10015; do
  pct stop $ctid 2>/dev/null || true
  pct destroy $ctid 2>/dev/null || true
done

# Bootstrap
source /var/lib/ralf/credentials.env
bash bootstrap/create-postgresql.sh
bash bootstrap/create-gitea.sh
bash bootstrap/create-and-fill-runner.sh

# Verifications
curl -sf http://10.10.20.12:3000/api/v1/repos/RALF-Homelab/ralf | jq -e '.name == "ralf"'
pct exec 10015 -- test -f /root/.semaphore-configured
```

### Smoke Tests

**Test 4: Gitea Smoke Test (Erweitert)**

```bash
#!/usr/bin/env bash
# tests/gitea/smoke.sh

echo "=== GITEA SMOKE TEST ==="

ping -c 1 10.10.20.12 && echo "✅ Ping" || echo "❌ Ping FAILED"
nc -zv 10.10.20.12 3000 && echo "✅ Port 3000" || echo "❌ Port FAILED"

curl -sf http://10.10.20.12:3000/api/v1/version && echo "✅ API" || echo "❌ API FAILED"

# Repository Test (NEU)
REPO=$(curl -sf http://10.10.20.12:3000/api/v1/repos/RALF-Homelab/ralf)
echo "$REPO" | jq -e '.name == "ralf"' && echo "✅ Repository" || echo "❌ Repository FAILED"
```

**Test 5: Semaphore Smoke Test**

```bash
#!/usr/bin/env bash
# tests/semaphore/smoke.sh

echo "=== SEMAPHORE SMOKE TEST ==="

ping -c 1 10.10.100.15 && echo "✅ Ping" || echo "❌ Ping FAILED"
nc -zv 10.10.100.15 3000 && echo "✅ Port 3000" || echo "❌ Port FAILED"

pct exec 10015 -- systemctl is-active semaphore && echo "✅ Service" || echo "❌ Service FAILED"

pct exec 10015 -- test -f /root/.semaphore-configured && echo "✅ Configured" || echo "⚠️ Not Configured"
```

### Regression Tests

**Test 6: Re-Run Idempotenz**

```bash
#!/usr/bin/env bash
# tests/bootstrap/regression-test.sh

source /var/lib/ralf/credentials.env

SCRIPTS=(
  "bootstrap/create-postgresql.sh"
  "bootstrap/create-gitea.sh"
  "bootstrap/create-and-fill-runner.sh"
)

for script in "${SCRIPTS[@]}"; do
  echo "Testing: $script (Run 1)"
  bash "$script"

  echo "Testing: $script (Run 2 - Idempotenz)"
  bash "$script" || exit 1
done

echo "✅ Alle Scripts sind idempotent"
```

---

## Implementation Plan

### Phase 1: Gitea Repository-Erstellung

1. Backup `create-gitea.sh`
2. Füge Repository-Erstellung nach Organization ein
3. Teste manuell: `bash bootstrap/create-gitea.sh`
4. Verify via API: `curl http://10.10.20.12:3000/api/v1/repos/RALF-Homelab/ralf`
5. Re-Run Test: Script nochmal ausführen (Idempotenz)
6. Commit

### Phase 2: Semaphore Auto-Configure

1. Backup `create-and-fill-runner.sh`
2. Füge AUTO_CONFIGURE Hook am Ende ein
3. Teste mit `AUTO_CONFIGURE=true` (default)
4. Teste mit `AUTO_CONFIGURE=false` (opt-out)
5. Verify Semaphore konfiguriert: Web-UI prüfen
6. Commit

### Phase 3: Testing

1. Erstelle/Update Smoke Tests
2. Erstelle Integration Test
3. Erstelle Regression Test
4. Führe alle Tests aus
5. Dokumentiere Ergebnisse

### Phase 4: Dokumentation

1. Update `docs/bootstrap-idempotency-report.md`
2. Update `README.md` Bootstrap-Section
3. Erstelle `docs/webui-automation-howto.md`
4. Commit

---

## Success Criteria

- ✅ `create-gitea.sh` erstellt Repository automatisch
- ✅ `create-and-fill-runner.sh` konfiguriert Semaphore automatisch
- ✅ Beide Scripts sind idempotent (Re-Run ohne Fehler)
- ✅ Opt-Out funktioniert (`AUTO_CONFIGURE=false`)
- ✅ Alle Tests bestehen (Unit, Integration, Smoke, Regression)
- ✅ Dokumentation vollständig

---

## Risks & Mitigation

| Risk | Wahrscheinlichkeit | Impact | Mitigation |
|------|-------------------|--------|------------|
| Gitea API ändert sich | Niedrig | Mittel | API-Version in Script dokumentieren |
| Credentials fehlen | Mittel | Hoch | Frühe Validation + klare Fehlermeldung |
| Network Timeout | Niedrig | Mittel | Retry-Logic + Timeout-Handling |
| configure-semaphore.sh fehlschlägt | Mittel | Mittel | Graceful Failure + manuelle Option |

---

## Alternatives Considered

### Alternative 1: CLI-First (Abgelehnt)

Gitea CLI verwenden statt API:
```bash
gitea admin repo create --name ralf --owner RALF-Homelab
```

**Warum abgelehnt:**
- CLI hat weniger Features (kein auto_init)
- Inkonsistent (Semaphore nutzt API)
- Schlechteres Error-Handling

### Alternative 2: Separate Auto-Configure Script (Abgelehnt)

Neues Script `bootstrap/auto-configure-all.sh` erstellen:
```bash
bash bootstrap/create-gitea.sh
bash bootstrap/create-and-fill-runner.sh
bash bootstrap/auto-configure-all.sh  # Ruft configure-semaphore.sh auf
```

**Warum abgelehnt:**
- Zusätzlicher manueller Schritt
- Weniger elegant als Hybrid-Lösung
- Mehr Scripts zu warten

---

## Timeline

| Phase | Dauer | Status |
|-------|-------|--------|
| Design | 2h | ✅ Complete |
| Implementation | 4h | ⏳ Pending |
| Testing | 2h | ⏳ Pending |
| Documentation | 1h | ⏳ Pending |
| **Total** | **9h** | |

---

## Conclusion

Dieses Design automatisiert die letzten manuellen Schritte im Bootstrap-Prozess und bringt RALF von 80% auf 98% Idempotenz. Die API-basierte Lösung ist robust, wartbar und konsistent mit bestehenden Patterns. Nach Implementierung ist RALF vollständig hands-off bootstrappable.

**Next Step:** Implementation Plan ausführen (siehe Phase 1-4)

---

**Design approved:** 2026-02-15
**Author:** RALF Homelab Project
**Co-Authored-By:** Claude Sonnet 4.5 <noreply@anthropic.com>
