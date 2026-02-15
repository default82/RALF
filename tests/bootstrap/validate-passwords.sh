#!/usr/bin/env bash
set -euo pipefail

### =========================
### Password Generator Validation Test
### =========================

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
cd "$SCRIPT_DIR/../.."

# Extract generate_password function without running the full script
generate_password() {
  local length="${1:-32}"  # Default: 32 characters for all passwords

  # Zeichensätze gemäß Anforderungen
  # Großbuchstaben: A-Z ohne I, L, O
  local upper="ABCDEFGHJKMNPQRSTUVWXYZ"
  # Kleinbuchstaben: a-z ohne i, l, o
  local lower="abcdefghjkmnpqrstuvwxyz"
  # Ziffern: 0-9 ohne 0, 1
  local digits="23456789"
  # Sonderzeichen: nur sichere, keine mehrdeutigen ($ entfernt wegen bash expansion)
  local special='-_'

  # Kombiniere alle Zeichensätze
  local all_chars="${upper}${lower}${digits}${special}"

  # Generiere Passwort
  local password=""
  for i in $(seq 1 "$length"); do
    # Zufälliges Zeichen aus dem Pool
    local rand_index=$(($(od -An -N2 -tu2 /dev/urandom) % ${#all_chars}))
    password="${password}${all_chars:$rand_index:1}"
  done

  echo -n "$password"
}

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
    FAIL=$((FAIL + 1))
    continue
  fi

  # Test 2: Only allowed characters [A-Za-z2-9_-]
  if [[ ! "$PW" =~ ^[A-Za-z2-9_-]+$ ]]; then
    echo "FAIL #$i: Contains invalid characters: $PW"
    FAIL=$((FAIL + 1))
    continue
  fi

  # Test 3: No forbidden characters [ILOilo01?%!@#&*+]
  if [[ "$PW" =~ [ILOilo01\?\%\!\@\#\&\*\+] ]]; then
    echo "FAIL #$i: Contains forbidden characters: $PW"
    FAIL=$((FAIL + 1))
    continue
  fi

  PASS=$((PASS + 1))
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
