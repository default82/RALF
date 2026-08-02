# ADR-0006: Laufzeitprofil für `postgresql-main`

- **Status:** Angenommen
- **Datum:** 2026-08-02

## Kontext

ADR-0005 wählt PostgreSQL 18, die Providerinstanz `postgresql-main` und vier isolierte Allocations. Für einen reproduzierbaren, zunächst ausschließlich lesenden Deploymentplan müssen Betriebsform, Referenzressourcen, Paketquelle, Netzwerk- und Sicherheitsziele sowie die Backupgrenze konkretisiert werden.

Der Plan darf noch keine Infrastruktur verändern. Deployment-spezifische Netz- und Proxmox-Werte bleiben außerhalb des Repositorys.

## Entscheidung

Das erste Referenzdeployment verwendet:

| Eigenschaft | Entscheidung |
| --- | --- |
| Plattform | Proxmox VE |
| Virtualisierung | eigener unprivilegierter LXC mit aktiviertem nesting |
| Betriebssystem | Ubuntu Server 26.04 LTS |
| Architektur | amd64/x86_64 |
| Containerlaufzeit | weder Docker noch Podman |
| Hostname | `postgresql-main` |
| PostgreSQL-Paket | `postgresql-18` |
| Paketquelle | offizielle Ubuntu-26.04-Quellen; keine zusätzliche PGDG-Quelle |
| Major-Version | 18 |
| Minor-Policy | neueste stabile 18.x-Version zum Installationszeitpunkt |

Der read-only Planer muss sichtbar melden, wenn die offiziellen Quellen nicht die erwartete aktuelle 18.x-Version anbieten. Er führt selbst keine Onlineprüfung durch. Ein automatischer Wechsel auf PostgreSQL 19 ist ausgeschlossen; Major-Upgrades benötigen einen eigenen Plan und eine eigene Freigabe.

## Referenzressourcen

- 4 vCPU,
- 8192 MiB RAM,
- 2048 MiB Swap,
- 100 GiB Root-Disk,
- SSD oder vergleichbar geeigneter persistenter Storage.

Dies sind Referenzwerte und keine universellen Mindestanforderungen. Eine lokale Deploymentkonfiguration darf sie überschreiben. Niedrigere Werte müssen im Plan als Abweichung erscheinen; fehlendes oder zu kleines Storage blockiert die Planung.

## Netzwerk- und PostgreSQL-Sicherheitsgrenze

Die Providerinstanz lauscht später ausschließlich auf ihrer konkret konfigurierten Adresse, nicht auf `0.0.0.0`. Remoteverbindungen sind auf TLS, SCRAM-SHA-256, die jeweilige logische Datenbank, deren eigene Anwendungsidentität und allocation-spezifische Client-CIDRs begrenzt. Eine leere Client-Allowlist blockiert Remote-Readiness.

Lokale Administration erfolgt über Unix-Socket und Peer-Authentifizierung. Es gibt standardmäßig kein gespeichertes PostgreSQL-Superuserkennwort und keine Remote-Superuseranmeldung. Consumer erhalten keine Superuser-, Datenbankerstellungs-, Rollenerstellungs- oder Replikationsrechte und keine Rechte auf fremde Allocations.

TLS verwendet eine dedizierte, deployment-spezifische CA und ein Serverzertifikat für den konfigurierten FQDN. Es gibt keine öffentliche ACME-CA und keinen automatischen Zugriff auf OPNsense. Erzeugung und Verteilung der TLS-Artefakte benötigen später eine eigene Freigabe.

## Secrets-Grenze

Die reale Deploymentkonfiguration und sämtliche Datenbank- sowie TLS-Geheimnisse liegen ausschließlich unter `/secrets` auf dem Proxmox-Host. Das Repository enthält nur ein nicht geheimes Beispiel und absolute Secretreferenzen.

Der Planer liest ausschließlich Dateimetadaten und weder Secretwerte noch private Schlüssel. Fehlende Secrets werden als spätere Mutation angezeigt; der Planer erstellt `/secrets` oder Unterpfade nicht. Ein späterer temporärer Transfer in den LXC wäre ausschließlich über ein geschütztes tmpfs unter `/run/ralf-database-provision/` zulässig und ist nicht Bestandteil dieser Entscheidungsausführung.

## Backupgrenze

Das Backupziel wird in der lokalen Deploymentkonfiguration als absoluter Hostpfad ausdrücklich angegeben. Es besitzt keinen automatischen Standardwert, liegt weder im LXC-Dateisystem noch unter `/secrets` oder im Git-Repository und muss als verschlüsselt oder anderweitig angemessen geschützt bestätigt sein.

