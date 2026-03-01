# Secrets-Handling (PostgreSQL)

## Policy

- Keine DB-Passwoerter im Repo.
- Nur Referenzen (`*_REF`) und ENV-Namen dokumentieren.
- Laufzeit-Injektion via Vaultwarden/Runner-ENV.

## Verwendete ENV-Variablen

- `RALF_POSTGRES_POSTGRES_PASSWORD`
- `RALF_POSTGRES_RALF_USER_PASSWORD`

## Blocker-Kriterium

Wenn die beiden ENV-Variablen zur Deploy-Zeit fehlen, ist Deploy `Blocker`.
