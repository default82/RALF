# Read-only Deploymentplan für `postgresql-main`

## Zweck und Grenze

`scripts/postgresql-main-plan.py` erstellt einen service-spezifischen, ausschließlich lesenden Bereitstellungsplan für die erste PostgreSQL-Providerinstanz des Database Service. Er validiert lokale Planungsdaten, paketierte Referenzstände und den vorhandenen Proxmox-Zustand. Anschließend beschreibt er alle Mutationen, die ein späterer, getrennt freizugebender Bereitstellungsschritt benötigen würde.

Der Planer besitzt ausschließlich den Modus `plan`. Er erstellt keinen LXC, installiert keine Pakete, konfiguriert PostgreSQL nicht und legt weder Datenbanken, Identitäten, TLS-Artefakte, Secrets noch Backups an. Es gibt keinen `apply`-, `create`-, `install`-, `provision`-, `delete`- oder `restore`-Modus.

## Referenzprofil

| Eigenschaft | Referenzwert |
| --- | --- |
| Plattform | Proxmox VE |
| Virtualisierung | eigener unprivilegierter LXC, nesting aktiviert |
| Betriebssystem | Ubuntu Server 26.04 LTS, amd64/x86_64 |
| Containerlaufzeit | kein Docker oder Podman |
| Hostname | `postgresql-main` |
| Paketquelle | offizielle Ubuntu-26.04-Quellen, keine PGDG-Quelle |
| Paket | `postgresql-18` |
| Versionspolitik | neueste stabile 18.x-Minor-Version; kein automatischer Wechsel auf PostgreSQL 19 |
| CPU | 4 vCPU |
| RAM | 8192 MiB |
| Swap | 2048 MiB |
| Root-Disk | 100 GiB auf SSD oder vergleichbar geeignetem persistentem Storage |

Die Ressourcenwerte sind das Referenzprofil, keine allgemeinen Mindestanforderungen. Niedrigere Werte erzeugen sichtbare Warnungen. Fehlendes Storage, zu wenig freier Speicher oder uneindeutige Infrastrukturwerte blockieren den Plan.

## Deploymentkonfiguration

Die reale Konfiguration wird ausschließlich aus folgendem Pfad gelesen:

```text
/secrets/database-service/providers/postgresql-main/deployment.toml
```

Sie enthält deployment-spezifische, aber keine geheimen Angaben. Das Repository enthält mit [`deploy/postgresql/postgresql-main.example.toml`](../../deploy/postgresql/postgresql-main.example.toml) nur ein offensichtlich unvollständiges Beispiel. Der Planer verwendet dieses Beispiel niemals automatisch.

Die Konfiguration wird streng validiert. Unbekannte Schlüssel, eine andere Schema-Version, ein anderer Provider, eine andere PostgreSQL-Major-Version oder eine von genau `gitea`, `openbao`, `semaphore` und `nodered` abweichende Allocation-Menge werden abgelehnt. VMID, Storage, Bridge, IPv4-Konfiguration, FQDN, Consumer-Allowlists und Backupziel müssen explizit angegeben oder nach den dokumentierten Eindeutigkeitsregeln lesend ermittelt werden können.

`vmid = 0` fordert die nächste freie VMID an. Ein leeres Storage oder eine leere Bridge ist nur dann zulässig, wenn exakt ein geeigneter Kandidat vorhanden ist. Mehrdeutigkeit ist ein Blocker. Der Planer erfindet keine IP-Adresse, kein Gateway, keinen DNS-Wert und kein Backupziel. DNS-Server werden als kanonische IP-Adressen explizit angegeben; eine leere Liste blockiert den Plan.

Leere `allowed_client_cidrs` sind als noch unvollständiger Planungsstand zulässig, blockieren aber Remote-Readiness. Globale Freigaben wie `0.0.0.0/0` oder `::/0` und nicht kanonische CIDRs werden abgelehnt.

