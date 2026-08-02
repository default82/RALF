# Dienst 001: Database Service – Architektur

## Zweck

Der Database Service ist die stabile persistente Datenschnittstelle von RALF. Er stellt strukturierte, transaktionale Datenhaltung als eigenständige RALF-Fähigkeit bereit und verantwortet deren Lebenszyklus. PostgreSQL ist die erste Referenzimplementierung, aber kein Bestandteil des öffentlichen RALF-Vertrags.

Andere RALF-Komponenten dürfen deshalb keine PostgreSQL-Verbindungsparameter, Systemtabellen, Erweiterungen, SQL-Dialekte, Fehlermeldungen oder Rollen voraussetzen. Das gilt ausdrücklich auch für `psql`, `pg_dump`, `pg_restore` und `pgvector`. PostgreSQL-spezifische Details bleiben im PostgreSQL-Provider sowie dessen Betriebs- und Administrationsschicht.

## Architekturmodell

```text
RALF-Komponenten
       │
       ▼
RALF Database Contract
       │
       ▼
Database Service
       │
       ▼
Provider
       │
       └── PostgreSQL
```

Der **RALF Database Contract** beschreibt benötigte Fähigkeiten, providerneutrale Zustände und Fehler, Lebenszyklusoperationen, Schema- und Migrationsregeln sowie Sicherheits-, Backup- und Restore-Anforderungen.

Der **Database Service** verantwortet die persistente strukturierte Datenhaltung, die Einhaltung des Vertrags, die Auswahl genau eines aktiven Providers, Fähigkeits- und Statusmeldungen, kontrollierte Schemaentwicklung und die Verträge für Sicherung und Wiederherstellung.

Ein **Provider** bildet diesen Vertrag auf ein konkretes Datenbanksystem ab. Der erste Provider ist PostgreSQL. Spätere Provider wie MariaDB, Microsoft SQL Server, SQLite oder andere relationale Datenbanken sind architektonisch möglich, aber nicht zugesichert. Sie sind nur kompatibel, wenn sie die für das jeweilige RALF-Profil erforderlichen Fähigkeiten nachweislich erfüllen.

## Providerprinzip und Abstraktionsgrenze

RALF abstrahiert Datenbankprodukte nicht um jeden Preis auf den kleinsten gemeinsamen Nenner. Der Vertrag ist fähigkeitsorientiert:

- Ein Provider deklariert die Fähigkeiten, die er tatsächlich und sicher bereitstellt.
- RALF-Komponenten beziehungsweise Betriebsprofile deklarieren erforderliche und optionale Fähigkeiten.
- Fehlt eine erforderliche Fähigkeit, wird die Kombination verständlich als inkompatibel oder eingeschränkt bewertet.
- Zusätzliche Providerfähigkeiten werden nicht automatisch Bestandteil des allgemeinen Vertrags.
- Providerdetails dürfen intern für Betrieb und Diagnose genutzt werden, aber nicht in den öffentlichen Vertrag durchsickern.

### Entscheidung zur Datenzugriffsgrenze

Der Database Service wird als **Betriebs- und Vertragsdienst** gestaltet. Er verwaltet Provider, Verbindungsfähigkeit, Fähigkeiten, Schema, Migrationen, Health, Readiness, Backup und Restore. Fachliche Datenoperationen gehören in domänenspezifische Repository- oder Datenschnittstellen der jeweils verantwortlichen RALF-Komponente.

Damit wird keine universelle RALF-Datenbanksprache geschaffen. Die im Vertrag genannten Datenoperationen sind vorläufige fachliche Begriffe zur Beschreibung notwendiger Transaktionseigenschaften, keine zentrale technische CRUD-API. Die genaue Kommunikation zwischen Domänen und Database Service bleibt offen.

Diese Grenze vermeidet eine künstliche Universal-API und hält fachliche Modelle bei ihren Eigentümern. Dafür müssen spätere Domänenverträge Providerneutralität und benötigte Fähigkeiten ausdrücklich berücksichtigen.

## Umfang von Database Service 0.1

Version 0.1 umfasst bewusst:

- genau einen aktiven Datenbankprovider,
- PostgreSQL als Referenzprovider,
- eine RALF-Datenbankinstanz,
- eine logische RALF-Datenbank,
- getrennte technische Rollen,
- transaktionale Datenoperationen,
- ein versioniertes Schema,
- kontrollierte Schemamigrationen,
- getrennte Health- und Readiness-Prüfungen,
- einen Backup- und Restore-Vertrag,
- providerneutrale Zustände und Fehler.

