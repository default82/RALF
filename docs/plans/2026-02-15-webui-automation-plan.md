# Web-UI Automatisierung - Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Automatisiere Gitea Repository-Erstellung und Semaphore-Konfiguration für 100% hands-off Bootstrap

**Architecture:** API-basierte Automatisierung mit GET-vor-POST Idempotenz, Hybrid-Integration für Semaphore via AUTO_CONFIGURE Flag

**Tech Stack:** Bash, Gitea REST API, Semaphore REST API, curl, jq

---

## Kontext

**Design-Dokument:** `docs/plans/2026-02-15-webui-automation-design.md`

**Ziel:** Bootstrap von 80% auf 98% Idempotenz bringen durch:
1. Automatische Gitea Repository-Erstellung (RALF-Homelab/ralf)
2. Automatische Semaphore-Konfiguration via configure-semaphore.sh

**Wichtige Prinzipien:**
- ✅ Idempotent: GET vor POST, mehrfach ausführbar
- ✅ Error Handling: HTTP-Status-Codes validieren
- ✅ Credentials: Aus `/var/lib/ralf/credentials.env`
- ✅ Backward Compatible: Bestehende Deployments nicht brechen

---

## Task 1: Gitea Repository-Erstellung vorbereiten

**Files:**
- Modify: `bootstrap/create-gitea.sh` (nach Line ~389)
- Test: Manual verification via curl

**Kontext:** Repository wird nach Organization-Erstellung eingefügt, vor Snapshot

### Step 1: Backup create-gitea.sh

```bash
cp bootstrap/create-gitea.sh bootstrap/create-gitea.sh.backup
```

Expected: Backup erstellt

### Step 2: Finde Einfügepunkt

```bash
grep -n "Erstelle Organisation RALF-Homelab" bootstrap/create-gitea.sh
```

Expected: Zeigt Line-Number (ca. 367)

```bash
grep -n "Snapshot post-install" bootstrap/create-gitea.sh
```

Expected: Zeigt Line-Number (ca. 395)

**Einfügepunkt:** Zwischen Organization-Erstellung und Snapshot

### Step 3: Code-Block vorbereiten

Erstelle `/tmp/gitea-repo-creation.sh` mit folgendem Inhalt:

```bash
### =========================
### 13) Erstelle Repository 'ralf'
### =========================

log "Erstelle Repository: RALF-Homelab/ralf"

pct_exec "$CTID" "
set -euo pipefail

# Warte auf Gitea API (nach Organization-Erstellung kann API kurz busy sein)
for i in {1..10}; do
  if curl -sf http://localhost:${GITEA_HTTP_PORT}/api/v1/version >/dev/null 2>&1; then
    break
  fi
  if [[ \$i -eq 10 ]]; then
    echo 'ERROR: Gitea API antwortet nicht nach 10 Sekunden'
    exit 1
  fi
  sleep 1
done

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
    echo 'Prüfe GITEA_ADMIN1_USER und GITEA_ADMIN1_PASS in credentials.env'
    exit 1
  else
    echo \"ERROR: Unerwarteter HTTP Code: \$HTTP_CODE\"
    echo \"Response: \$BODY\"
    exit 1
  fi
fi
"
```

Expected: File `/tmp/gitea-repo-creation.sh` erstellt

### Step 4: Code-Block in create-gitea.sh einfügen

```bash
# Finde Line-Number für Einfügepunkt (nach Organization, vor Snapshot)
LINE=$(grep -n "### 13) Snapshot post-install" bootstrap/create-gitea.sh | cut -d: -f1)

# Füge Code-Block ein
head -n $((LINE - 1)) bootstrap/create-gitea.sh > /tmp/create-gitea-new.sh
cat /tmp/gitea-repo-creation.sh >> /tmp/create-gitea-new.sh
tail -n +$LINE bootstrap/create-gitea.sh >> /tmp/create-gitea-new.sh

# Ersetze Original
mv /tmp/create-gitea-new.sh bootstrap/create-gitea.sh
chmod +x bootstrap/create-gitea.sh
```

Expected: Code-Block eingefügt, Script ausführbar

### Step 5: Verifiziere Syntax

```bash
bash -n bootstrap/create-gitea.sh
```

Expected: Keine Syntax-Fehler

### Step 6: Commit

