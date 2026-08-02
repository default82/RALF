# Database Allocation Contract 0.1

## Status und Zweck

Dieser Vertrag beschreibt eine isolierte Zuweisung von Datenbankressourcen an genau einen Database Consumer. Er ist Teil der providerneutralen Verwaltungsebene des Database Service und definiert weder eine technische API noch SQL, Datenbankobjekte oder ein Konfigurationsformat.

Eine Allocation ist eine Vertrags- und Lebenszykluseinheit. Ein Consumer-Profil ist dagegen nur eine wiederverwendbare Anforderungsbeschreibung und keine laufende Allocation.

## Consumer

Jede Allocation referenziert genau einen `consumer_id` und genau einen Consumer-Typ:

- `ralf_native`
- `external_application`
- `platform_internal`

Ein Consumer kann später mehrere ausdrücklich geplante Allocations besitzen, etwa für getrennte Betriebszwecke. Eine einzelne Allocation wird jedoch nie mehreren Consumern gemeinsam zugeordnet.

## Vertragsbegriffe

Eine Allocation besitzt fachlich mindestens:

| Begriff | Bedeutung |
| --- | --- |
| `allocation_id` | Stabile, nicht geheime Identität der Zuweisung. |
| `consumer_id` | Eindeutiger Consumer der Allocation. |
| `provider_instance_id` | Zugeordnete Providerinstanz. |
| `database_name_reference` | Nicht geheime Referenz auf die zugewiesene Datenbankressource. |
| `isolation_class` | Gewählte Isolationsform. |
| `schema_lifecycle` | Eigentums- und Migrationsmodus des Schemas. |
| `required_capabilities` | Fähigkeiten, ohne die die Allocation nicht kompatibel ist. |
| `optional_capabilities` | Nutzbare, aber nicht zwingende Fähigkeiten. |
| `identity_references` | Nicht geheime Referenzen auf allocation-eigene technische Identitäten. |
| `secret_references` | Nicht geheime absolute Referenzen unter `/secrets`. |
| `backup_policy_reference` | Zugeordneter Backupvertrag. |
| `retention_policy_reference` | Zugeordnete Aufbewahrungsregel. |
| `status` | Providerneutraler Allocation-Zustand. |

Für spätere Platzierungsentscheidungen muss die Allocation zusätzlich Verfügbarkeits-, Isolations-, Ressourcen-, Backup- und Restore-Anforderungen ausdrücken können.

## Isolationsklassen

### `logical_database`

Der Consumer erhält eine eigene logische Datenbank innerhalb einer gemeinsam betriebenen Providerinstanz. Eigene Identitäten und fehlende Rechte auf andere Allocations bleiben Pflicht.

### `dedicated_provider_instance`

Der Consumer erhält aufgrund von Sicherheits-, Verfügbarkeits-, Ressourcen- oder Kompatibilitätsanforderungen eine eigene Providerinstanz.

### `external_provider`

Die Allocation referenziert eine bereits vorhandene externe Datenbankbereitstellung. Umfang, Verantwortung und erlaubte Verwaltung müssen ausdrücklich festgelegt werden.

Referenzstandard für PostgreSQL im Database-Service-Vertrag 0.1 ist `logical_database`; dies verhindert keine spätere dedizierte Platzierung.

## Isolationseigenschaften

Eine gültige Allocation gewährleistet:

- genau einen Consumer,
- genau einen aktiven Provider,
- eigene technische Identitäten,
- keine Zugriffsrechte auf Datenbanken anderer Consumer,
- kein gemeinsames Anwendungsschema mit anderen Allocations,
- keine gemeinsame Anwendungsidentität oder gemeinsames Kennwort,
- keine Provider-Superuseridentität für den Consumer,
- allocation-bezogene Health-, Readiness-, Backup- und Restorezustände.

Eine gemeinsam genutzte Providerinstanz ist eine sichtbare gemeinsame Fehlerdomäne, nicht der Beweis gemeinsamer Daten- oder Berechtigungsgrenzen.

## Schema-Lebenszyklus

Jede Allocation verwendet genau einen Modus.

### `domain_managed`

Eine RALF-Domäne besitzt fachlich Schema und versionierte Migrationen. Der Database Service plant, prüft Providerfähigkeiten und führt nur freigegebene Migrationspakete aus. RALF Core und Conversation verwenden diesen Modus.

### `application_managed`

Eine externe Anwendung besitzt Schema und Migrationen. Der Database Service übersetzt oder beansprucht diese nicht. Das Consumer-Profil muss offenlegen, ob Laufzeit- und Migrationsidentität trennbar sind, wann erweiterte Rechte benötigt werden und ob sie danach reduziert werden können.

### `platform_preprovisioned`

Die Plattform legt ausdrücklich vertraglich geforderte Datenbankobjekte kontrolliert vor dem Anwendungsstart an. Dieser Modus ist nur mit einem konkreten Consumer-Vertrag zulässig.

