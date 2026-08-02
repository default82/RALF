# RALF Database Contract 0.1

## Status und Zweck

Dieser Vertrag beschreibt die providerneutrale Verwaltungsebene der gemeinsam nutzbaren Database-Service-Plattform. Er legt weder REST, RPC, MCP, Python-Signaturen, SQL noch ein Konfigurationsformat fest.

PostgreSQL ist der erste Referenzprovider, bleibt aber außerhalb des öffentlichen Vertrags. Der detaillierte Vertrag einer isolierten Zuweisung steht im [Database Allocation Contract 0.1](database-allocation-v0.1.md).

## Vertragsumfang 0.1

Version 0.1 beschreibt einen oder mehrere Datenbankprovider, mindestens eine Providerinstanz und mehrere voneinander isolierbare Database Allocations für RALF-native, externe und spätere plattforminterne Consumer. Pro Allocation ist genau ein Provider aktiv. Eine Installation muss nicht sofort mehrere Allocations oder Providerinstanzen anlegen.

Der Vertrag umfasst:

- Providerinstanzen und ihre Fähigkeiten,
- Consumer-Profile und Database Allocations,
- Isolation und technische Identitäten,
- nicht geheime Secret-Referenzen,
- Provider- und Allocation-Lebenszyklus,
- Health und Readiness,
- Schema-Lebenszyklus und Kompatibilität,
- allocation-bezogene Backups und Restores,
- providerneutrale Fehler und Freigabegrenzen.

Er setzt weder genau einen Consumer noch genau eine logische Datenbank voraus.

## Verwaltungs- und Datenebene

Der Vertrag steuert ausschließlich die Verwaltungsebene. Er beschreibt Zustände, Pläne und kontrollierte Lebenszyklusaktionen für Providerinstanzen und Allocations.

Die Datenebene verwendet das native Protokoll des Providers. Der Database Service ist kein SQL-Proxy, übersetzt keine Anwendungsabfragen und bietet keine universellen Lese-, Schreib- oder CRUD-Operationen.

RALF-native Consumer konkretisieren fachliche Datenzugriffe durch eigene Repository-Verträge. Externe Anwendungen verwenden ihre eigenen Treiber und Schemata. Kein externer Consumer wird zur Verwendung eines RALF-Domänenvertrags verpflichtet.

## Consumer und Profile

Ein Database Consumer benötigt genau eine oder mehrere ausdrücklich geplante Allocations. Zulässige Consumer-Arten sind:

- `ralf_native`
- `external_application`
- `platform_internal`

Ein Consumer-Profil beschreibt unterstützte Provider, benötigte und optionale Fähigkeiten, Schema-Lebenszyklus, Identitätsmodell, Backup- und Health-Erwartungen sowie bekannte Einschränkungen. Es ist keine laufende Allocation und erzeugt keine Datenbank.

RALF Core ist der erste spezifizierte `ralf_native` Consumer. Gitea und OpenBao sind mögliche `external_application` Consumer; ihre tatsächliche Auswahl bleibt offen.

## Providerfähigkeiten

### Grundlegender Katalog

| Fähigkeit | Einordnung für das Database-Service-Profil 0.1 |
| --- | --- |
| `relational_storage` | erforderlich |
| `transactions` | erforderlich |
| `schema_migrations` | erforderlich, wenn eine Allocation Migrationen verlangt |
| `constraints` | erforderlich |
| `indexes` | erforderlich |
| `backup` | erforderlich |
| `restore` | erforderlich |
| `json_documents` | optional |
| `full_text_search` | optional |
| `advisory_locks` | optional |
| `vector_search` | später |
| `point_in_time_recovery` | später |
| `replication` | später |
| `high_availability` | später |

Jede Allocation erklärt ihre tatsächlich erforderlichen Fähigkeiten. Ein Provider kann grundsätzlich verfügbar sein und dennoch für eine konkrete Allocation inkompatibel bleiben.

## Fachliche Vertragsgruppen

Die folgenden Gruppen beschreiben Verantwortungen, keine technischen Methoden oder Signaturen.

### Providerverwaltung

- Provideridentität und Version erfassen,
- Providerfähigkeiten bewerten,
- Providerinstanz planen und ihren Lebenszyklus kontrollieren,
- Provider-Health und -Readiness melden.

### Allocation-Verwaltung

- Consumer und Profil referenzieren,
- Isolation und Providerzuordnung planen,
- Identitäts- und Secret-Referenzen prüfen,
- Allocation-Lebenszyklus und Kompatibilität melden,
- Schema-, Backup- und Restorevertrag zuordnen.

### Schema und Migration

- Schema-Lebenszyklusmodus kennen,
- aktuelle und erwartete Version beziehungsweise den anwendungseigenen Zustand bewerten,
- freizugebende Migrationen planen,
- ausschließlich dafür autorisierte Migrationen ausführen,
- keine unbekannte oder stille Migration beim Dienststart vortäuschen.

