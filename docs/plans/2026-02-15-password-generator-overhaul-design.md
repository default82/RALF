# Password Generator Overhaul - Design Document

**Datum:** 2026-02-15
**Status:** ✅ Approved
**Autor:** RALF Homelab Project
**Co-Authored-By:** Claude Sonnet 4.5 <noreply@anthropic.com>

---

## Problem Statement

Der aktuelle Passwort-Generator (`bootstrap/generate-credentials.sh`) verwendet Sonderzeichen (`?%!@#&*+`), die bei HTTP Basic Authentication und verschiedenen Web-Services Probleme verursachen.

**Entdeckt während:** Clean-Room Test von Gitea (CT 2012)

**Symptome:**
- Gitea Admin-User Authentication schlägt fehl (HTTP 401)
- Passwörter mit `&`, `%`, `+`, `*` werden nicht korrekt verarbeitet
- Alphanumerische Test-Passwörter funktionieren einwandfrei

**Root Cause:**
- Sonderzeichen benötigen URL-Encoding in HTTP Basic Auth
- Shell-Expansion-Probleme bei `*`, `?`, `!`
- Service-spezifische Escaping-Anforderungen inkonsistent

---

## Design-Entscheidungen

### 1. Security vs. Compatibility Trade-off

**Gewählt:** Maximum Compatibility

**Begründung:**
- Homelab-Umgebung mit 8+ verschiedenen Web-Services
- Korrektes Escaping in jedem Service ist fehleranfällig
- Längere Passwörter kompensieren reduzierte Entropie
- Praktikabilität > theoretische Maximalsicherheit

### 2. Passwort-Länge

**Gewählt:** Einheitlich 32 Zeichen für alle Passwörter

**Begründung:**
- Einfach und konsistent
- Kompensiert reduzierte Entropie durch kleineren Zeichensatz
- Alle Passwörter werden in `credentials.env` gespeichert (keine manuelle Eingabe)
- 189 bit Entropie ist mehr als ausreichend für Homelab

### 3. Sichere Sonderzeichen

**Gewählt:** Minimal Safe Set (`-`, `_`)

**Begründung:**
- Funktioniert garantiert in URLs, Shell, HTTP Basic Auth, Datenbanken
- Erfüllt Sonderzeichen-Requirements von Diensten
- Keine Encoding/Escaping-Probleme

### 4. Migration-Strategie

**Gewählt:** Clean Break - Komplette Neu-Generierung

**Begründung:**
- Passt zu Clean-Room Testing-Ansatz
- Container können einfach neu erstellt werden
- Automatisches Backup-System bereits vorhanden
- Sauberer Schnitt statt inkrementelle Migration

### 5. Test-Strategie

**Gewählt:** Full Regression Test

**Begründung:**
- Validiere alle Services die Passwörter verwenden
- Verhindere weitere unentdeckte Kompatibilitätsprobleme
- Dokumentiere Testergebnisse für Zukunft

---

## Technisches Design

### Zeichensatz-Änderungen

**Vorher:**
```bash
local upper="ABCDEFGHJKMNPQRSTUVWXYZ"      # 23 Zeichen
local lower="abcdefghjkmnpqrstuvwxyz"      # 23 Zeichen
local digits="23456789"                     # 8 Zeichen
local special='?%!@#&*+'                    # 8 Zeichen
# Gesamt: 62 Zeichen
```

**Nachher:**
```bash
local upper="ABCDEFGHJKMNPQRSTUVWXYZ"      # 23 Zeichen
local lower="abcdefghjkmnpqrstuvwxyz"      # 23 Zeichen
local digits="23456789"                     # 8 Zeichen
local special="-_"                          # 2 Zeichen
# Gesamt: 56 Zeichen
```

### Entropie-Vergleich

| Konfiguration | Zeichensatz | Länge | Bit Entropie |
|---------------|-------------|-------|--------------|
| **Alt (Admin)** | 62 Zeichen | 24 | ~146 bit |
| **Alt (DB)** | 62 Zeichen | 32 | ~192 bit |
| **Neu (Alle)** | 56 Zeichen | 32 | **~189 bit** |

**Ergebnis:** Praktisch identische Sicherheit, maximale Kompatibilität.

### Kompatibilitäts-Matrix

| Kontext | Alt (`&*+%`) | Neu (`-_`) |
|---------|--------------|------------|
| HTTP Basic Auth | ❌ Needs encoding | ✅ Works |
| URLs | ❌ Needs encoding | ✅ Works |
| Shell (bash) | ⚠️ Expansion issues | ✅ Works |
| PostgreSQL | ✅ Works | ✅ Works |
| MariaDB | ✅ Works | ✅ Works |
| JSON | ⚠️ Needs escaping | ✅ Works |
| YAML | ⚠️ Needs quoting | ✅ Works |