Nicht Bestandteil von 0.1 sind Vektorsuche und `pgvector`, Hochverfügbarkeit, Replikation, automatisches Failover, Sharding, Multi-Master, externe Mandanten, ein allgemeiner Datenbankdienst für fremde Anwendungen, Datenbank-Webadministration, automatische Performanceoptimierung, autonome Datenlöschung oder -reparatur sowie Cloud-Datenbankintegration.

## Fähigkeitsmodell

| Fähigkeit | Bedeutung | Einordnung für 0.1 |
| --- | --- | --- |
| `relational_storage` | Dauerhafte strukturierte Speicherung mit relationalen Beziehungen. | erforderlich |
| `transactions` | Atomare, konsistente Transaktionsgrenzen für zusammengehörige Operationen. | erforderlich |
| `schema_migrations` | Versionierte, geordnete und kontrolliert ausführbare Schemaänderungen. | erforderlich |
| `constraints` | Datenbankseitige Durchsetzung definierter Integritätsregeln. | erforderlich |
| `indexes` | Definierte Zugriffsstrukturen für vorhersehbare Abfragen. | erforderlich |
| `json_documents` | Speicherung und gezielte Abfrage strukturierter JSON-Dokumente. | optional nutzbar |
| `full_text_search` | Datenbankgestützte Volltextsuche. | optional nutzbar |
| `advisory_locks` | Kooperative, anwendungsdefinierte Sperren für koordinierte Abläufe. | optional nutzbar |
| `vector_search` | Ähnlichkeitssuche über Vektorrepräsentationen. | später |
| `backup` | Kontrollierte Erzeugung einer sicherungsfähigen Datenrepräsentation. | erforderlich |
| `restore` | Kontrollierte Wiederherstellung aus einer geprüften Sicherung. | erforderlich |
| `point_in_time_recovery` | Wiederherstellung auf einen bestimmten Zeitpunkt. | später |
| `replication` | Bereitstellung replizierter Datenbankkopien. | später |
| `high_availability` | Betrieb mit definierten Verfügbarkeits- und Ausfallzielen. | später |

Die Einordnung ist der Architekturvorschlag für Vertrag 0.1. Ob `json_documents` oder `full_text_search` bereits verpflichtend werden, hängt von den zuerst festgelegten fachlichen Daten und Datenbankkunden ab.

## Verantwortlichkeiten

### Persistenz

- strukturierte RALF-Daten dauerhaft speichern,
- konsistente Lese- und Schreibvorgänge ermöglichen,
- Transaktionsgrenzen unterstützen,
- relationale Integrität ermöglichen.

### Schema

- aktuelle und angestrebte Schemaversion kennen,
- Migrationen geordnet, versioniert und nachvollziehbar behandeln,
- inkompatible oder unbekannte Schemaversionen erkennen,
- Downgrades und Migrationserfolge nicht vortäuschen.

### Fähigkeiten

- unterstützte Fähigkeiten melden,
- fehlende erforderliche Fähigkeiten als Inkompatibilität ausweisen,
- Provider und Providerversion intern kennen,
- keine providerspezifischen Details zum allgemeinen Vertrag erklären.

### Betrieb

- Health und Readiness getrennt bewerten,
- Start-, Stopp-, Wartungs-, Migrations-, Backup- und Restore-Zustände melden,
- Verbindungs-, Speicher- und Providerprobleme neutral klassifizieren,
- kontrollierte Sicherungs- und Wiederherstellungsvorgänge ermöglichen.

### Sicherheit

- technische Rollen und ihre Aufgaben trennen,
- normale Anwendungen nie mit administrativer Superuserrolle betreiben,
- minimale Rechte verwenden,
- Geheimnisse vom Repository und von nicht geheimer Konfiguration fernhalten,
- Verbindungen und Identitäten als deployment-spezifische Konfiguration behandeln.

### Auditierbarkeit

- Migrationen sowie Backup- und Restorevorgänge nachvollziehbar machen,
- Statusänderungen und Fehlerursachen verständlich klassifizieren,
- keine Geheimnisse oder vollständigen Zugangsdaten protokollieren.

## Nicht-Verantwortlichkeiten

Der Database Service ist kein Datei- oder Objekt-Storage, Cache, Message Queue, Event Bus, Suchdienst, allgemeiner Vektorspeicher oder Secrets-Dienst. Er verantwortet weder Modellinferenz und Modellverwaltung noch Benutzeroberfläche, Reverse Proxy, Netzwerk-, Container-, Proxmox- oder OPNsense-Verwaltung. Er ist außerdem kein allgemeiner Datenbankverwaltungsdienst für Anwendungen außerhalb von RALF.

## Fachliches Rollenmodell

