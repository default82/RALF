# Secrets-Handling (MinIO)

## Policy

- Keine MinIO-Secrets im Repository.
- Laufzeitgenerierung mit mindestens 32 Zeichen.
- Primaere Ablage: Vaultwarden:
- `ralf/minio/root_user`
- `ralf/minio/root_password`
- Lokale Ablage: `/root/ralf-secrets/minio.generated` (Mode `600`).
- Runtime-Config: `/etc/minio/minio.env` (Mode `600`).

## Verwendete Credentials

- `MINIO_ROOT_USER`
- `MINIO_ROOT_PASSWORD`

## Blocker-Kriterium

- Wenn weder Vaultwarden-Injektion noch lokale Secret-Datei vorhanden ist, dann Deploy `Blocker`.