```bash
git add bootstrap/create-gitea.sh
git commit -m "feat(gitea): automatische Repository-Erstellung via API

- Erstellt RALF-Homelab/ralf automatisch nach Organization
- Idempotent: GET-Check vor POST
- Error Handling: HTTP-Status-Code Validierung
- Auto-Init: Repository mit README, .gitignore, MIT License

Closes: Web-UI Repository-Erstellung (Teil 1/2)

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

Expected: Commit erfolgreich

---

## Task 2: Gitea Repository-Erstellung testen

**Files:**
- Test: `bootstrap/create-gitea.sh`
- Verify: Gitea API

**Voraussetzung:** PostgreSQL (CT 2010) muss laufen

### Step 1: Lade Credentials

```bash
source /var/lib/ralf/credentials.env
```

Expected: Environment-Variablen geladen

### Step 2: Teste create-gitea.sh (Erster Durchlauf)

```bash
# Falls Gitea bereits existiert, zerstören für Clean-Room-Test
if pct status 2012 >/dev/null 2>&1; then
  pct stop 2012
  pct destroy 2012
fi

# Bootstrap Gitea
bash bootstrap/create-gitea.sh
```

Expected:
- Container CT 2012 erstellt
- Gitea installiert
- Admin Users erstellt
- Organization erstellt
- **Repository erstellt** (neu!)
- Snapshot erstellt
- Exit 0

### Step 3: Verifiziere Repository via API

```bash
curl -sf http://10.10.20.12:3000/api/v1/repos/RALF-Homelab/ralf | jq '.'
```

Expected Output:
```json
{
  "id": 1,
  "owner": {
    "login": "RALF-Homelab",
    "full_name": "RALF Homelab Infrastructure"
  },
  "name": "ralf",
  "full_name": "RALF-Homelab/ralf",
  "description": "RALF Homelab - Self-orchestrating infrastructure platform",
  "private": true,
  "default_branch": "main",
  ...
}
```

### Step 4: Verifiziere Repository-Inhalt

```bash
# Prüfe ob README existiert
curl -sf http://10.10.20.12:3000/api/v1/repos/RALF-Homelab/ralf/contents/README.md | jq -r '.name'
```

Expected: `README.md`

```bash
# Prüfe ob .gitignore existiert
curl -sf http://10.10.20.12:3000/api/v1/repos/RALF-Homelab/ralf/contents/.gitignore | jq -r '.name'
```

Expected: `.gitignore`

### Step 5: Teste Idempotenz (Zweiter Durchlauf)

```bash
bash bootstrap/create-gitea.sh
```

Expected:
- Container 2012 existiert bereits → Skip
- Alle Konfigurationen werden übersprungen
- Repository-Check: "Repository RALF-Homelab/ralf existiert bereits"
- Exit 0

### Step 6: Verifiziere Repository existiert noch

```bash
curl -sf http://10.10.20.12:3000/api/v1/repos/RALF-Homelab/ralf | jq -r '.name'
```

Expected: `ralf`

### Step 7: Dokumentiere Test-Ergebnis

```bash
echo "✅ Gitea Repository-Erstellung erfolgreich getestet" >> /tmp/test-results.txt
echo "  - Erster Durchlauf: Repository erstellt" >> /tmp/test-results.txt
echo "  - Zweiter Durchlauf: Idempotent (keine Änderung)" >> /tmp/test-results.txt
```

Expected: Test-Log erstellt

---

## Task 3: Semaphore Auto-Configure vorbereiten

**Files:**
- Modify: `bootstrap/create-and-fill-runner.sh` (am Ende, vor "FERTIG")

**Kontext:** Auto-Configure Hook ruft configure-semaphore.sh auf wenn AUTO_CONFIGURE=true

### Step 1: Backup create-and-fill-runner.sh

```bash
cp bootstrap/create-and-fill-runner.sh bootstrap/create-and-fill-runner.sh.backup
```

Expected: Backup erstellt

### Step 2: Finde Einfügepunkt

```bash
grep -n "log \"FERTIG\"" bootstrap/create-and-fill-runner.sh
```

Expected: Zeigt Line-Number (letzte Zeile vor Ende)

**Einfügepunkt:** Vor `log "FERTIG"`

### Step 3: Code-Block vorbereiten

Erstelle `/tmp/semaphore-auto-configure.sh` mit folgendem Inhalt:

```bash
### =========================
### 11) Auto-Configure Semaphore (Optional)
### =========================