Das externe Backupziel ist verpflichtend. Zusätzlich bestätigt `protection_confirmed`, dass der Zielbereich verschlüsselt oder anderweitig angemessen geschützt ist; ohne diese Bestätigung bleibt der Plan blockiert. `minimum_free_gib` hält die deployment-spezifisch verlangte freie Kapazität fest.

## Versionsmatrix

[`deploy/postgresql/version-matrix.toml`](../../deploy/postgresql/version-matrix.toml) ist eine versionierte, offline gelesene Referenzmatrix mit Stichtag 2. August 2026:

- PostgreSQL 18, initial dokumentiert 18.4, Paket `postgresql-18`, Policy `latest-stable-18.x`,
- Gitea 1.27.1 mit dokumentierter PostgreSQL-Anforderung `>=12`,
- OpenBao 2.6.1 mit PostgreSQL-Storage und dokumentierter Anforderung `>=9.5`,
- Semaphore UI 2.18.29 mit Backend `postgres`,
- Node-RED 5.0.4 mit Node.js-Referenz 24 und ausschließlich relationalen Flow-Anwendungsdaten.

Die Matrix installiert nichts und führt keine Onlineprüfung aus. Unmittelbar vor einer späteren Installation muss erneut geprüft werden, welche stabile 18.x-Version die offiziellen Ubuntu-26.04-Quellen tatsächlich anbieten und ob alle vorgesehenen Anwendungsversionen dazu kompatibel sind. Semaphore dokumentiert PostgreSQL-Unterstützung, aber keine hier festgelegte maximale PostgreSQL-Version. Node-RED erhält nicht automatisch einen internen PostgreSQL-Speicher; dafür ist später ein konkreter PostgreSQL-Node oder ein eigener Flow-Vertrag erforderlich.

## Aufruf

```bash
sudo python3 scripts/postgresql-main-plan.py \
  plan \
  --config /secrets/database-service/providers/postgresql-main/deployment.toml
```

Andere Konfigurationspfade werden von der Kommandozeile bewusst abgelehnt. Tests verwenden ausschließlich direkte, temporäre Eingaben und Mock-Probes.

## Read-only Prüfungen

Der Planer darf nur fest definierte, begrenzte Argumentlisten für lesende Proxmox- und Hostprüfungen verwenden. Er liest:

- Proxmox-Version,
- vorhandene Container und den Zustand einer gegebenenfalls belegten VMID,
- Storage-Status und freie Kapazität,
- Linux-Bridges, Adressen und Routen,
- verfügbare Ubuntu-Container-Templates,
- Metadaten der Deploymentkonfiguration, Secretreferenzen, TLS-Pfade und des Backupziels,
- den lokalen Git-Commit und die paketierte Versionsmatrix.

Externe Aufrufe besitzen feste Argumentlisten, kurze Zeitlimits und begrenzte Ausgaben. Es gibt kein `shell=True`, keinen Netzwerkscan, keine PostgreSQL-Verbindung und keine Online-Versionsabfrage.

## Secrets- und TLS-Vertrag

`/secrets` bleibt die einzige Secrets-Wurzel. Der Planer prüft vorhandene Pfade ausschließlich per Dateimetadaten. Er liest keine Secretwerte, berechnet keine Inhalts-Hashes und gibt keine Inhalte aus.

Geplante Allocation-Referenzen sind:

```text
/secrets/database-service/allocations/gitea/application-password
/secrets/database-service/allocations/openbao/application-password
/secrets/database-service/allocations/semaphore/application-password
/secrets/database-service/allocations/nodered/application-password
```

TLS wird später über eine dedizierte CA und ein Serverzertifikat für den konfigurierten FQDN bereitgestellt. Die geplanten Referenzen liegen unter `/secrets/database-service/providers/postgresql-main/pki/`. Der Planer erzeugt oder liest weder Schlüssel noch Zertifikatsinhalte. Eine neue CA darf erst nach eigener ausdrücklicher Freigabe entstehen; öffentliche ACME-Zertifikate und ein automatischer OPNsense-Zugriff sind nicht vorgesehen.

