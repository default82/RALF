# MinIO Dienstkartei (RALF)

## Phase 1: Dienstkartei

- Dienst: `minio`
- Zweck: zentraler S3-kompatibler Object-Store fuer R.A.L.F. (Statefiles, Planfiles, Artefakte, Reports)
- Betriebsmodell: Proxmox LXC (Ubuntu 24.04), ohne Docker
- Funktionsgruppe (X): `30` (Backup & Sicherheit)

### Ports

- `9000/tcp` S3 API (nur LAN `10.10.0.0/16`)
- `9001/tcp` MinIO Console (nur LAN `10.10.0.0/16`)

### Ressourcenprofil (Zweierpotenzen)

- CPU: `2`
- RAM: `2048 MB`
- RootFS: `8 GB`
- Datenvolume (`/srv/minio-data`): `128 GB`
- Swap: `1024 MB`

### Abhaengigkeiten / Verknuepfungen

- Dependencies (Dienst-zu-Dienst): `keine` (Startdienst)
- Wird genutzt von:
- `semaphore` (S3 State/Plan/Report Artefakte)
- `n8n` (Artefakte)

### Credentials

- `MINIO_ROOT_USER`
- `MINIO_ROOT_PASSWORD`
- Generierung: zur Laufzeit, kryptographisch sicher, mindestens 32 Zeichen
- Vaultwarden-Referenzen:
- `ralf/minio/root_user`
- `ralf/minio/root_password`
- Persistenz: `/root/ralf-secrets/minio.generated` (Mode `600`)
- Repo: nur Platzhalter und `.env.example`

### Persistente Daten

- `/srv/minio-data` (extra Mountpoint `mp0`, nicht rootfs)
- Bucket `ralf-state` (Versioning ON)
- Bucket `ralf-artifacts`

`Statusobjekt`
```json
{
  "step_id": "minio_phase_1_service_card",
  "result": "OK",
  "summary": "MinIO als zentraler RALF State/Object-Store mit Ressourcen, Ports, Dependencies und Secret-Policy festgelegt.",
  "ip": "10.10.30.10",
  "ctid": 3010,
  "funktionsgruppe_x": 30,
  "dependencies": [],
  "used_by": [
    "semaphore",
    "n8n"
  ],
  "next_actions": [
    "Phase 2 Platzierung und Firewall festschreiben",
    "Phase 3 pct Deployment ausfuehren"
  ]
}
```

## Phase 2: Platzierung

- Hostname: `minio`
- FQDN: `minio.<LAB_DOMAIN>`
- IP: `10.10.30.10/16`
- CTID Formel: `CTID = X * 100 + Y`
- CTID Ergebnis: `30 * 100 + 10 = 3010`
- Gateway: `10.10.0.1`
- DHCP: `nein` (statisch)

### Security Defaults

- LXC: `unprivileged=1` (Isolation/Hardening, fuer MinIO ausreichend)
- Proxmox Firewall: aktiv
- Inbound: nur `22`, `9000`, `9001` aus `10.10.0.0/16`

`Statusobjekt`
```json
{
  "step_id": "minio_phase_2_placement",
  "result": "OK",
  "summary": "MinIO ist deterministisch in Funktionsgruppe 30 mit statischer IP 10.10.30.10 und CTID 3010 eingeordnet.",
  "ip": "10.10.30.10",
  "ctid": 3010,
  "funktionsgruppe_x": 30,
  "dependencies": [],
  "used_by": [
    "semaphore",
    "n8n"
  ],
  "next_actions": [
    "Phase 3 Proxmox Deployment ausfuehren",
    "Phase 4 install.sh im Container ausrollen"
  ]
}
```