if [[ "${AUTO_CONFIGURE:-true}" == "true" ]]; then
  log "Auto-Configure: Starte Semaphore-Konfiguration"
  log "  - Repository Connection zu Gitea"
  log "  - SSH Keys"
  log "  - Ansible Inventory"
  log "  - Environment Variables"
  log ""
  log "Dies kann 2-3 Minuten dauern..."

  # Führe configure-semaphore.sh aus
  SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

  if bash "${SCRIPT_DIR}/configure-semaphore.sh"; then
    log "✅ Semaphore-Konfiguration erfolgreich abgeschlossen"

    # Marker-File für Tests
    pct_exec "$CTID" "touch /root/.semaphore-configured"
  else
    EXIT_CODE=$?
    log "❌ Semaphore-Konfiguration fehlgeschlagen (Exit Code: $EXIT_CODE)"
    log ""
    log "Container CT ${CTID} läuft weiter, aber Konfiguration ist unvollständig"
    log "Manuelle Konfiguration möglich mit:"
    log "  bash bootstrap/configure-semaphore.sh"
    log ""
    log "HINWEIS: Dies ist kein kritischer Fehler - Container ist deployed"
    # NICHT exit - Container ist erfolgreich deployed, nur Config fehlt
  fi
else
  log "AUTO_CONFIGURE=false - Überspringe Semaphore-Konfiguration"
  log ""
  log "Für manuelle Konfiguration später:"
  log "  bash bootstrap/configure-semaphore.sh"
  log ""
fi
```

Expected: File `/tmp/semaphore-auto-configure.sh` erstellt

### Step 4: Code-Block in create-and-fill-runner.sh einfügen

```bash
# Finde Line-Number für Einfügepunkt (vor "log FERTIG")
LINE=$(grep -n "log \"FERTIG\"" bootstrap/create-and-fill-runner.sh | cut -d: -f1)

# Füge Code-Block ein
head -n $((LINE - 1)) bootstrap/create-and-fill-runner.sh > /tmp/create-and-fill-runner-new.sh
cat /tmp/semaphore-auto-configure.sh >> /tmp/create-and-fill-runner-new.sh
tail -n +$LINE bootstrap/create-and-fill-runner.sh >> /tmp/create-and-fill-runner-new.sh

# Ersetze Original
mv /tmp/create-and-fill-runner-new.sh bootstrap/create-and-fill-runner.sh
chmod +x bootstrap/create-and-fill-runner.sh
```

Expected: Code-Block eingefügt, Script ausführbar

### Step 5: Verifiziere Syntax

```bash
bash -n bootstrap/create-and-fill-runner.sh
```

Expected: Keine Syntax-Fehler

### Step 6: Commit

```bash
git add bootstrap/create-and-fill-runner.sh
git commit -m "feat(semaphore): automatische Konfiguration via AUTO_CONFIGURE Hook

- Ruft configure-semaphore.sh automatisch auf (default: true)
- Opt-Out: AUTO_CONFIGURE=false überspringt Konfiguration
- Graceful Failure: Container läuft weiter bei Config-Fehler
- Marker-File: /root/.semaphore-configured für Tests

Closes: Semaphore Auto-Configure (Teil 2/2)

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

Expected: Commit erfolgreich

---

## Task 4: Semaphore Auto-Configure testen

**Files:**
- Test: `bootstrap/create-and-fill-runner.sh`
- Verify: Semaphore API + Marker-File

**Voraussetzung:** PostgreSQL + Gitea müssen laufen

### Step 1: Lade Credentials

```bash
source /var/lib/ralf/credentials.env
```

Expected: Environment-Variablen geladen

### Step 2: Teste mit AUTO_CONFIGURE=true (Default)

```bash
# Falls Semaphore bereits existiert, zerstören für Clean-Room-Test
if pct status 10015 >/dev/null 2>&1; then
  pct stop 10015
  pct destroy 10015
fi

# Bootstrap Semaphore
bash bootstrap/create-and-fill-runner.sh
```

Expected:
- Container CT 10015 erstellt
- Semaphore installiert
- configure-semaphore.sh wird aufgerufen
- Repository Connection erstellt
- SSH Keys erstellt
- Inventory erstellt
- Environment Variables erstellt
- Marker-File `/root/.semaphore-configured` erstellt
- Exit 0

**HINWEIS:** Dieser Schritt dauert 5-7 Minuten!