Zielmetadaten eines späteren Apply wären `root:root` mit Modus `0700` für Secretverzeichnisse und `0600` für Passwortdateien sowie private Schlüssel. Symlinks, unsichere Rechte, unerwartete Eigentümer oder leere vorhandene Passwortdateien werden als Konflikt gemeldet. Fehlende Pfade werden nur als später anzulegende Artefakte angezeigt.

Ein späterer Apply dürfte Klartextwerte nur kurzfristig über `/run/ralf-database-provision/` auf einem geschützten tmpfs in den LXC übertragen und müsste sie unmittelbar nach der jeweiligen Identitätsanlage entfernen. Dieser Mechanismus ist noch nicht implementiert.

## PostgreSQL-Zielvertrag

Der Plan beschreibt folgenden späteren Sicherheitszustand:

- lokale Administration über Unix-Socket und Peer-Authentifizierung,
- kein gespeichertes PostgreSQL-Superuserkennwort als Standard,
- keine Remote-Superuseranmeldung,
- `password_encryption = scram-sha-256`,
- Remotezugriff ausschließlich per TLS auf die konkrete Provideradresse,
- kein Listener auf `0.0.0.0`,
- pro Allocation eine eigene `hostssl`-Grenze für eigene Datenbank, Identität und Clientnetze,
- SCRAM-SHA-256 für Remote-Authentifizierung,
- normale Anwendungsidentitäten ohne Superuser-, Datenbankerstellungs-, Rollenerstellungs- oder Replikationsrechte,
- keine Consumer-übergreifenden Anwendungsobjekte über globale `PUBLIC`-Rechte.

Für `application_managed` dürfen Anwendungen Objekte und Migrationen ausschließlich in ihrer eigenen logischen Datenbank verwalten. Die konkrete SQL- und `public`-Schema-Umsetzung gehört in einen späteren Apply-Schritt.

## Backupvertrag

Referenzstandard ist ein logisches PostgreSQL-Custom-Format pro Allocation, später sinngemäß mit `pg_dump --format=custom`. Die Daten sollen vom LXC zum Proxmox-Host gestreamt werden; im Datenbank-LXC ist kein dauerhafter Backup-Mount vorgesehen.

Unter dem explizit konfigurierten Host-Root wäre später folgende Struktur anzulegen:

```text
postgresql-main/
├── gitea/
├── openbao/
├── semaphore/
└── nodered/
```

Backupdateien wären `root:root` und `0600`. Der Planer legt weder Verzeichnisse noch Backups an. Automatische Retention oder Löschung gehört nicht zu diesem Schritt.

## Planausgabe und Blocker

Die Ausgabe enthält Repository und Matrix, Proxmox-Ziel, Netzwerk, PostgreSQL-Sicherheitsvertrag, jede Allocation, Secret- und TLS-Metadaten, Backupziel, spätere Mutationen sowie ausdrücklich ausgeschlossenen Umfang. Secretinhalte erscheinen nie.

Typische Blocker sind:

- fehlende oder ungültige reale Konfiguration,
- belegte oder nicht eindeutig ermittelbare VMID,
- uneindeutiges oder fehlendes Storage beziehungsweise Bridge,
- fehlendes Ubuntu-26.04-amd64-Template,
- zu wenig freier Storage,
- leere Client-Allowlist,
- unsichere bestehende Secret- oder TLS-Metadaten,
- fehlendes, ungeeignetes oder unbestätigt geschütztes Backupziel.

Der letzte Ausgabewert ist genau `PLAN_READY` oder `PLAN_BLOCKED`. `PLAN_READY` ist ausschließlich eine Planungsbewertung und keine Freigabe oder Ausführung.

## Nächster Schritt

Nach Review und Merge kann ein getrennt entworfener Apply-Vertrag die bereits vollständig sichtbaren Mutationen, Transaktionsgrenzen, Recovery-Strategien und Einzelbestätigungen spezifizieren. Bis dahin bleibt jede Infrastruktur unverändert.
