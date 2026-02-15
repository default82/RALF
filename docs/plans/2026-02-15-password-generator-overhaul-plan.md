# Password Generator Overhaul - Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace problematic special characters in password generator with compatible ones, standardize all passwords to 32 characters, and verify with full regression test.

**Architecture:** In-place update of `generate_password()` function in `bootstrap/generate-credentials.sh`, change character set from `?%!@#&*+` to `-_`, update all password generation calls to 32 characters, regenerate credentials with clean break, full regression test across all services.

**Tech Stack:** Bash, OpenSSL, curl, PostgreSQL, Gitea, Semaphore

---

## Task 1: Update generate_password() Function

**Files:**
- Modify: `bootstrap/generate-credentials.sh:31-56`

**Step 1: Backup current file**

```bash
cd /root/ralf/.worktrees/feature/ralf-completion
cp bootstrap/generate-credentials.sh bootstrap/generate-credentials.sh.backup
```

Run: `ls -la bootstrap/generate-credentials.sh*`
Expected: Two files (original + backup)

**Step 2: Update special character set**

Edit `bootstrap/generate-credentials.sh` line 42:

```bash
# OLD:
local special='?%!@#&*+'

# NEW:
local special='-_'
```

**Step 3: Update default length**

Edit `bootstrap/generate-credentials.sh` line 32:

```bash
# OLD:
local length="${1:-32}"

# NEW (add comment):
local length="${1:-32}"  # Default: 32 characters for all passwords
```

**Step 4: Verify changes**

Run:
```bash
grep "local special" bootstrap/generate-credentials.sh
```

Expected: `local special='-_'`

**Step 5: Test the function manually**

Run:
```bash
source bootstrap/generate-credentials.sh
PW=$(generate_password 32)
echo "Generated: $PW"
echo "Length: ${#PW}"
```

Expected:
- Length: 32
- Only characters: A-Z (no I,L,O), a-z (no i,l,o), 2-9, -, _

**Step 6: Commit**

```bash
git add bootstrap/generate-credentials.sh
git commit -m "$(cat <<'EOF'
fix: update password generator character set

Changes:
- Special chars: ?%!@#&*+ → -_ (compatible with HTTP Basic Auth)
- Default length: 32 characters (explicit comment)
- Maintains exclusions: I,L,O / i,l,o / 0,1

Root Cause: Gitea auth fails with &%+* in HTTP Basic Auth
Solution: Use only shell/URL-safe special characters

Character set: 56 chars (23 upper + 23 lower + 8 digits + 2 special)
Entropie: ~189 bit for 32 characters (sufficient for homelab)

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>
EOF
)"
```

Expected: Commit created successfully

---

## Task 2: Update Password Generation Calls (24→32)

**Files:**
- Modify: `bootstrap/generate-credentials.sh:158,162,167,171,179,183,189,193,206,210`

**Step 1: Update Gitea admin passwords**

Edit lines 158 and 162:

```bash
# OLD:
export GITEA_ADMIN1_PASS="$(generate_password 24)"
export GITEA_ADMIN2_PASS="$(generate_password 24)"

# NEW:
export GITEA_ADMIN1_PASS="$(generate_password 32)"
export GITEA_ADMIN2_PASS="$(generate_password 32)"
```

**Step 2: Update Semaphore admin passwords**

Edit lines 167 and 171:

```bash
# OLD:
export SEMAPHORE_ADMIN1_PASS="$(generate_password 24)"
export SEMAPHORE_ADMIN2_PASS="$(generate_password 24)"

# NEW:
export SEMAPHORE_ADMIN1_PASS="$(generate_password 32)"
export SEMAPHORE_ADMIN2_PASS="$(generate_password 32)"
```

**Step 3: Update n8n admin passwords**

Edit lines 179 and 183:

```bash
# OLD:
export N8N_ADMIN1_PASS="$(generate_password 24)"
export N8N_ADMIN2_PASS="$(generate_password 24)"

# NEW:
export N8N_ADMIN1_PASS="$(generate_password 32)"
export N8N_ADMIN2_PASS="$(generate_password 32)"
```

**Step 4: Update Matrix admin passwords**

Edit lines 189 and 193:

```bash
# OLD:
export MATRIX_ADMIN1_PASS="$(generate_password 24)"
export MATRIX_ADMIN2_PASS="$(generate_password 24)"

# NEW:
export MATRIX_ADMIN1_PASS="$(generate_password 32)"
export MATRIX_ADMIN2_PASS="$(generate_password 32)"
```