---

## Implementierung

### Code-Änderungen

**Datei:** `bootstrap/generate-credentials.sh`

**1. Generator-Funktion (Zeilen 31-56):**
```bash
generate_password() {
  local length="${1:-32}"  # Default: 32 (vorher: unspecified)

  # Zeichensätze gemäß Kompatibilitäts-Anforderungen
  local upper="ABCDEFGHJKMNPQRSTUVWXYZ"
  local lower="abcdefghjkmnpqrstuvwxyz"
  local digits="23456789"
  local special="-_"  # GEÄNDERT: war '?%!@#&*+'

  local all_chars="${upper}${lower}${digits}${special}"

  # Generierungslogik unverändert
  local password=""
  for i in $(seq 1 "$length"); do
    local rand_index=$(($(od -An -N2 -tu2 /dev/urandom) % ${#all_chars}))
    password="${password}${all_chars:$rand_index:1}"
  done

  echo -n "$password"
}
```

**2. Credential Calls (Zeilen 106-275):**

Ändere 10 Calls von 24 → 32:
```bash
# Service Admin Accounts
export GITEA_ADMIN1_PASS="$(generate_password 32)"        # war: 24
export GITEA_ADMIN2_PASS="$(generate_password 32)"        # war: 24
export SEMAPHORE_ADMIN1_PASS="$(generate_password 32)"    # war: 24
export SEMAPHORE_ADMIN2_PASS="$(generate_password 32)"    # war: 24
export N8N_ADMIN1_PASS="$(generate_password 32)"          # war: 24
export N8N_ADMIN2_PASS="$(generate_password 32)"          # war: 24
export MATRIX_ADMIN1_PASS="$(generate_password 32)"       # war: 24
export MATRIX_ADMIN2_PASS="$(generate_password 32)"       # war: 24
export MAIL_ACCOUNT1_PASS="$(generate_password 32)"       # war: 24
export MAIL_ACCOUNT2_PASS="$(generate_password 32)"       # war: 24
```

**Unverändert bleiben:**
- Database Passwords (bereits 32)
- API Tokens (bleiben base64)
- Encryption Keys (40 Zeichen, spezielle Anforderungen)

---

## Test-Plan

### Phase 1: Generator Validation

```bash
# Teste 100 generierte Passwörter
for i in {1..100}; do
  PW=$(generate_password 32)

  # Validierungen:
  [[ ${#PW} -eq 32 ]] || echo "FAIL: Länge nicht 32"
  [[ "$PW" =~ ^[A-Za-z2-9_-]+$ ]] || echo "FAIL: Ungültige Zeichen"
  [[ ! "$PW" =~ [ILOilo01\?\%\!\@\#\&\*\+] ]] || echo "FAIL: Verbotene Zeichen"
done
```

### Phase 2: Service-by-Service Tests

| Service | Test Command | Erwartetes Ergebnis |
|---------|--------------|---------------------|
| **PostgreSQL** | `PGPASSWORD=$PASS psql -U postgres -h 10.10.20.10 -c '\l'` | Liste der Datenbanken |
| **Gitea** | `curl -u kolja:$PASS http://10.10.20.12:3000/api/v1/user` | `{"login":"kolja"}` |
| **Semaphore** | `curl -u kolja:$PASS http://10.10.100.15:3000/api/auth/login` | Token zurück |
| **MariaDB** | `mysql -u root -p$PASS -e 'SHOW DATABASES;'` | Liste der Datenbanken |
| **MinIO** | `mc alias set test http://10.10.20.13:9000 admin $PASS` | "Added successfully" |

### Phase 3: Clean-Room Bootstrap

```bash
# 1. Neue Credentials generieren
bash bootstrap/generate-credentials.sh
source /var/lib/ralf/credentials.env

# 2. Gitea komplett neu aufsetzen
pct destroy 2012
bash bootstrap/create-gitea.sh

# 3. Smoke Tests
bash tests/gitea/smoke.sh
# Erwartung: PASS (Repository-Check kann SKIP sein)

# 4. Auth-Test
curl -s -u kolja:${GITEA_ADMIN1_PASS} http://10.10.20.12:3000/api/v1/user | jq -r '.login'
# Erwartung: "kolja"

# 5. Organization & Repository Creation
# Erwartung: HTTP 200/201, keine 401 Fehler
```

### Phase 4: Existing Services Update

