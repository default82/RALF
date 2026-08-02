# RALF Database Contract 0.1

## Status und Zweck

Dieses Dokument definiert die fachliche Vertragsoberfläche des Database Service in Version 0.1. Es legt weder REST, RPC, MCP, Python-Signaturen noch ein SQL- oder Dateiformat fest. PostgreSQL ist der erste Referenzprovider, bleibt jedoch außerhalb des öffentlichen Vertrags.

## Vertragsumfang 0.1

Der Vertrag gilt für genau einen aktiven Provider, eine RALF-Datenbankinstanz und eine logische RALF-Datenbank. Er beschreibt Fähigkeiten, Provider- und Schemazustand, kontrollierte Migrationen, Health, Readiness, Backup, Restore, Rollenanforderungen und providerneutrale Fehler.

Er definiert keine fachlichen Tabellen, Datenmodelle, Queries oder allgemeine Datenbankverwaltung für fremde Anwendungen.

## Fähigkeiten

### Erforderlich

- `relational_storage`
- `transactions`
- `schema_migrations`
- `constraints`
- `indexes`
- `backup`
- `restore`

Ohne eine dieser Fähigkeiten ist ein Provider für Database Service 0.1 nicht kompatibel.

### Optional nutzbar

- `json_documents`
- `full_text_search`
- `advisory_locks`

Eine RALF-Domäne darf eine optionale Fähigkeit für ihr eigenes Profil zur Voraussetzung machen. Dadurch wird sie nicht automatisch für alle Database-Service-Nutzer verpflichtend.

Der erste Kunde, die Conversation-Domäne in RALF Core, benötigt keine dieser optionalen Fähigkeiten.

### Später

- `vector_search`
- `point_in_time_recovery`
- `replication`
- `high_availability`

Diese Fähigkeiten sind ausdrücklich nicht Teil der Mindestzusage von 0.1.

## Fachliche Vertragsoperationen

Die folgenden Namen gliedern Verantwortungen. Sie sind Platzhalter und keine öffentlichen Funktionssignaturen.

### Status

- `get_service_status`
- `get_provider_information`
- `get_capabilities`
- `get_schema_status`

### Datenoperationen

- `begin_transaction`
- `commit_transaction`
- `rollback_transaction`
- `execute_read`
- `execute_write`

Diese Begriffe beschreiben die benötigten Transaktions- und Datenzugriffseigenschaften. Gemäß ADR‑0001 werden fachliche Lese- und Schreiboperationen später in domänenspezifischen Repository-Verträgen konkretisiert, nicht als universelle Database-Service-API.

### Schema

- `get_current_schema_version`
- `get_target_schema_version`
- `plan_migrations`
- `apply_migrations`

### Sicherung

- `plan_backup`
- `create_backup`
- `verify_backup`
- `plan_restore`
- `restore_backup`

### Diagnose

- `health_check`
- `readiness_check`
- `diagnose`

## Lebenszykluszustände

„Administrativ“ bedeutet eine ausdrücklich geplante und autorisierte Lebenszyklusaktion. Diagnose ist in jedem Zustand lesend zulässig, soweit der Provider erreichbar ist.

| Zustand | Bedeutung | Lesen | Schreiben | Administrative Aktionen |
| --- | --- | --- | --- | --- |
| `unknown` | Zustand wurde noch nicht zuverlässig ermittelt. | nein | nein | nur Diagnose und sichere Bestandsaufnahme |
| `unconfigured` | Provider oder logische Datenbank ist noch nicht vollständig konfiguriert. | nein | nein | Konfiguration darf geplant werden |
| `configured` | Konfiguration ist vorhanden, Betriebsbereitschaft aber noch nicht bestätigt. | nein | nein | Start und Prüfung dürfen geplant werden |
| `starting` | Provider startet oder stellt Verbindungen her. | nein | nein | Statusprüfung, kein paralleler Lebenszykluswechsel |
| `ready` | Alle Pflichtfähigkeiten, Schema- und Sicherheitsprüfungen sind erfüllt. | ja | ja | geplante Standardaktionen zulässig |
| `degraded` | Betrieb ist eingeschränkt; Umfang ist diagnostiziert. | nur wenn ausdrücklich als sicher bewertet | nur wenn ausdrücklich als sicher bewertet | Diagnose und freigegebene Korrekturplanung |
| `maintenance` | Geplanter Wartungsmodus. | standardmäßig nein | nein | ausschließlich freigegebene Wartungsaktionen |
| `migration_required` | Provider ist gesund, aber das Schema ist nicht zur Zielversion kompatibel. | höchstens ausdrücklich kompatible Reads | nein | Migrationsplanung zulässig |
| `migrating` | Eine freigegebene Migration läuft. | nein, sofern Migration nichts anderes garantiert | nein | nur der laufende Migrationsvorgang |
| `backup_running` | Eine Sicherung läuft. | ja, wenn der Provider konsistente Reads garantiert | nur wenn die Backupmethode Konsistenz garantiert | nur Backupüberwachung oder Abbruch nach eigener Regel |
| `restore_running` | Eine Wiederherstellung läuft. | nein | nein | nur der laufende Restorevorgang |
| `failed` | Ein kritischer Fehler verhindert sicheren Betrieb. | nein | nein | Diagnose und ausdrücklich geplante Wiederherstellung |
| `stopped` | Provider ist kontrolliert gestoppt. | nein | nein | Start, Diagnose oder Restoreplanung zulässig |