### Sicherung und Wiederherstellung

- allocation-bezogene Backups planen, erzeugen und verifizieren,
- einen Restore separat planen und bestätigen lassen,
- Quelle, Ziel und betroffene Allocation eindeutig benennen,
- andere Allocations vor unbeabsichtigten Auswirkungen schützen.

## Isolation und Identitäten

Referenzstandard ist `logical_database`: eine logische Datenbank, eigene Identitäten und keine Rechte auf andere Allocations pro Consumer. Weitere Klassen sind `dedicated_provider_instance` und `external_provider`.

Identitätsreferenzen sind allocation-bezogen:

- `allocation_owner`
- `migration_identity`
- `application_identity`
- `backup_identity`
- `monitoring_identity`

Eine gemeinsame Anwendungsidentität, ein gemeinsames Kennwort oder ein gemeinsames Anwendungsschema für mehrere Consumer ist unzulässig. Consumer verwenden keine Provider-Superuseridentität.

Consumer-Profile dürfen begründete Abweichungen deklarieren, etwa eine nicht trennbare Migrationsidentität bei `application_managed`. Die Abweichung muss sichtbar und hinsichtlich ihrer zeitweise erweiterten Rechte bewertet sein.

## Schema-Lebenszyklus

Jede Allocation besitzt genau einen Modus:

- `domain_managed`
- `application_managed`
- `platform_preprovisioned`

Bei `domain_managed` liefert eine RALF-Domäne versionierte Migrationspakete; der Database Service plant und führt sie nach eigener Freigabe aus. Bei `application_managed` besitzt die externe Anwendung Schema und Migrationen. Bei `platform_preprovisioned` legt die Plattform ausdrücklich vertraglich verlangte Objekte vor Anwendungsstart an.

Der Database Service beansprucht nicht die fachliche Eigentümerschaft externer Anwendungsschemata.

## Secrets-Vertrag

Alle geheimen Datenbankwerte liegen ausschließlich unter der absoluten externen Wurzel `/secrets`. Normale Konfiguration enthält nur nicht geheime `secret_references`, deren Ziel innerhalb `/secrets/database-service/` liegt.

Der Vertrag speichert keine Kennwörter, privaten Schlüssel, Tokens oder vollständigen Connection Strings. Das Repository behält zusätzlich `secrets/` als ausgeschlossenen lokalen Pfad.

Secret-Referenzen werden später auf absoluten Pfad, Verbleib innerhalb der Wurzel, fehlende Traversierung, unerwartete Symlinks und restriktive Rechte geprüft. Erzeugung und Rotation sind eigene freizugebende Vorgänge; diese Spezifikation schreibt oder liest keine Secretdatei.

OpenBao kann später Secrets-Provider werden, ersetzt `/secrets` aber nicht automatisch. Insbesondere dürfen OpenBao-Bootstrap-Geheimnisse bei einer eigenen PostgreSQL-Allocation nicht zirkulär aus OpenBao bezogen werden.

## Lebenszykluszustände

Providerinstanzen und Allocations verwenden getrennte Zustandsmeldungen. Der gemeinsame Katalog lautet:

- `unknown`
- `unconfigured`
- `configured`
- `starting`
- `ready`
- `degraded`
- `maintenance`
- `migration_required`
- `migrating`
- `backup_running`
- `restore_running`
- `failed`
- `stopped`

Nicht jeder Zustand ist auf beide Ebenen gleich anwendbar. `migration_required` bezieht sich beispielsweise auf eine Allocation, während ein Provider gleichzeitig `ready` sein kann. Zugriff ist nur erlaubt, wenn die konkrete Allocation dafür bereit ist; ein Fehler einer Allocation macht andere Allocations nicht automatisch fehlerhaft.

## Health und Readiness

Eine Providerinstanz meldet getrennt `provider_health` und `provider_readiness`. Jede Allocation meldet unabhängig `allocation_health` und `allocation_readiness`.

Provider-Health beantwortet, ob der Provider grundsätzlich funktioniert. Provider-Readiness berücksichtigt zusätzlich den für neue oder bestehende Allocations nutzbaren Betriebszustand.

Allocation-Readiness verlangt mindestens:

- Providerinstanz ist bereit,
- zugewiesene logische Datenbank beziehungsweise Ressource ist vorhanden,
- erforderliche Fähigkeiten sind erfüllt,
- Secret-Referenzen sind sicher auflösbar,
- technische Identitäten sind mit den minimal notwendigen Rechten verwendbar,
- Schema entspricht dem gewählten Lebenszyklusmodus,
- erforderlicher Backupvertrag ist vorhanden,
- kein Zugriff auf fremde Allocations ist möglich.

Ein Provider kann gesund sein, während eine einzelne Allocation wegen `migration_required`, fehlender Identität oder Konfigurationskonflikt nicht bereit ist.

## Backupvertrag