**Step 5: Update Mail account passwords**

Edit lines 206 and 210:

```bash
# OLD:
export MAIL_ACCOUNT1_PASS="$(generate_password 24)"
export MAIL_ACCOUNT2_PASS="$(generate_password 24)"

# NEW:
export MAIL_ACCOUNT1_PASS="$(generate_password 32)"
export MAIL_ACCOUNT2_PASS="$(generate_password 32)"
```

**Step 6: Verify all changes**

Run:
```bash
grep 'generate_password' bootstrap/generate-credentials.sh | grep -E '(ADMIN|ACCOUNT)' | grep -v '^#'
```

Expected: All should show `generate_password 32`

**Step 7: Commit**

```bash
git add bootstrap/generate-credentials.sh
git commit -m "$(cat <<'EOF'
fix: standardize all passwords to 32 characters

Changes:
- Admin accounts: 24 → 32 characters (10 passwords)
- Database passwords: unchanged (already 32)
- API tokens: unchanged (base64)
- Encryption keys: unchanged (40 chars)

Rationale: Compensate reduced entropy from smaller character set
           (189 bit with 56-char set vs 146 bit with 62-char set at 24 chars)

Affected passwords:
- Gitea Admin 1+2
- Semaphore Admin 1+2
- n8n Admin 1+2
- Matrix Admin 1+2
- Mail Account 1+2

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>
EOF
)"
```

Expected: Commit created successfully

---

## Task 3: Create Password Validator Test

**Files:**
- Create: `tests/bootstrap/validate-passwords.sh`

**Step 1: Create test script**

```bash
cat > tests/bootstrap/validate-passwords.sh <<'EOFTEST'
#!/usr/bin/env bash
set -euo pipefail

### =========================
### Password Generator Validation Test
### =========================

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
cd "$SCRIPT_DIR/../.."

# Source generator
source bootstrap/generate-credentials.sh

echo "PASSWORD GENERATOR VALIDATION TEST"
echo "==================================="
echo ""

TOTAL=100
PASS=0
FAIL=0

for i in $(seq 1 $TOTAL); do
  PW=$(generate_password 32)

  # Test 1: Length must be 32
  if [[ ${#PW} -ne 32 ]]; then
    echo "FAIL #$i: Length ${#PW} != 32"
    ((FAIL++))
    continue
  fi

  # Test 2: Only allowed characters [A-Za-z2-9_-]
  if [[ ! "$PW" =~ ^[A-Za-z2-9_-]+$ ]]; then
    echo "FAIL #$i: Contains invalid characters: $PW"
    ((FAIL++))
    continue
  fi

  # Test 3: No forbidden characters [ILOilo01?%!@#&*+]
  if [[ "$PW" =~ [ILOilo01\?\%\!\@\#\&\*\+] ]]; then
    echo "FAIL #$i: Contains forbidden characters: $PW"
    ((FAIL++))
    continue
  fi

  ((PASS++))
done

echo ""
echo "Results: $PASS/$TOTAL passed"
echo ""

if [[ $FAIL -eq 0 ]]; then
  echo "✅ PASSWORD GENERATOR: VALID"
  exit 0
else
  echo "❌ PASSWORD GENERATOR: INVALID ($FAIL failures)"
  exit 1
fi
EOFTEST

chmod +x tests/bootstrap/validate-passwords.sh
```

**Step 2: Run validation test**

Run: `bash tests/bootstrap/validate-passwords.sh`

Expected:
```
PASSWORD GENERATOR VALIDATION TEST
===================================

Results: 100/100 passed

✅ PASSWORD GENERATOR: VALID
```

**Step 3: Commit**

```bash
git add tests/bootstrap/validate-passwords.sh
git commit -m "$(cat <<'EOF'
test: add password generator validation test

Validates 100 generated passwords for:
- Length: exactly 32 characters
- Allowed: A-Z (no I,L,O), a-z (no i,l,o), 2-9, -, _
- Forbidden: I,L,O,i,l,o,0,1,?,%,!,@,#,&,*,+

Usage: bash tests/bootstrap/validate-passwords.sh
Exit: 0 if all pass, 1 if any fail

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>
EOF
)"
```

Expected: Commit created successfully

---

## Task 4: Regenerate Credentials (Clean Break)

**Files:**
- Modify: `/var/lib/ralf/credentials.env` (regenerated)

**Step 1: Verify current credentials exist**

Run: `ls -la /var/lib/ralf/credentials.env`

Expected: File exists with 600 permissions

**Step 2: Run generator (creates automatic backup)**