```bash
# PostgreSQL (läuft bereits)
PGPASSWORD=$POSTGRES_MASTER_PASS psql -U postgres -h 10.10.20.10 <<EOF
ALTER USER postgres WITH PASSWORD '$POSTGRES_MASTER_PASS';
EOF

# Test Connection mit neuem Passwort
PGPASSWORD=$POSTGRES_MASTER_PASS psql -U postgres -h 10.10.20.10 -c '\l'
```

### Erfolgs-Kriterien

- ✅ 100/100 generierte Passwörter sind valide
- ✅ Gitea Clean-Room Test: Alle Auth-Calls erfolgreich
- ✅ PostgreSQL: Connection mit neuem Passwort OK
- ✅ Semaphore: Login mit neuem Passwort OK
- ✅ Alle Smoke Tests: PASS

---

## Migration & Rollback

### Migration-Prozess

```bash
# 1. Backup (automatisch beim Generieren)
bash bootstrap/generate-credentials.sh
# → Erstellt: /var/lib/ralf/credentials.env.backup.YYYYMMDD_HHMMSS

# 2. Source neue Credentials
source /var/lib/ralf/credentials.env

# 3. Services neu deployen (Clean-Room)
pct destroy 2012 && bash bootstrap/create-gitea.sh
pct destroy 10015 && bash bootstrap/create-and-fill-runner.sh

# 4. Existierende Services aktualisieren
# PostgreSQL Password ändern (siehe Phase 4)
```

### Rollback-Strategie

**Option 1: Credentials Restore**
```bash
BACKUP=$(ls -t /var/lib/ralf/credentials.env.backup.* | head -1)
cp "$BACKUP" /var/lib/ralf/credentials.env
source /var/lib/ralf/credentials.env
```

**Option 2: LXC Snapshot Rollback**
```bash
# Vor Migration: Snapshots erstellen
pct snapshot 2010 pre-password-change
pct snapshot 2012 pre-password-change
pct snapshot 10015 pre-password-change

# Bei Rollback: Wiederherstellen
pct rollback 2012 pre-password-change
pct start 2012
```

**Option 3: Git Revert**
```bash
cd /root/ralf/.worktrees/feature/ralf-completion
git log --oneline | head -5  # Finde Commit vor Änderung
git revert <commit-hash>
```

---

## Nicht-Ziele

Diese Features sind bewusst **nicht** im Scope:

- ❌ **Service-spezifische Password-Profile:** Zu komplex, YAGNI
- ❌ **Automatische Passwort-Rotation:** Separate Feature für später
- ❌ **Password-Komplexitäts-Validierung pro Service:** Overhead
- ❌ **External Password Manager Integration (z.B. Vaultwarden):** Separate Phase
- ❌ **Hybrid Migration (alte + neue Passwörter):** Clean Break ist einfacher

---

## Zukünftige Erweiterungen

Wenn später benötigt:

1. **Password Profiles System:**
   - `generate_password 32 web` vs `generate_password 32 database`
   - Service-spezifische Zeichensätze

2. **Password Rotation Automation:**
   - Script das Service-für-Service Passwörter rotiert
   - Cron-Job für regelmäßige Rotation

3. **Vaultwarden Integration:**
   - Credentials aus Vaultwarden statt File lesen
   - `bootstrap/` Scripts nutzen Vaultwarden API

---

## Risiken & Mitigationen

| Risiko | Wahrscheinlichkeit | Impact | Mitigation |
|--------|-------------------|--------|------------|
| Service akzeptiert keine `-` oder `_` | Niedrig | Mittel | Full Regression Test deckt dies auf |
| Passwort-Länge 32 überschreitet Service-Limit | Sehr niedrig | Mittel | Dokumentierte Services haben keine Limits |
| Rollback schlägt fehl | Niedrig | Hoch | Triple-Backup: Credentials, Snapshots, Git |
| Test findet weitere Kompatibilitätsprobleme | Mittel | Niedrig | Genau das Ziel des Full Regression Tests |

---

## Implementierungs-Reihenfolge

Siehe separates Dokument: `docs/plans/2026-02-15-password-generator-overhaul-plan.md`

(Wird mit `writing-plans` Skill erstellt)

---

## Referenzen

- Original Issue: Clean-Room Test Failure (Gitea Auth 401)
- Related: `docs/webui-automation-howto.md` (Bootstrap-Prozess)
- Related: `bootstrap/generate-credentials.sh` (Implementierung)
- Related: `tests/gitea/smoke.sh` (Test-Framework)

---

**Nächster Schritt:** Implementierungsplan mit `writing-plans` Skill erstellen.