Ein allocation-bezogener Backupdatensatz beschreibt mindestens:

- `backup_id`
- `provider_instance_id`
- `allocation_id`
- `consumer_id`
- `created_at`
- `schema_version_or_state`
- `backup_type`
- `integrity_status`
- `encryption_status`
- `storage_reference`

Der Standard für 0.1 ist ein logisches Backup pro Allocation. Eine erzeugte Datei allein ist noch kein verifiziertes Backup. Speicherort, Aufbewahrung und Verschlüsselung bleiben deployment-spezifisch. Providerweite Sicherungen können später zusätzlich bestehen.

## Restorevertrag

Ein Restore benötigt eine geprüfte Sicherung, eindeutige Quell- und Ziel-Allocation, Schema- beziehungsweise Anwendungszustandsprüfung, sichtbare Auswirkungen, ausdrückliche Bestätigung, kontrollierte Ausführung sowie anschließende Integritäts- und Readiness-Prüfung.

Ein Allocation-Restore darf weder eine andere Allocation noch die gesamte Providerinstanz stillschweigend überschreiben. Es gibt keinen automatischen Restore.

## Providerneutrale Fehlerklassen

| Kategorie | Bedeutung |
| --- | --- |
| `configuration_error` | Nicht geheime Vertragsdaten sind ungültig oder unvollständig. |
| `provider_unavailable` | Providerinstanz ist nicht verfügbar. |
| `provider_conflict` | Providerzustand oder Fähigkeiten widersprechen dem Vertrag. |
| `allocation_unavailable` | Zugewiesene Datenbankressource ist nicht verfügbar. |
| `allocation_conflict` | Isolation, Identitäten oder Zuordnung widersprechen dem Allocation-Vertrag. |
| `connection_error` | Native Verbindung konnte nicht hergestellt oder gehalten werden. |
| `authentication_error` | Technische Identität konnte nicht nachgewiesen werden. |
| `authorization_error` | Identität besitzt falsche oder unzureichende Rechte. |
| `secret_reference_error` | Secret-Referenz ist ungültig oder nicht sicher auflösbar. |
| `capability_missing` | Eine für die Allocation erforderliche Fähigkeit fehlt. |
| `schema_mismatch` | Schema- oder Anwendungszustand ist unbekannt oder inkompatibel. |
| `migration_required` | Eine bekannte Migration ist vor Bereitschaft erforderlich. |
| `migration_failed` | Eine freigegebene Migration ist fehlgeschlagen. |
| `storage_exhausted` | Ressource reicht für sicheren Betrieb nicht aus. |
| `backup_failed` | Sicherung oder Verifikation ist fehlgeschlagen. |
| `restore_failed` | Wiederherstellung oder Abschlussprüfung ist fehlgeschlagen. |
| `unknown_error` | Fehler konnte keiner stabilen Kategorie zugeordnet werden. |

Providerspezifische Fehler dürfen intern für Diagnose erhalten bleiben, werden aber nicht allgemeiner Vertragsbestandteil.

## Freigabegrenzen

Anlage, Änderung, Migration, Backup, Restore, Identitätsänderung, Secret-Erzeugung oder -Rotation sowie Verschiebung einer Allocation auf eine andere Providerinstanz benötigen später jeweils einen sichtbaren Plan und eine eigene Freigabe. Eine Beschreibung in diesem Vertrag ist keine Ausführungsfreigabe.

## Erster RALF-nativer Consumer

[ADR-0002](../decisions/ADR-0002-first-database-customer.md) legt RALF Core als ersten spezifizierten RALF-nativen Consumer fest. Seine Conversation-Domäne verwendet ausschließlich in ihrer eigenen Allocation den [ConversationRepository Contract](conversation-repository-v0.1.md). Gitea, OpenBao und andere externe Anwendungen verwenden diesen Vertrag nicht.

[ADR-0003](../decisions/ADR-0003-shared-database-platform.md) präzisiert die gemeinsam nutzbare Plattform und die Mehrkundenstruktur.

## Offene Entscheidungen

1. Welche Allocations werden zuerst tatsächlich angelegt?
2. Welche Provider- und Allocation-Zustandsübergänge gehören in das Referenzprofil?
3. Welche Consumer benötigen dedizierte Providerinstanzen?
4. Wie werden externe anwendungseigene Migrationen sicher freigegeben oder beobachtet?
5. Wie erhalten Consumer Zugriff auf Secretdateien unter `/secrets`?
6. Welche Eigentümer-, Gruppen- und Rotationsregeln gelten dort?
7. Welche Backups sind allocation-bezogen und welche providerweit?
8. Wie werden Ressourcen- und Netzwerkgrenzen abgebildet?
9. Welche PostgreSQL-Version wird Referenzversion?

**Nächster kleiner Schritt:** PostgreSQL-Referenzprovider und Allocation-Lebenszyklus spezifizieren, ohne PostgreSQL zu installieren.