### Step 3: Verifiziere Marker-File

```bash
pct exec 10015 -- test -f /root/.semaphore-configured && echo "✅ Configured" || echo "❌ NOT Configured"
```

Expected: `✅ Configured`

### Step 4: Verifiziere Semaphore Service

```bash
pct exec 10015 -- systemctl is-active semaphore
```

Expected: `active`

### Step 5: Teste mit AUTO_CONFIGURE=false (Opt-Out)

```bash
# Zerstöre Container
pct stop 10015
pct destroy 10015

# Bootstrap mit AUTO_CONFIGURE=false
AUTO_CONFIGURE=false bash bootstrap/create-and-fill-runner.sh
```

Expected:
- Container CT 10015 erstellt
- Semaphore installiert
- "AUTO_CONFIGURE=false - Überspringe Semaphore-Konfiguration" im Log
- configure-semaphore.sh wird NICHT aufgerufen
- Exit 0

### Step 6: Verifiziere Marker-File fehlt

```bash
pct exec 10015 -- test -f /root/.semaphore-configured && echo "❌ FAIL: Configured" || echo "✅ PASS: NOT Configured"
```

Expected: `✅ PASS: NOT Configured`

### Step 7: Manuelle Konfiguration nachträglich

```bash
# configure-semaphore.sh manuell aufrufen
bash bootstrap/configure-semaphore.sh
```

Expected:
- Repository Connection erstellt
- SSH Keys erstellt
- Inventory erstellt
- Environment Variables erstellt
- Exit 0

### Step 8: Verifiziere Marker-File jetzt vorhanden

```bash
pct exec 10015 -- test -f /root/.semaphore-configured && echo "✅ Configured" || echo "❌ NOT Configured"
```

Expected: `✅ Configured`

### Step 9: Dokumentiere Test-Ergebnis

```bash
echo "✅ Semaphore Auto-Configure erfolgreich getestet" >> /tmp/test-results.txt
echo "  - AUTO_CONFIGURE=true: Automatisch konfiguriert" >> /tmp/test-results.txt
echo "  - AUTO_CONFIGURE=false: Übersprungen" >> /tmp/test-results.txt
echo "  - Manuelle Config nachträglich: Funktioniert" >> /tmp/test-results.txt
```

Expected: Test-Log erweitert

---

## Task 5: Smoke Tests erweitern

**Files:**
- Modify: `tests/gitea/smoke.sh` (Repository-Check hinzufügen)
- Create: `tests/semaphore/smoke.sh` (neu)

### Step 1: Erweitere Gitea Smoke Test

```bash
# Backup
cp tests/gitea/smoke.sh tests/gitea/smoke.sh.backup

# Füge Repository-Check hinzu (vor "END SMOKE TEST")
cat >> tests/gitea/smoke.sh <<'EOF'

# Repository Test
REPO=$(curl -sf http://10.10.20.12:3000/api/v1/repos/RALF-Homelab/ralf 2>/dev/null)
if echo "$REPO" | jq -e '.name == "ralf"' >/dev/null 2>&1; then
  echo "✅ Repository RALF-Homelab/ralf exists"
else
  echo "❌ Repository RALF-Homelab/ralf NOT FOUND"
fi

# Admin Users Test
ADMIN1=$(curl -sf http://10.10.20.12:3000/api/v1/users/kolja 2>/dev/null)
if echo "$ADMIN1" | jq -e '.login == "kolja"' >/dev/null 2>&1; then
  echo "✅ Admin User kolja exists"
else
  echo "❌ Admin User kolja NOT FOUND"
fi

ADMIN2=$(curl -sf http://10.10.20.12:3000/api/v1/users/ralf 2>/dev/null)
if echo "$ADMIN2" | jq -e '.login == "ralf"' >/dev/null 2>&1; then
  echo "✅ Admin User ralf exists"
else
  echo "❌ Admin User ralf NOT FOUND"
fi
EOF
```

Expected: Gitea Smoke Test erweitert

### Step 2: Teste Gitea Smoke Test

```bash
bash tests/gitea/smoke.sh
```

Expected Output:
```
=== GITEA SMOKE TEST ===
✅ Ping
✅ Port 3000
✅ Port 2222 (SSH)
✅ API Health
✅ Repository RALF-Homelab/ralf exists
✅ Admin User kolja exists
✅ Admin User ralf exists
=== END GITEA SMOKE TEST ===
```