Run:
```bash
echo "" | bash bootstrap/generate-credentials.sh
```

Expected:
- Prompt about overwriting
- Backup created: `/var/lib/ralf/credentials.env.backup.YYYYMMDD_HHMMSS`
- New credentials generated

**Step 3: Verify backup was created**

Run: `ls -t /var/lib/ralf/credentials.env.backup.* | head -1`

Expected: Most recent backup file listed

**Step 4: Source new credentials**

Run:
```bash
source /var/lib/ralf/credentials.env
echo "Gitea Admin 1 password length: ${#GITEA_ADMIN1_PASS}"
```

Expected: `Gitea Admin 1 password length: 32`

**Step 5: Validate a sample password**

Run:
```bash
source /var/lib/ralf/credentials.env
echo "$GITEA_ADMIN1_PASS" | grep -qE '^[A-Za-z2-9_-]{32}$' && echo "VALID" || echo "INVALID"
```

Expected: `VALID`

**Step 6: Document in commit message (no code change)**

This step is informational - credentials.env is not in Git.

---

## Task 5: Clean-Room Test - Gitea

**Files:**
- Test: Container 2012 (Gitea)
- Test: `tests/gitea/smoke.sh`

**Step 1: Destroy existing Gitea container**

Run:
```bash
pct stop 2012 2>/dev/null || true
pct destroy 2012
```

Expected: Container destroyed, logical volumes removed

**Step 2: Source credentials**

Run:
```bash
source /var/lib/ralf/credentials.env
```

**Step 3: Bootstrap Gitea with new credentials**

Run:
```bash
bash bootstrap/create-gitea.sh 2>&1 | tee /tmp/gitea-bootstrap-cleanroom.log
```

Expected:
- Container 2012 created
- Gitea installed
- Admin users created (kolja, ralf)
- Organization RALF-Homelab created
- Repository created
- No authentication errors (401)

**Step 4: Wait for Gitea to be fully ready**

Run:
```bash
sleep 10
curl -sf http://10.10.20.12:3000 >/dev/null && echo "✅ Gitea UP" || echo "❌ Gitea DOWN"
```

Expected: `✅ Gitea UP`

**Step 5: Test authentication with new password**

Run:
```bash
source /var/lib/ralf/credentials.env
RESULT=$(curl -s -u kolja:${GITEA_ADMIN1_PASS} http://10.10.20.12:3000/api/v1/user | jq -r '.login // "FAIL"')
echo "Auth result: $RESULT"
```

Expected: `Auth result: kolja`

**Step 6: Run smoke tests**

Run: `bash tests/gitea/smoke.sh`

Expected:
```
GITEA SMOKE TEST
  HTTP :3000 erreichbar ... OK
  SSH :2222 erreichbar ... OK
  Host erreichbar (ping) ... OK
  API /api/v1/version ... OK
  Repository RALF-Homelab/ralf ... OK (or SKIP if not created yet)
  Admin User 'kolja' ... OK
  Admin User 'ralf' ... OK

GITEA SMOKE: OK
```

**Step 7: Test second admin user**

Run:
```bash
source /var/lib/ralf/credentials.env
RESULT=$(curl -s -u ralf:${GITEA_ADMIN2_PASS} http://10.10.20.12:3000/api/v1/user | jq -r '.login // "FAIL"')
echo "Auth result: $RESULT"
```

Expected: `Auth result: ralf`

**Step 8: Verify organization and repository exist**

Run:
```bash
source /var/lib/ralf/credentials.env
curl -s -u kolja:${GITEA_ADMIN1_PASS} http://10.10.20.12:3000/api/v1/orgs/RALF-Homelab | jq -r '.name // "NOT FOUND"'
curl -s -u kolja:${GITEA_ADMIN1_PASS} http://10.10.20.12:3000/api/v1/repos/RALF-Homelab/ralf | jq -r '.name // "NOT FOUND"'
```

Expected:
- Organization: `RALF-Homelab`
- Repository: `ralf`

**Step 9: Document results (no commit)**

Results documented in test run, no code changes needed.

---

## Task 6: Update Existing Services - PostgreSQL

**Files:**
- Test: Container 2010 (PostgreSQL)

**Step 1: Verify PostgreSQL is running**

Run: `pct status 2010`

Expected: `status: running`

**Step 2: Source credentials**

Run: `source /var/lib/ralf/credentials.env`

**Step 3: Test OLD password still works**