Zugriffe in `degraded` oder `backup_running` benötigen später eine konkrete, providerseitig belegte Zusage. Ohne diese Zusage gilt „nicht zulässig“.

## Health und Readiness

**Health** beantwortet, ob Provider beziehungsweise Datenbankprozess grundsätzlich funktionieren. Mögliche Kriterien sind Erreichbarkeit, Verbindungsaufbau und eine einfache interne Prüfung.

**Readiness** beantwortet, ob RALF die Datenbank aktuell sicher verwenden darf. Zusätzlich müssen mindestens gelten:

- alle erforderlichen Fähigkeiten sind vorhanden,
- die richtige logische Datenbank ist erreichbar,
- die Schemaversion ist bekannt und kompatibel,
- keine notwendige Migration und kein Restore steht im Weg,
- kein kritischer Speicherzustand liegt vor,
- die Anwendungsidentität besitzt genau die erforderlichen minimalen Rechte.

Health und Readiness sind unabhängig. Ein laufender, erreichbarer PostgreSQL-Provider kann gesund, aber wegen einer fehlenden RALF-Schemamigration nicht bereit sein.

## Schema- und Migrationsvertrag

- Migrationen sind versioniert und eindeutig geordnet.
- Der aktuelle Schemawert wird in der Datenbank selbst gespeichert.
- Jede Migration besitzt eine stabile ID.
- Vor jeder Migration wird ein nachvollziehbarer Plan angezeigt.
- Jede Migration benötigt eine eigene ausdrückliche Freigabe.
- Ein normaler Dienststart führt keine unbekannte oder stillschweigende Migration aus.
- Eine fehlgeschlagene Migration wird niemals als erfolgreich markiert.
- Rollbackfähigkeit wird für jede Migration einzeln dokumentiert; Rückwärtsausführung ist keine allgemeine Zusage.
- Struktur- und Datenmigrationen werden unterscheidbar dokumentiert.
- Unbekannte neuere oder inkompatible Schemaversionen führen zu `schema_mismatch` statt zu einem vorgetäuschten Downgrade.
- Providerspezifische Migrationsartefakte und SQL-Dateien gehören ausschließlich zum jeweiligen Provider.

Die technische Paketierung von Migrationen bleibt offen.

## Backupvertrag

Ein Backupdatensatz beschreibt mindestens:

| Feld | Bedeutung |
| --- | --- |
| `backup_id` | Stabile Identität der Sicherung. |
| `provider_id` | Provider, der die Sicherung erzeugt hat. |
| `created_at` | Nachvollziehbarer Erstellungszeitpunkt. |
| `schema_version` | Gesicherte RALF-Schemaversion. |
| `database_identity` | Nicht geheime Identität der gesicherten logischen Datenbank. |
| `backup_type` | Art der Sicherung. |
| `integrity_status` | Ergebnis der technischen Überprüfbarkeit. |
| `encryption_status` | Deklarierter Verschlüsselungszustand ohne Schlüsselmaterial. |
| `storage_reference` | Deployment-spezifischer Verweis auf den Speicherort. |

Zulässige fachliche Typen sind zunächst `logical`, `physical` und `snapshot`. Für 0.1 wird `logical` bevorzugt; die konkrete Umsetzung ist noch nicht entschieden.

Eine Sicherung ist erst erfolgreich, wenn ihre Erzeugung technisch abgeschlossen und ihre Überprüfbarkeit bestätigt ist. Eine vorhandene Datei allein gilt nicht als verifiziertes Backup. Der Vertrag enthält keine Kennwörter oder Schlüssel. Speicherort, Aufbewahrung und Verschlüsselung bleiben deployment-spezifisch. Automatische Löschung alter Sicherungen gehört nicht zu 0.1.

## Restorevertrag

Jeder Restore ist ein eigener geplanter Vorgang und benötigt mindestens:

