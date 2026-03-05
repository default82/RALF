# IP-Adressenvergabe – Konvention

Version 1.0 – Kanonisch (MVP)

## Schema

Alle Dienste nutzen den Adressraum `10.10.0.0/16`.

Das dritte Oktett (`x`) bestimmt die **Dienstkategorie**.
Das vierte Oktett (`y`) bestimmt die **laufende Nummer** des Dienstes innerhalb der Kategorie.

```
10.10.x.y
```

## Kategorien

| x   | Kategorie                                    | Beispiele                          |
|-----|----------------------------------------------|------------------------------------|
| 0   | Netzwerk                                     | Router, Switches                   |
| 10  | Hardware                                     | PVE-NICs, Proxmox-Host             |
| 20  | Datenbanken                                  | PostgreSQL                         |
| 30  | Backup & Sicherheit                          | MinIO                              |
| 40  | Web & Verwaltungsoberflächen                 | Gitea                              |
| 50  | Verzeichnisdienste & Authentifizierung       | Vaultwarden                        |
| 60  | Medienserver & Verwaltung                    | (reserviert)                       |
| 70  | Dokumenten- & Wissensmanagement              | (reserviert)                       |
| 80  | Monitoring & Logging                         | Prometheus                         |
| 90  | Künstliche Intelligenz & Datenverarbeitung   | KI-Instanz                         |
| 100 | Automatisierung                              | Semaphore, n8n                     |
| 110 | Kommunikation und Steuerung                  | Matrix Synapse                     |
| 120 | Spiele                                       |                                    |
| 200 | Funktionale VM                               |                                    |

## Aktuelle Dienst-Zuordnung

| Dienst          | IP              | CTID  | Kategorie (x)                          |
|-----------------|-----------------|-------|----------------------------------------|
| PostgreSQL      | 10.10.20.10     | 2010  | 20 – Datenbanken                       |
| MinIO           | 10.10.30.10     | 3010  | 30 – Backup & Sicherheit               |
| Gitea           | 10.10.40.10     | 4010  | 40 – Web & Verwaltungsoberflächen      |
| Vaultwarden     | 10.10.50.10     | 5010  | 50 – Verzeichnisdienste & Auth.        |
| Prometheus      | 10.10.80.10     | 8010  | 80 – Monitoring & Logging              |
| KI-Instanz      | 10.10.90.10     | 9010  | 90 – KI & Datenverarbeitung            |
| Semaphore       | 10.10.100.10    | 10010 | 100 – Automatisierung                  |
| n8n             | 10.10.100.20    | 10020 | 100 – Automatisierung                  |
| Matrix Synapse  | 10.10.110.10    | 11010 | 110 – Kommunikation und Steuerung      |

## CTID-Schema

Die Proxmox-Container-ID (CTID) folgt dem Muster:

```
CTID = x * 100 + y
```

Dabei ist `y` der Wert des vierten Oktetts (z. B. `10` für den ersten Dienst, `20` für den zweiten).

Beispiel: Kategorie 80, erster Dienst (y=10) → CTID = `80 * 100 + 10` = `8010`

## Regeln

- Neue Dienste werden in die passende Kategorie eingeordnet.
- Das vierte Oktett (`y`) beginnt bei `.10` für den ersten Dienst und wird in 10er-Schritten erhöht.
- Keine statische IP außerhalb dieses Schemas.
- Änderungen an dieser Konvention erfordern Diskurs und Versionierung dieses Dokuments.