## Technische Identitäten

Mögliche allocation-bezogene Identitäten sind:

- `allocation_owner`
- `migration_identity`
- `application_identity`
- `backup_identity`
- `monitoring_identity`

Nicht jede Allocation benötigt jede getrennte Identität. Fehlende Trennbarkeit muss im Consumer-Profil ausdrücklich erklärt und sicherheitlich bewertet werden.

`allocation_owner` wird nicht im normalen Anwendungsbetrieb verwendet. `application_identity` erhält ausschließlich die für den Consumer erforderlichen Rechte. Backup- und Monitoringidentitäten dürfen zentral betrieben werden, bleiben aber auf den vereinbarten Umfang begrenzt.

## Secret-Referenzen

Secretwerte sind kein Bestandteil dieses Vertrags. Die kanonische externe Wurzel ist `/secrets`; allocation-bezogene Referenzen liegen unter:

```text
/secrets/database-service/allocations/<allocation-id>/
```

Mögliche spätere Dateinamen sind `owner-password`, `migration-password`, `application-password`, `backup-password` und `monitoring-password`. Nicht benötigte Dateien werden nicht erzeugt.

Eine Referenz muss absolut sein, innerhalb `/secrets` verbleiben, Traversierung und unerwartete Symlinks ausschließen sowie auf eine restriktiv lesbare Datei zeigen. Normale Konfiguration speichert nie den Secretwert oder eine vollständige Verbindungs-URL mit Zugangsdaten.

Erzeugung, erstmalige Bereitstellung und Rotation sind getrennte geplante Vorgänge. Vorhandene Geheimnisse werden nicht automatisch überschrieben.

## Fähigkeiten und Kompatibilität

Eine Allocation ist nur kompatibel, wenn ihre `required_capabilities` von der zugeordneten Providerinstanz erfüllt werden. Optionale Fähigkeiten dürfen fehlen, ohne die grundlegende Bereitschaft zu verhindern.

RALF Core Conversation verlangt `relational_storage`, `transactions`, `schema_migrations`, `constraints`, `indexes`, `backup` und `restore`. Externe Consumer erklären eigene Anforderungen; diese werden nicht aus dem Conversation-Profil abgeleitet.

## Zustände

Der normative [Database-Allocation-Lebenszyklus](../lifecycle/database-allocation.md) definiert die Zustände `requested`, `planned`, `provisioning`, `configured`, `migration_required`, `migrating`, `ready`, `degraded`, `backup_running`, `restore_planned`, `restore_running`, `suspended`, `deleting`, `deleted` und `failed` einschließlich erlaubter Zugriffe und administrativer Grenzen.

Eine Allocation darf nicht `ready` melden, nur weil ihre Providerinstanz gesund ist. Ein Dienststart erzeugt weder eine Allocation noch eine Migration oder einen anderen mutierenden Zustandsübergang.

## Fachliche Operationen und Allocation-Plan

Der Lebenszyklus beschreibt die fachlichen Operationen von Planung und Anlage über Verifikation, Migration, Suspendierung, Backup, Restore und Secret-Rotation bis zur geplanten Löschung. Diese Namen sind keine technischen Signaturen.

Jede Mutation benötigt einen Plan mit Ausgangs- und Zielzustand, Voraussetzungen, sichtbaren Mutationen, Risiken, ausdrücklicher Freigabe und Abschlussverifikation. Der Plan benennt Consumer, Profil, Providerinstanz, Version, Isolation, Datenbankreferenz, Schema-Lebenszyklus, Fähigkeiten, Identitäten, Secret-Referenzen, Netzwerkgrenze, Policies, Ressourcen, Validierung und Rollback-Grenzen. Er enthält keine Secretwerte oder ausführbaren freien Befehle.

## Health und Readiness

`allocation_health` beschreibt, ob die zugewiesene Ressource grundsätzlich funktioniert. `allocation_readiness` beschreibt, ob genau dieser Consumer sie sicher verwenden kann.

Readiness verlangt mindestens:

- Providerinstanz `ready`,
- zugewiesene Ressource vorhanden,
- Pflichtfähigkeiten erfüllt,
- Secret-Referenzen sicher auflösbar,
- benötigte Identitäten verwendbar,
- Schema-Lebenszyklus im erwarteten Zustand,
- erforderlicher Backupvertrag vorhanden,
- keine fremden Zugriffsrechte.

Eine nicht bereite Allocation beeinflusst andere Allocations nicht automatisch. Ein Providerfehler kann dagegen mehrere Allocations derselben Instanz betreffen und muss entsprechend sichtbar sein.

## Backup

Ein allocation-bezogenes Backup referenziert mindestens `provider_instance_id`, `allocation_id` und `consumer_id`. Standard für 0.1 ist ein logisches Backup der einzelnen Allocation.