Run:
```bash
# Get old password from backup
OLD_BACKUP=$(ls -t /var/lib/ralf/credentials.env.backup.* | head -1)
OLD_PASS=$(grep "^export POSTGRES_MASTER_PASS=" "$OLD_BACKUP" | cut -d'"' -f2)

PGPASSWORD="$OLD_PASS" psql -U postgres -h 10.10.20.10 -c '\l' >/dev/null 2>&1 && echo "OLD PASSWORD WORKS" || echo "OLD PASSWORD FAILS"
```

Expected: `OLD PASSWORD WORKS` (or FAILS if container was already recreated)

**Step 4: Change PostgreSQL master password**

Run:
```bash
source /var/lib/ralf/credentials.env

# Use OLD password to connect and change to NEW
OLD_BACKUP=$(ls -t /var/lib/ralf/credentials.env.backup.* | head -1)
OLD_PASS=$(grep "^export POSTGRES_MASTER_PASS=" "$OLD_BACKUP" | cut -d'"' -f2)

PGPASSWORD="$OLD_PASS" psql -U postgres -h 10.10.20.10 <<EOF
ALTER USER postgres WITH PASSWORD '$POSTGRES_MASTER_PASS';
EOF
```

Expected: `ALTER ROLE`

**Step 5: Test NEW password**

Run:
```bash
source /var/lib/ralf/credentials.env
PGPASSWORD="$POSTGRES_MASTER_PASS" psql -U postgres -h 10.10.20.10 -c '\l'
```

Expected: List of databases displayed

**Step 6: Run PostgreSQL smoke test**

Run: `bash tests/postgresql/smoke.sh`

Expected:
```
POSTGRESQL SMOKE TEST
  Host: 10.10.20.10
  Port: 5432
  ...
  TCP :5432 erreichbar ... OK
  Host erreichbar (ping) ... OK
  pg_isready ... OK

POSTGRESQL SMOKE: OK
```

**Step 7: Document results (no commit)**

Results documented in test run, no code changes needed.

---

## Task 7: Test Semaphore (if deployed)

**Files:**
- Test: Container 10015 (Semaphore)

**Step 1: Check if Semaphore is deployed**

Run: `pct status 10015 2>&1`

Expected: Either `status: running` or `Configuration file ... does not exist`

**Step 2: If running, test authentication**

Run (only if Semaphore exists):
```bash
source /var/lib/ralf/credentials.env
curl -s -X POST http://10.10.100.15:3000/api/auth/login \
  -H 'Content-Type: application/json' \
  -d "{\"auth\":\"${SEMAPHORE_ADMIN1_USER}\",\"password\":\"${SEMAPHORE_ADMIN1_PASS}\"}" \
  | jq -r '.token // "AUTH FAILED"'
```

Expected: Token string (not "AUTH FAILED")

**Step 3: If not deployed, skip**

If Semaphore doesn't exist yet, this is expected - it will be tested when deployed.

**Step 4: Document results (no commit)**

Results documented, no code changes needed.

---

## Task 8: Update Documentation

**Files:**
- Modify: `docs/webui-automation-howto.md`

**Step 1: Add password requirements section**

Add after line 15 (in Quick Start section):

```markdown
### Password Requirements

**WICHTIG:** Passwörter werden mit kompatiblen Zeichen generiert:
- Zeichensatz: `A-Z (ohne I,L,O) + a-z (ohne i,l,o) + 2-9 + - + _`
- Länge: **32 Zeichen** (alle Passwörter)
- Kompatibel mit: HTTP Basic Auth, URLs, Shell, PostgreSQL, MariaDB

**Warum diese Einschränkungen?**
Sonderzeichen wie `&`, `%`, `+`, `*` verursachen Probleme bei:
- HTTP Basic Authentication (curl, API calls)
- URL-Parameter
- Shell-Expansion

**Entropie:** ~189 bit (ausreichend für Homelab-Umgebung)
```

**Step 2: Verify changes**

Run: `git diff docs/webui-automation-howto.md`

Expected: New section visible in diff

**Step 3: Commit**

```bash
git add docs/webui-automation-howto.md
git commit -m "$(cat <<'EOF'
docs: add password requirements to automation howto

Documents new password generator character set:
- Compatible chars: A-Za-z2-9-_
- Length: 32 characters (standardized)
- Rationale: HTTP Basic Auth compatibility

Context: Gitea auth failed with special chars (&%+*)
Solution: Use only shell/URL-safe special characters

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>
EOF
)"
```

Expected: Commit created successfully

---

## Task 9: Final Verification & Summary

**Files:**
- Test: All services

**Step 1: Run all smoke tests**