| Rolle | Sicherheitsziel |
| --- | --- |
| `database_owner` | Besitzt die logische Datenbank beziehungsweise zentrale Objekte und wird nie für normale RALF-Anwendungszugriffe verwendet. |
| `migration_role` | Darf ausschließlich während eines freigegebenen Migrationsvorgangs kontrollierte Schemaänderungen ausführen. |
| `application_role` | Besitzt nur die für den normalen fachlichen Betrieb erforderlichen Lese- und Schreibrechte und keine administrativen Rechte. |
| `backup_role` | Besitzt nur die für geplante Sicherung und Wiederherstellung notwendigen Rechte. |
| `monitoring_role` | Darf ausschließlich die für Status, Health, Readiness und Diagnose erforderlichen Informationen lesen. |

Ein Provider darf diese Rollen technisch anders abbilden, muss aber dieselbe Trennung und dieselben Sicherheitsziele nachweisbar erfüllen.

## Konfigurationsvertrag

Die spätere nicht geheime Konfiguration wird in folgende Kategorien gegliedert:

- **Provider:** `provider_id`, `provider_version`
- **Verbindung:** `host`, `port`, `database_name`, `connection_security`, `connection_timeout`
- **Rollenreferenzen:** `application_identity`, `migration_identity`, `backup_identity`, `monitoring_identity`
- **Betrieb:** `health_timeout`, `migration_policy`, `backup_policy`, `retention_policy`
- **Fähigkeiten:** `required_capabilities`, `optional_capabilities`

Diese Namen definieren Kategorien, noch kein Dateiformat und keine öffentliche Programmierschnittstelle. Kennwörter, private Schlüssel, API-Tokens, vollständige Connection Strings mit Zugangsdaten, Cloud-Credentials und Backup-Verschlüsselungsschlüssel gehören niemals in normale Konfigurationsdateien. Ein eigener Secrets-Vertrag wird später benötigt und ist nicht Teil dieser Spezifikation.

## Lebenszyklus

Der providerneutrale Lebenszyklus unterscheidet `unknown`, `unconfigured`, `configured`, `starting`, `ready`, `degraded`, `maintenance`, `migration_required`, `migrating`, `backup_running`, `restore_running`, `failed` und `stopped`. Nur `ready` erlaubt reguläre Lese- und Schreibzugriffe. Eingeschränkte Zugriffe in `degraded` oder `backup_running` benötigen eine ausdrücklich belegte Providerzusage; Migration, Restore und Fehlerzustände sperren den normalen Datenzugriff.

Die genaue Bedeutung und die Zugriffsgrenzen jedes Zustands sind im [Vertrag 0.1](../contracts/database-service-v0.1.md#lebenszykluszustände) definiert. Administrative Aktionen bedeuten dort ausschließlich ausdrücklich geplante, autorisierte Lebenszyklusvorgänge; sie sind keine allgemeine Administrationsfreigabe.

## Sicherheitsgrenzen

- Andere RALF-Komponenten sehen keine PostgreSQL-spezifischen Zugangsdaten oder Werkzeuge.
- Normale Anwendungsidentitäten besitzen keine Owner-, Migrations- oder Backuprechte.
- Migration, Backup und Restore sind getrennte, geplante Vorgänge mit eigener Freigabe.
- Fehlerantworten enthalten keine Geheimnisse und keine providerspezifischen Interna als Vertragsbestandteil.
- Restore, Datenlöschung und Reparatur erfolgen niemals automatisch.

## PostgreSQL als Referenzprovider

Der PostgreSQL-Provider soll später Version und Verfügbarkeit erkennen, Verbindungen aufbauen, das Rollenmodell abbilden, die logische Datenbank anlegen und verwalten, providerspezifische Migrationen ausführen, Health und Readiness prüfen, logische Backups und Restore umsetzen, Fehler in RALF-Fehlerklassen übersetzen und seine Fähigkeiten deklarieren.

Noch nicht entschieden sind Referenzversion, Paketquelle, Betriebsform, Netzwerkfreigaben, Serverkonfiguration, Zugriffsregeln, Datenverzeichnis, Backupziel und Zugangsdaten. Diese Punkte gehören in spätere getrennte Entscheidungen.

## SQLite-Abgrenzung

SQLite kann später einen Minimal- oder Einzelprozessprovider bilden. Es ist nicht automatisch gleichwertig mit PostgreSQL und darf nur Fähigkeiten deklarieren, die es im gewählten Betriebsprofil sicher erfüllt. Eine möglicherweise eingebettete SQLite-Datenbank einer anderen RALF-Komponente wäre nicht automatisch der RALF Database Service.