1. Auswahl eines verifizierten Backups,
2. sichtbare Angabe von Quelle und Ziel,
3. Prüfung von Schemaversion und Zielzustand,
4. ausdrückliche Bestätigung,
5. kontrollierte einmalige Ausführung,
6. anschließende Integritäts-, Health- und Readiness-Prüfung.

Es gibt keinen automatischen Restore und kein stillschweigendes Überschreiben einer produktiven Datenbank.

## Providerneutrale Fehlerklassen

| Kategorie | Bedeutung |
| --- | --- |
| `configuration_error` | Nicht geheime Konfiguration ist ungültig oder unvollständig. |
| `connection_error` | Verbindung konnte nicht hergestellt oder gehalten werden. |
| `authentication_error` | Identität konnte nicht erfolgreich nachgewiesen werden. |
| `authorization_error` | Identität besitzt nicht die erforderlichen minimalen Rechte. |
| `capability_missing` | Eine erforderliche Fähigkeit fehlt. |
| `schema_mismatch` | Datenbankschema ist unbekannt oder inkompatibel. |
| `migration_required` | Eine bekannte Migration ist vor sicherem Betrieb erforderlich. |
| `migration_failed` | Eine freigegebene Migration ist fehlgeschlagen. |
| `transaction_failed` | Eine Transaktion konnte nicht erfolgreich abgeschlossen werden. |
| `constraint_violation` | Eine deklarierte Integritätsbedingung wurde verletzt. |
| `storage_exhausted` | Verfügbarer Speicher reicht für den sicheren Vorgang nicht aus. |
| `backup_failed` | Sicherung oder deren Verifikation ist fehlgeschlagen. |
| `restore_failed` | Wiederherstellung oder Abschlussprüfung ist fehlgeschlagen. |
| `provider_unavailable` | Provider ist nicht verfügbar. |
| `provider_conflict` | Providerzustand widerspricht dem ausgewählten Vertrag. |
| `unknown_error` | Fehler konnte keiner stabilen Kategorie zugeordnet werden. |

Jeder spätere Fehlerdatensatz enthält mindestens `error_code`, `category`, `message`, `retryable`, `provider_reference` und `operation_reference`. Providerspezifische Fehlercodes dürfen intern für Diagnose und Audit erhalten bleiben, werden aber nicht Teil des allgemeinen RALF-Fehlervertrags.

## Sicherheits- und Auditvertrag

- Die fachlichen Rollen `database_owner`, `migration_role`, `application_role`, `backup_role` und `monitoring_role` bleiben getrennt.
- Die Anwendung arbeitet nie mit einer administrativen Superuseridentität.
- Geheimnisse stehen weder im Repository noch in normaler Konfiguration, Statusantworten oder Logs.
- Migrationen, Backups und Restores sind mit Plan, Operation, Ergebnis und nicht geheimen Referenzen nachvollziehbar.
- Providerdiagnosen werden redigiert, bevor sie eine öffentliche Vertragsgrenze überschreiten.

## Erster Datenbankkunde

[ADR-0002](../decisions/ADR-0002-first-database-customer.md) entscheidet RALF Core als ersten Kunden und Conversation als erste persistente Domäne. Der [ConversationRepository Contract 0.1](conversation-repository-v0.1.md) konkretisiert fachliche Lese- und Schreibvorgänge domänenspezifisch, ohne sie in eine allgemeine Database-Service-API zu überführen.

Conversation verlangt `relational_storage`, `transactions`, `schema_migrations`, `constraints` und `indexes`. Backup und Restore verbleiben im Database Service. Schemaeigentum und fachliche Bedeutung bleiben bei RALF Core; der Database Service verantwortet die kontrollierte Ausführung freigegebener Migrationen, nicht das Conversation-Modell.

## Offene Vertragsfragen

Die frühere Frage nach dem ersten Datenbankkunden und dessen Repository-Grenze ist durch ADR-0002 entschieden. Offen bleiben:

1. **Unmittelbar nächste Entscheidung:** Welche minimale Verantwortung besitzt RALF Core zwischen Benutzereingabe, `ConversationRepository` und einer späteren Modellruntime?
2. Welche PostgreSQL-Version wird als Referenzversion gewählt?
3. Wie wird ein domänenspezifischer Repository-Vertrag technisch angebunden, ohne eine universelle Datenzugriffs-API zu schaffen?
4. Wie werden Secrets sicher und deployment-spezifisch bereitgestellt?
5. Wo liegen Daten und Backups in den ersten unterstützten Betriebsprofilen?
6. Welche Backup-Retention wird später verlangt?
7. Wie werden Migrationen technisch paketiert und ihrem Provider eindeutig zugeordnet?

Keine dieser Fragen autorisiert bereits eine Implementierung oder Installation.