Run:
```bash
echo "=== PostgreSQL ==="
bash tests/postgresql/smoke.sh
echo ""
echo "=== Gitea ==="
bash tests/gitea/smoke.sh
```

Expected: All tests show `OK` or `PASS`

**Step 2: Test password generator one more time**

Run: `bash tests/bootstrap/validate-passwords.sh`

Expected: `✅ PASSWORD GENERATOR: VALID`

**Step 3: Verify credentials file**

Run:
```bash
source /var/lib/ralf/credentials.env
echo "Gitea Admin 1: ${#GITEA_ADMIN1_PASS} chars"
echo "PostgreSQL Master: ${#POSTGRES_MASTER_PASS} chars"
echo "Sample password: ${GITEA_ADMIN1_PASS:0:10}..."
```

Expected:
- All lengths: 32 chars
- Sample shows safe characters only

**Step 4: Create summary commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
fix: password generator overhaul - implementation complete

Summary of changes:
1. ✅ Generator function: special chars ?%!@#&*+ → -_
2. ✅ All passwords: standardized to 32 characters
3. ✅ Validation test: 100/100 passwords pass
4. ✅ Clean-room test: Gitea auth works perfectly
5. ✅ PostgreSQL: master password updated
6. ✅ Documentation: password requirements added

Test results:
- Password validator: 100/100 PASS
- Gitea smoke test: PASS
- PostgreSQL smoke test: PASS
- Gitea auth (kolja): PASS
- Gitea auth (ralf): PASS

Character set: 56 chars (A-Z no ILO + a-z no ilo + 2-9 + -_)
Entropie: 189 bit @ 32 chars (vs 146 bit @ 24 chars old)

Root Cause: HTTP Basic Auth fails with &%+* characters
Solution: Use only shell/URL-safe special characters

Closes: Clean-Room Test Failure Issue
Related: docs/plans/2026-02-15-password-generator-overhaul-design.md

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>
EOF
)"
```

Expected: Final commit created

**Step 5: Print summary**

Run:
```bash
cat <<'SUMMARY'
╔══════════════════════════════════════════════════════════════╗
║  PASSWORD GENERATOR OVERHAUL - IMPLEMENTATION COMPLETE       ║
╚══════════════════════════════════════════════════════════════╝

✅ Generator Updated
   - Special chars: ?%!@#&*+ → -_
   - Default length: 32 characters

✅ Credentials Regenerated
   - 10 admin passwords: 24 → 32 chars
   - All passwords validated
   - Automatic backup created

✅ Services Tested
   - Gitea: Clean-room deployment SUCCESS
   - PostgreSQL: Password updated, connection OK
   - Smoke tests: ALL PASS

✅ Documentation Updated
   - Password requirements documented
   - Rationale explained

📊 Results:
   - Character set: 56 chars
   - Entropy: 189 bit (32 chars)
   - Compatibility: HTTP/URLs/Shell ✅
   - Test coverage: 100/100 passwords valid

🎯 Next Steps:
   1. Deploy to production
   2. Test remaining services (Semaphore, n8n, Matrix)
   3. Monitor for any authentication issues

SUMMARY
```

Expected: Summary printed

---

## Rollback Procedure (If Needed)

If any tests fail catastrophically:

**Step 1: Restore old credentials**

```bash
BACKUP=$(ls -t /var/lib/ralf/credentials.env.backup.* | head -1)
cp "$BACKUP" /var/lib/ralf/credentials.env
source /var/lib/ralf/credentials.env
```

**Step 2: Revert code changes**

```bash
cd /root/ralf/.worktrees/feature/ralf-completion
git log --oneline | head -10  # Find commit before changes
git reset --hard <commit-hash-before-changes>
```

**Step 3: Restore container from snapshot**

```bash
pct rollback 2012 pre-install  # If snapshot exists
pct start 2012
```

---

## Notes

- **TDD:** Password validation test created before regenerating credentials
- **DRY:** Reuses existing backup mechanism in generate-credentials.sh
- **YAGNI:** No password profiles, no rotation automation (not needed yet)
- **Frequent commits:** 8 commits total (small, atomic changes)
- **Complete code:** All changes shown in full, no "add validation" placeholders

## References

- Design: `docs/plans/2026-02-15-password-generator-overhaul-design.md`
- Generator: `bootstrap/generate-credentials.sh`
- Tests: `tests/bootstrap/validate-passwords.sh`
- Smoke Tests: `tests/gitea/smoke.sh`, `tests/postgresql/smoke.sh`
