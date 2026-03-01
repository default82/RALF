# PostgreSQL Dienstkartei (RALF)

## Phase 1: Dienstkartei + Requirements

- Dienst: `postgresql`
- Zweck: zentrale Status-/Gedaechtnisschicht fuer RALF (Events, Zustands-Snapshots, Metadaten)
- Betriebsmodell: Proxmox LXC (Ubuntu 24.04 LTS), LXC-first

### Ports

- `5432/tcp` intern (10.10.0.0/16)
- Kein oeffentliches Exposing ueber WAN

### Abhaengigkeiten

- Proxmox VE mit `pct`
- Ubuntu 24.04 LXC-Template vorhanden oder auto-downloadbar
- DNS-Aufloesung fuer `postgres.otta.zone` (intern)
- Secrets-Zufuehrung via ENV/Vaultwarden-Referenz

### Ressourcenprofil (Zweierpotenzen)

- CPU: `2`
- RAM: `2048 MB`
- RootFS: `16 GB`
- Swap: `0`

### Security-Notizen

- `listen_addresses` auf internen Zielbereich begrenzen
- `pg_hba.conf` nur local + `10.10.0.0/16` mit `scram-sha-256`
- keine Klartext-Secrets im Repo
- UFW optional (default `false`), damit kein stiller Konflikt mit Proxmox-Firewall entsteht

`Statusobjekt`
```json
{
  "step_id": "postgres_phase_1_service_card",
  "result": "OK",
  "summary": "Dienstprofil, Ports, Dependencies, Ressourcen und Security-Basis fuer PostgreSQL sind definiert.",
  "artifacts": [
    "services/postgresql/service_card.md"
  ],
  "next_actions": [
    "Phase 2 Platzierung final freigeben",
    "DNS-Record intern fuer postgres.otta.zone eintragen"
  ]
}
```

## Phase 2: Platzierungsvorschlag + Gate 1

- Hostname: `postgres-ops`
- IP: `10.10.20.10/16`
- DNS: `postgres.otta.zone` (intern)
- CTID/VMID-Regel: `20010`
- Plattform: `LXC` (begruendet)

### Warum LXC (statt VM)

- geringe Overhead-Kosten bei NUC-sparsamer Zielplattform
- schneller Provision/Restart
- fuer PostgreSQL in homelab-internem Netz ausreichend isoliert
- entspricht LXC-first Leitplanke

`Statusobjekt`
```json
{
  "step_id": "postgres_phase_2_placement",
  "result": "OK",
  "summary": "Platzierung fuer PostgreSQL auf 10.10.20.10 als LXC ist konsistent mit Netz-/Ressourcen-Policy.",
  "artifacts": [
    "services/postgresql/service_card.md"
  ],
  "next_actions": [
    "Phase 3 OpenTofu-Inputs anwenden",
    "Template-Verfuegbarkeit auf Storage pruefen"
  ]
}
```