Backup ist erst erfolgreich, wenn Erzeugung und technische Verifikation abgeschlossen sind. Aufbewahrung, Verschlüsselung und Speicherort werden durch referenzierte Policies festgelegt und nicht in Secretwerten oder Datenbankzugangsdaten eingebettet.

## Restore

Restore ist eine eigene geplante Operation mit geprüfter Quelle, eindeutiger Ziel-Allocation, sichtbarer Auswirkung, Schema- beziehungsweise Anwendungszustandsprüfung, ausdrücklicher Freigabe und anschließender Integritäts- und Readiness-Prüfung.

Ein Restore darf keine fremde Allocation oder die gesamte Providerinstanz stillschweigend überschreiben. Providerweite Wiederherstellung ist ein gesonderter Vertrag.

## Providerneutrale Fehlerklassen

- `allocation_not_found`
- `allocation_not_ready`
- `allocation_already_exists`
- `allocation_conflict`
- `consumer_conflict`
- `provider_not_ready`
- `provider_version_incompatible`
- `provider_unavailable`
- `provider_conflict`
- `capability_missing`
- `isolation_violation`
- `identity_conflict`
- `secret_reference_invalid`
- `secret_already_exists`
- `secret_unavailable`
- `schema_mismatch`
- `schema_lifecycle_conflict`
- `migration_required`
- `migration_failed`
- `backup_failed`
- `backup_not_verified`
- `restore_conflict`
- `restore_failed`
- `resource_exhausted`
- `unknown_error`

Fehler enthalten später eine nicht geheime Allocation-, Consumer-, Provider- und Operationsreferenz. Providerrohfehler und Secretwerte werden nicht Bestandteil des allgemeinen Vertrags.

## Freigaben und Änderungen

Folgende Änderungen benötigen später jeweils einen Plan mit sichtbaren Auswirkungen und eine ausdrückliche Freigabe:

- Allocation anlegen oder entfernen,
- Providerinstanz oder Isolationsklasse ändern,
- Fähigkeiten oder Ressourcenanforderungen ändern,
- Identitäten oder Secret-Referenzen ändern,
- Migration ausführen,
- Backup- oder Retention-Policy ändern,
- Restore durchführen,
- Secrets erzeugen oder rotieren.

Keine Bestätigung dieses Architekturvertrags ist bereits eine Applyfreigabe.

## Consumer-Beispiele

### RALF Core

`ralf_native`, `domain_managed`, eigene Allocation. Der ConversationRepository-Vertrag gilt ausschließlich hier.

### Gitea

Möglicher `external_application` Consumer mit eigenem Datenbankzugriff und `application_managed`. Gitea verwendet nicht ConversationRepository.

### OpenBao

Möglicher `external_application` Consumer. PostgreSQL bleibt optionale Storage-Wahl; Integrated Storage muss gleichwertig geprüft werden. OpenBao verwendet nicht ConversationRepository.

## Erstes Referenzdeployment

[ADR-0005](../decisions/ADR-0005-first-postgresql-deployment-profile.md) wählt für die Providerinstanz `postgresql-main` genau vier Allocations: `gitea`, `openbao`, `semaphore` und `nodered`. Alle sind `external_application`, verwenden `logical_database`, besitzen `application_managed` als Schema-Lebenszyklus und sind ausdrücklich ausgewählt.

Jede Allocation besitzt eine eigene logische Datenbank, eine eigene `application_identity` und eine eigene Referenz auf `application-password` unter `/secrets/database-service/allocations/<allocation-id>/`. Rechte auf fremde Allocations, gemeinsame Anwendungsrollen, gemeinsame Anwendungspasswörter und gemeinsam genutzte Anwendungsschemata sind ausgeschlossen. Health, Readiness, Backup und Restore bleiben allocation-bezogen.

OpenBao verwendet in diesem Deployment PostgreSQL als Storage; die Auswahl gilt nicht allgemein. Node-RED verwendet seine Allocation ausschließlich für relationale Flow-Anwendungsdaten, nicht automatisch für Flowdateien, Credentials, Context oder den internen Node-RED-Storage.

RALF Core erhält in diesem ersten realen Deployment keine Allocation. Seine spätere `domain_managed` Allocation setzt einen implementierten Core sowie ein konkretes Schema oder Migrationspaket voraus.

## Offene Punkte

- Platzierungsentscheidung gemeinsam oder dediziert,
- Rechte bei anwendungseigenen Migrationen,
- Zugriff der Consumer auf `/secrets`,
- Eigentümer-, Gruppen- und Rotationsmodell,
- Ressourcen- und Netzwerkgrenzen,
- allocation- und providerweite Backupbeziehung,
- konkrete Consumer-Versionskompatibilität.

**Nächster Schritt:** Der [read-only Deploymentplan](../operations/postgresql-main-deployment-plan.md) konkretisiert das erste Profil ohne Providerinstanz oder Allocation anzulegen. Danach wird ein getrennter Apply-Vertrag mit Recovery- und Freigabegrenzen spezifiziert.