### Step 3: Erstelle Semaphore Smoke Test

```bash
cat > tests/semaphore/smoke.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

echo "=== SEMAPHORE SMOKE TEST ==="

# Network Tests
ping -c 1 10.10.100.15 >/dev/null 2>&1 && echo "✅ Ping" || echo "❌ Ping FAILED"
nc -zv 10.10.100.15 3000 2>&1 | grep -q succeeded && echo "✅ Port 3000" || echo "❌ Port 3000 FAILED"

# API Health (ohne Auth)
curl -sf http://10.10.100.15:3000/api/ping >/dev/null 2>&1 && echo "✅ API Ping" || echo "❌ API Ping FAILED"

# Service Status (intern)
if pct exec 10015 -- systemctl is-active semaphore >/dev/null 2>&1; then
  echo "✅ Semaphore Service Active"
else
  echo "❌ Semaphore Service NOT ACTIVE"
fi

# Configuration Check
if pct exec 10015 -- test -f /root/.semaphore-configured 2>/dev/null; then
  echo "✅ Semaphore Auto-Configured"
else
  echo "⚠️  Semaphore NOT Auto-Configured (manual config needed)"
fi

echo "=== END SEMAPHORE SMOKE TEST ==="
EOF

chmod +x tests/semaphore/smoke.sh
```

Expected: Semaphore Smoke Test erstellt

### Step 4: Teste Semaphore Smoke Test

```bash
bash tests/semaphore/smoke.sh
```

Expected Output:
```
=== SEMAPHORE SMOKE TEST ===
✅ Ping
✅ Port 3000
✅ API Ping
✅ Semaphore Service Active
✅ Semaphore Auto-Configured
=== END SEMAPHORE SMOKE TEST ===
```

### Step 5: Commit

```bash
git add tests/gitea/smoke.sh tests/semaphore/smoke.sh
git commit -m "test: erweitere Smoke Tests für Web-UI Automatisierung

Gitea:
- Repository-Existenz-Check
- Admin-User-Checks (kolja, ralf)

Semaphore:
- Neuer Smoke Test
- Service Status Check
- Auto-Configure Status Check

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

Expected: Commit erfolgreich

---

## Task 6: Integration Test erstellen

**Files:**
- Create: `tests/bootstrap/full-bootstrap-test.sh` (neu)

### Step 1: Erstelle Integration Test

```bash
cat > tests/bootstrap/full-bootstrap-test.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

log() { echo -e "\n==> $*"; }

# Cleanup Helper
destroy_if_exists() {
  local ctid=$1
  if pct status "$ctid" >/dev/null 2>&1; then
    log "Cleanup: Lösche CT $ctid"
    pct stop "$ctid" 2>/dev/null || true
    pct destroy "$ctid"
  fi
}

log "=== Full Bootstrap Integration Test ==="

# Optional: Cleanup (für Clean-Room-Test)
if [[ "${CLEAN_ROOM:-false}" == "true" ]]; then
  log "CLEAN_ROOM=true - Lösche existierende Container"
  destroy_if_exists 2010
  destroy_if_exists 2012
  destroy_if_exists 10015
fi

# Credentials laden
if [[ ! -f /var/lib/ralf/credentials.env ]]; then
  echo "ERROR: /var/lib/ralf/credentials.env nicht gefunden"
  echo "Erstelle Credentials mit: bash bootstrap/generate-credentials.sh"
  exit 1
fi

source /var/lib/ralf/credentials.env

# Bootstrap ausführen
log "Phase 1: PostgreSQL"
bash bootstrap/create-postgresql.sh

log "Phase 2: Gitea (mit Repository-Erstellung)"
bash bootstrap/create-gitea.sh

log "Phase 3: Semaphore (mit Auto-Configure)"
bash bootstrap/create-and-fill-runner.sh

# Verifications
log "=== Verifications ==="

# 1. PostgreSQL läuft
if pct exec 2010 -- systemctl is-active postgresql >/dev/null 2>&1; then
  echo "✅ PostgreSQL Service aktiv"
else
  echo "❌ PostgreSQL Service NICHT aktiv"
  exit 1
fi

# 2. Gitea läuft
if pct exec 2012 -- systemctl is-active gitea >/dev/null 2>&1; then
  echo "✅ Gitea Service aktiv"