Referenzstandard ist ein logisches Custom-Format pro Allocation, später sinngemäß mit `pg_dump --format=custom`. Backups werden zum Proxmox-Host gestreamt; es gibt keinen dauerhaften Backup-Mount im Datenbank-LXC. Retention und automatisches Löschen bleiben offen.

## Begründung

- Ein eigener unprivilegierter LXC begrenzt die Providerinstanz gegenüber Host und Consumern.
- Ubuntu 26.04 LTS und dessen offizielle Quellen vermeiden für das Referenzprofil eine zusätzliche Paketquelle.
- PostgreSQL 18 bleibt innerhalb der in ADR-0005 festgelegten Major-Grenze aktuell.
- Explizite Proxmox-, Netzwerk-, Secret- und Backupwerte verhindern stille Infrastrukturannahmen.
- TLS, SCRAM und allocation-spezifische Regeln bewahren die vereinbarte Isolation auch auf der nativen PostgreSQL-Datenebene.
- Ein externes, allocation-bezogenes Backupziel unterstützt getrennte Wiederherstellung ohne dauerhaften Host-Mount im LXC.

## Konsequenzen

- Der Planer darf VMID, Storage und Bridge nur bei exakt eindeutiger Auswahl automatisch bestimmen.
- IP-Adresse, Präfix, Gateway, FQDN, Consumer-Netze und Backupziel werden nie erraten.
- Das Ubuntu-Template, die freie Storagekapazität und vorhandene Konflikte werden ausschließlich read-only geprüft.
- Der Plan zeigt alle späteren LXC-, Paket-, TLS-, PostgreSQL-, Allocation-, Secret- und Backupmutationen, führt aber keine davon aus.
- Gitea, OpenBao, Semaphore UI und Node-RED werden nicht installiert.
- Der Node-RED-Datenbankvertrag bleibt auf relationale Flow-Anwendungsdaten begrenzt.

## Sicherheitsfolgen

Ein unprivilegierter LXC und getrennte Datenbankidentitäten reduzieren, beseitigen aber nicht die gemeinsame Fehler- und Ressourcendomäne der Providerinstanz. Insbesondere die hochsensible OpenBao-Allocation kann später eine dedizierte Instanz erfordern. Diese Platzierungsentscheidung bleibt sichtbar und separat freigabepflichtig.

Secretwerte dürfen weder im Plan noch im Repository, in Logs, Prozessargumenten oder normalen Umgebungsvariablen erscheinen. Ein `PLAN_READY` bestätigt nur die Vollständigkeit und Widerspruchsfreiheit der Planung.

## Verworfene Alternativen

- **Docker oder Podman im LXC:** für das Referenzprofil nicht erforderlich und zusätzliche Betriebsgrenze.
- **PGDG-Paketquelle:** nicht ausgewählt, solange das gewünschte 18.x-Paket aus den offiziellen Ubuntu-26.04-Quellen geeignet verfügbar ist.
- **Listener auf allen Adressen:** wegen unnötig breiter Angriffsfläche verworfen.
- **Globale Client-Allowlist:** wegen fehlender Allocation-Isolation verworfen.
- **Automatisches Backupziel:** wegen deployment-spezifischer Storage- und Schutzanforderungen verworfen.
- **Secrets im Repository oder dauerhaft im LXC:** wegen Offenlegungs- und Lebenszyklusrisiken verworfen.
- **Sofortiger Apply-Modus:** bis zum getrennten Mutations-, Recovery- und Freigabevertrag zurückgestellt.

## Offene Punkte

- konkrete VMID, Storage, Bridge, Adresse, FQDN, Gateway und Consumer-CIDRs,
- konkretes verfügbares Ubuntu-26.04-amd64-Template,
- tatsächliche 18.x-Paketversion in den offiziellen Ubuntu-Quellen zum Installationszeitpunkt,
- Eigentümermodell für Consumerzugriffe auf Secretdateien,
- Erzeugung, Rotation und Verteilung von Passwörtern und TLS-Artefakten,
- Backup-Retention und Wiederherstellungstest,
- Ressourcenlimits innerhalb der Providerinstanz,
- Apply-Transaktionsgrenzen und Recovery nach Teilerfolgen.

## Nächster Schritt

Nach Review und Merge wird ein getrenntes, weiterhin ausdrücklich freizugebendes Apply-Konzept entworfen. Der aktuelle Planer bleibt strikt read-only; keine Infrastruktur wird durch diese Entscheidung verändert.