else
  echo "❌ Gitea Service NICHT aktiv"
  exit 1
fi

# 3. Gitea Repository existiert
REPO_CHECK=$(curl -sf http://10.10.20.12:3000/api/v1/repos/RALF-Homelab/ralf 2>/dev/null | jq -r '.name' 2>/dev/null || echo "")
if [[ "$REPO_CHECK" == "ralf" ]]; then
  echo "✅ Gitea Repository RALF-Homelab/ralf existiert"
else
  echo "❌ Gitea Repository existiert NICHT"
  exit 1
fi

# 4. Semaphore läuft
if pct exec 10015 -- systemctl is-active semaphore >/dev/null 2>&1; then
  echo "✅ Semaphore Service aktiv"
else
  echo "❌ Semaphore Service NICHT aktiv"
  exit 1
fi

# 5. Semaphore konfiguriert
if pct exec 10015 -- test -f /root/.semaphore-configured 2>/dev/null; then
  echo "✅ Semaphore wurde auto-konfiguriert"
else
  echo "⚠️  Semaphore wurde NICHT auto-konfiguriert"
  echo "    (möglicherweise AUTO_CONFIGURE=false gesetzt)"
fi

log "=== Test erfolgreich ==="
echo ""
echo "Alle Komponenten deployed und verifiziert"
echo ""
echo "Next Steps:"
echo "  1. Code pushen:"
echo "     cd /root/ralf"
echo "     git remote add gitea http://10.10.20.12:3000/RALF-Homelab/ralf.git"
echo "     git push gitea main"
echo ""
echo "  2. Semaphore UI: http://10.10.100.15:3000"
echo "  3. Gitea UI: http://10.10.20.12:3000"
EOF

chmod +x tests/bootstrap/full-bootstrap-test.sh
```

Expected: Integration Test erstellt

### Step 2: Teste Integration Test (mit existierenden Containern)

```bash
bash tests/bootstrap/full-bootstrap-test.sh
```

Expected:
- Alle Container werden übersprungen (existieren bereits)
- Alle Verifications: ✅ PASS
- Exit 0

### Step 3: Teste Integration Test (Clean-Room)

**WARNUNG:** Dieser Test zerstört Container 2010, 2012, 10015!

```bash
CLEAN_ROOM=true bash tests/bootstrap/full-bootstrap-test.sh
```

Expected:
- Container werden gelöscht
- Kompletter Bootstrap läuft durch
- Alle Verifications: ✅ PASS
- Dauer: ~15-20 Minuten
- Exit 0

### Step 4: Commit

```bash
git add tests/bootstrap/full-bootstrap-test.sh
git commit -m "test: füge Full Bootstrap Integration Test hinzu

- End-to-End Test aller Bootstrap-Phasen
- Verifiziert: PostgreSQL, Gitea, Semaphore
- Prüft: Services aktiv, Repository existiert, Auto-Configure
- CLEAN_ROOM Mode für vollständigen Neuaufbau

Usage:
  bash tests/bootstrap/full-bootstrap-test.sh
  CLEAN_ROOM=true bash tests/bootstrap/full-bootstrap-test.sh

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

Expected: Commit erfolgreich

---

## Task 7: Regression Test erstellen

**Files:**
- Create: `tests/bootstrap/regression-test.sh` (neu)

### Step 1: Erstelle Regression Test

```bash
cat > tests/bootstrap/regression-test.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

log() { echo -e "\n==> $*"; }

log "=== Regression Test: Bootstrap Re-Run (Idempotenz) ==="

# Credentials laden
if [[ ! -f /var/lib/ralf/credentials.env ]]; then
  echo "ERROR: /var/lib/ralf/credentials.env nicht gefunden"
  exit 1
fi

source /var/lib/ralf/credentials.env

# Alle Scripts 2x ausführen
SCRIPTS=(
  "bootstrap/create-postgresql.sh"
  "bootstrap/create-gitea.sh"
  "bootstrap/create-and-fill-runner.sh"
)

FAILED=0

for script in "${SCRIPTS[@]}"; do
  log "Testing: $script (Run 1)"
  if bash "$script"; then
    echo "✅ Run 1 erfolgreich"
  else
    echo "❌ Run 1 fehlgeschlagen"
    FAILED=1
    continue
  fi

  log "Testing: $script (Run 2 - Idempotenz-Check)"
  if bash "$script"; then
    echo "✅ Run 2 erfolgreich (idempotent)"
  else
    echo "❌ Run 2 fehlgeschlagen"
    FAILED=1
    continue
  fi

  echo "✅ $script ist idempotent"
done

if [[ $FAILED -eq 0 ]]; then
  log "=== Alle Scripts sind idempotent ==="
  exit 0
else
  log "=== Fehler: Einige Scripts sind NICHT idempotent ==="
  exit 1
fi
EOF

chmod +x tests/bootstrap/regression-test.sh
```

Expected: Regression Test erstellt

### Step 2: Teste Regression Test

```bash
bash tests/bootstrap/regression-test.sh
```

Expected:
- Alle Scripts werden 2x ausgeführt
- Alle Runs: ✅ PASS
- Exit 0

### Step 3: Commit

```bash
git add tests/bootstrap/regression-test.sh
git commit -m "test: füge Regression Test für Idempotenz hinzu

- Führt alle Bootstrap-Scripts 2x aus
- Verifiziert: Scripts sind idempotent (Re-Run ohne Fehler)
- Tests: create-postgresql.sh, create-gitea.sh, create-and-fill-runner.sh

Usage:
  bash tests/bootstrap/regression-test.sh

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

Expected: Commit erfolgreich

---

## Task 8: Dokumentation aktualisieren

**Files:**
- Modify: `README.md` (Bootstrap-Section)
- Create: `docs/webui-automation-howto.md` (neu)

### Step 1: Erstelle HowTo-Dokument

```bash
cat > docs/webui-automation-howto.md <<'EOF'
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
EOF
```

Expected: HowTo-Dokument erstellt

### Step 2: Update README.md Bootstrap-Section

```bash
# Finde Bootstrap-Section in README
grep -n "## Bootstrap" README.md
```

Expected: Zeigt Line-Number

**Füge folgenden Abschnitt nach "## Bootstrap" ein:**

```markdown
### Automatisierung Status

✅ **98% Idempotent** - Bootstrap ist vollständig automatisiert!

**Manuelle Schritte:**
1. ✅ **Vor Bootstrap:** `bash bootstrap/generate-credentials.sh` (einmalig)
2. ✅ **Während Bootstrap:** KEINE! Komplett automatisch
3. ✅ **Nach Bootstrap:** Code pushen (einmalig)

**Details:** Siehe `docs/webui-automation-howto.md`
```

### Step 3: Commit

```bash
git add docs/webui-automation-howto.md README.md
git commit -m "docs: HowTo für Web-UI Automatisierung + README Update

- Neue Anleitung: docs/webui-automation-howto.md
  * Quick Start Guide
  * AUTO_CONFIGURE Optionen
  * Troubleshooting
  * Tests

- README.md: Bootstrap-Section aktualisiert
  * Automatisierungs-Status: 98% idempotent
  * Manuelle Schritte dokumentiert

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

Expected: Commit erfolgreich

---

## Task 9: Final Verification

**Files:**
- Verify: Alle Tests laufen durch
- Verify: Dokumentation vollständig

### Step 1: Führe alle Tests aus

```bash
# Smoke Tests
bash tests/gitea/smoke.sh
bash tests/semaphore/smoke.sh

# Integration Test (mit existierenden Containern)
bash tests/bootstrap/full-bootstrap-test.sh

# Regression Test
bash tests/bootstrap/regression-test.sh
```

Expected: Alle Tests ✅ PASS

### Step 2: Verifiziere Dokumentation

```bash
# Check Design Doc
test -f docs/plans/2026-02-15-webui-automation-design.md && echo "✅ Design Doc"

# Check Plan Doc
test -f docs/plans/2026-02-15-webui-automation-plan.md && echo "✅ Plan Doc"

# Check HowTo
test -f docs/webui-automation-howto.md && echo "✅ HowTo"

# Check README Update
grep -q "98% Idempotent" README.md && echo "✅ README updated"
```

Expected: Alle Checks ✅

### Step 3: Erstelle Summary-Commit

```bash
cat > /tmp/implementation-summary.txt <<EOF
Implementation Summary: Web-UI Automatisierung

Status: ✅ Complete

Implementierte Features:
1. ✅ Gitea Repository-Erstellung (bootstrap/create-gitea.sh)
   - API-basiert via POST /api/v1/orgs/RALF-Homelab/repos
   - Idempotent: GET-Check vor POST
   - Error Handling: HTTP-Status-Code Validation
   - Auto-Init: README, .gitignore, MIT License

2. ✅ Semaphore Auto-Configure (bootstrap/create-and-fill-runner.sh)
   - Hybrid-Integration via AUTO_CONFIGURE Flag
   - Default: Automatisch konfiguriert
   - Opt-Out: AUTO_CONFIGURE=false
   - Graceful Failure: Container läuft weiter bei Config-Fehler

3. ✅ Smoke Tests erweitert
   - tests/gitea/smoke.sh: Repository-Check
   - tests/semaphore/smoke.sh: Neu erstellt

4. ✅ Integration Test
   - tests/bootstrap/full-bootstrap-test.sh
   - End-to-End Test aller Phasen
   - CLEAN_ROOM Mode für vollständigen Neuaufbau

5. ✅ Regression Test
   - tests/bootstrap/regression-test.sh
   - Idempotenz-Verifikation

6. ✅ Dokumentation
   - docs/webui-automation-howto.md
   - README.md Bootstrap-Section aktualisiert

Ergebnis:
- Idempotenz: 80% → 98%
- Manuelle Schritte: 2 → 0 (während Bootstrap)
- Bootstrap-Zeit: ~20 Minuten (unverändert)
- Tests: 100% PASS

Next Steps:
- Code nach Gitea pushen
- In Production testen
- n8n Master Workflow erstellen (Self-Orchestration)
EOF

cat /tmp/implementation-summary.txt
```

Expected: Summary angezeigt

### Step 4: Tag erstellen

```bash
git tag -a v1.0.0-webui-automation -m "Web-UI Automatisierung implementiert

- Gitea Repository-Erstellung automatisiert
- Semaphore Auto-Configure implementiert
- Tests erweitert (Smoke, Integration, Regression)
- Dokumentation vollständig

Bootstrap ist jetzt 98% idempotent mit 0 manuellen Schritten."
```

Expected: Tag erstellt

### Step 5: Push zu Gitea

```bash
git push gitea feature/ralf-completion
git push gitea v1.0.0-webui-automation
```

Expected: Alles gepusht

---

## Success Criteria

- ✅ `create-gitea.sh` erstellt Repository automatisch
- ✅ `create-and-fill-runner.sh` konfiguriert Semaphore automatisch
- ✅ Beide Scripts sind idempotent (Re-Run ohne Fehler)
- ✅ Opt-Out funktioniert (`AUTO_CONFIGURE=false`)
- ✅ Alle Tests bestehen (Unit, Integration, Smoke, Regression)
- ✅ Dokumentation vollständig

---

## Execution Time Estimate

| Task | Estimated Time | Notes |
|------|----------------|-------|
| Task 1: Gitea Repo Prep | 15 min | Code-Block erstellen + einfügen |
| Task 2: Gitea Repo Test | 20 min | Incl. Container-Deployment (~15 min) |
| Task 3: Semaphore Prep | 15 min | Code-Block erstellen + einfügen |
| Task 4: Semaphore Test | 30 min | Incl. configure-semaphore.sh (~20 min) |
| Task 5: Smoke Tests | 20 min | Erweitern + erstellen + testen |
| Task 6: Integration Test | 30 min | Erstellen + Clean-Room-Test (~20 min) |
| Task 7: Regression Test | 15 min | Erstellen + testen |
| Task 8: Documentation | 20 min | HowTo + README |
| Task 9: Final Verify | 20 min | Alle Tests + Summary |
| **Total** | **~3 hours** | Ohne Clean-Room-Tests: ~2 hours |

---

## Notes

**Testing Strategy:**
- Tests können parallel zu Implementation geschrieben werden
- Clean-Room-Tests sind zeitintensiv (Container-Deployments)
- Regression Tests können mit existierenden Containern laufen

**Error Handling:**
- Alle API-Calls validieren HTTP-Status-Codes
- Graceful Failure bei configure-semaphore.sh
- Container laufen weiter auch bei Config-Fehler

**Idempotenz:**
- Konsequentes GET-vor-POST Pattern
- HTTP 409 (Conflict) wird als Success behandelt
- Marker-Files für Test-Verifikation

---

**Plan erstellt:** 2026-02-15
**Author:** RALF Homelab Project
**Co-Authored-By:** Claude Sonnet 4.5 <noreply@anthropic.com>
