# ConversationRepository Contract 0.1

## Status und Zweck

Dieser Vertrag beschreibt die fachliche Persistenzgrenze der Conversation-Domäne in RALF Core. `ConversationRepository` ist ein Domänenvertrag und noch keine Klasse, Bibliothek, REST-, RPC-, MCP-, Python- oder SQL-Schnittstelle.

Er schützt das fachliche Modell vor Providerdetails und verhindert generische Tabellen- oder CRUD-Zugriffe. Der Database Service bleibt für Providerbetrieb, Fähigkeiten, Schemaausführung, Health, Backup und Restore verantwortlich.

Der Vertrag gilt ausschließlich für die RALF-Core-Allocation. Gitea, OpenBao und andere externe Database Consumer verwenden ihre eigenen nativen Datenbank- beziehungsweise Storage-Zugriffe und niemals ConversationRepository.

## Verantwortung

Das Repository ermöglicht ausschließlich das konsistente Speichern und Wiederherstellen von `Conversation` und `Message` gemäß den [Domänenregeln](../domains/conversation.md). Es erzwingt beziehungsweise bewahrt fachlich relevante Invarianten, Reihenfolge, Statusübergänge, Transaktionsgrenzen und Löschzusammenhang.

Es besitzt weder den Database Service noch den PostgreSQL-Provider. Eine spätere Implementierung darf Providerdetails nur hinter einem Infrastrukturadapter verwenden.

## Fachliche Operationen

Die Namen gliedern den Vertrag, sind aber keine Funktionssignaturen und legen keine Parameter fest.

### Unterhaltungen

- `create_conversation`
- `get_conversation`
- `list_conversations`
- `archive_conversation`
- `delete_conversation`

### Nachrichten lesen

- `list_messages`
- `get_message`

### Benutzernachrichten

- `append_user_message`

### Assistentenantworten

- `begin_assistant_message`
- `append_assistant_content`
- `complete_assistant_message`
- `fail_assistant_message`
- `cancel_assistant_message`

## Eingangs- und Ergebnisbegriffe

Spätere technische Signaturen können folgende fachliche Informationen benötigen, ohne dass Form, Typ oder Transport bereits festgelegt werden:

- eine stabile Conversation- oder Message-Referenz,
- den erwarteten Conversation-Revisionsstand,
- eine nicht bedeutungstragende fachliche Operationsreferenz zur möglichen Wiederholungserkennung,
- Rolle, Inhaltstyp und Textinhalt einer neuen Nachricht,
- einen kontrollierten zusätzlichen Textteil für eine laufende Assistentenantwort,
- eine redigierte providerneutrale Fehlerzusammenfassung,
- Listenfilter für aktive oder archivierte Unterhaltungen,
- eine noch festzulegende Begrenzung und Fortsetzung für Listen.

Ergebnisse beschreiben fachliche Snapshots von Conversation oder Message, geordnete Listen, den neuen Revisionsstand oder einen providerneutralen Fehler. Sie geben keine Datenbankzeilen, SQL-Ergebnisse, Connection-Objekte oder PostgreSQL-Fehler aus.

## Verbindliche Semantik

- Erzeugen, Statuswechsel und Löschung respektieren die Invarianten der Domäne.
- Listen von Nachrichten sind fachlich nach `sequence` geordnet.
- `append_user_message` speichert eine Benutzernachricht vollständig als `completed`.
- `begin_assistant_message` erzeugt höchstens eine aktive Antwort pro Unterhaltung.
- Nur `in_progress` darf durch `append_assistant_content` erweitert werden.
- `complete_assistant_message`, `fail_assistant_message` und `cancel_assistant_message` erzeugen einen fachlich unveränderlichen Endzustand.
- Eine archivierte Unterhaltung lehnt neue Nachrichten ab.
- `delete_conversation` behandelt Unterhaltung und Nachrichten als eine fachliche Einheit.
- Eine teilweise persistierte Operation wird nie als erfolgreich gemeldet.

## Providerneutrale Fehlerkategorien

| Kategorie | Bedeutung |
| --- | --- |
| `conversation_not_found` | Die referenzierte Unterhaltung existiert nicht. |
| `conversation_archived` | Die gewünschte Schreiboperation ist für eine archivierte Unterhaltung nicht zulässig. |
| `message_not_found` | Die referenzierte Nachricht existiert nicht in der erwarteten Unterhaltung. |
| `invalid_message_state` | Der verlangte Übergang passt nicht zum aktuellen Nachrichtenstatus. |
| `active_response_exists` | Es existiert bereits eine Assistentenantwort `in_progress`. |
| `revision_conflict` | Der erwartete Conversation-Revisionsstand stimmt nicht mit dem aktuellen Stand überein. |
| `duplicate_operation` | Eine fachlich identische oder bereits abgeschlossene Operation wurde als Wiederholung erkannt. |
| `content_invalid` | Inhalt, Rolle oder Inhaltstyp verletzt den Conversation-Vertrag. |
| `persistence_unavailable` | Conversation-Persistenz ist aktuell nicht bereit. |
| `transaction_failed` | Die fachliche Operation konnte nicht atomar abgeschlossen werden. |
| `unknown_error` | Der Fehler konnte keiner stabilen Kategorie zugeordnet werden. |

Die konkrete Fehlerstruktur und die Abbildung auf Database-Service-Fehler bleiben offen. Rohfehler, Stacktraces, SQL, Zugangsdaten und vollständige Providerantworten überschreiten die Repository-Grenze nicht.

## Parallelität und Idempotenz

Der Vertrag verlangt keine doppelte Sequenz, keine stillschweigende doppelte Nachricht und keine zwei parallelen aktiven Assistentenantworten. Die konkrete Erkennung über erwartete Revision, Operation-ID, Idempotency-Key oder eine Kombination bleibt eine offene Entscheidung.

Eine Wiederholung eines bereits erfolgreichen Abschlusses darf nicht unbemerkt einen zweiten fachlichen Effekt erzeugen. Ebenso darf ein Netzwerkfehler nicht automatisch als Begründung für eine doppelte Benutzernachricht dienen.

## Benötigte Database-Service-Fähigkeiten

Conversation 0.1 verlangt:

- `relational_storage`
- `transactions`
- `schema_migrations`
- `constraints`
- `indexes`

Nicht erforderlich sind `json_documents`, `full_text_search`, `advisory_locks`, `vector_search`, `point_in_time_recovery`, `replication` und `high_availability`.

`backup` und `restore` bleiben erforderliche Fähigkeiten des Database Service, sind aber keine Operationen des ConversationRepository.

## Rollen- und Schemavertrag

Normale Repository-Operationen verwenden ausschließlich die allocation-eigene `application_identity` mit minimalen Conversation-Lese- und Schreibrechten. Der Vertrag bietet keine Rollenverwaltung und keine Schemaänderung. Migrationspakete gehören fachlich zur Conversation-Domäne, werden aber nur über den Database Service und `migration_identity` geplant und ausgeführt.

Der konkrete PostgreSQL-Adapter, Objektbezeichnungen, Datentypen, Constraints und Indizes werden in diesem Vertrag nicht festgelegt.

## Ausgeschlossene Funktionen

Das Repository bietet kein generisches SQL, keine frei formulierbaren Abfragen, keine beliebigen Tabellenzugriffe, kein CRUD für andere Domänen und keine Provider- oder Datenbankbenutzerverwaltung. Es führt weder Backup, Restore, Modellinferenz, Promptaufbau, Streaming, semantische Suche noch Tool-Ausführung aus.

## Offene Vertragsfragen

- Welche Informationen sind für das Starten einer Conversation minimal erforderlich?
- Welche Parallelitäts- und Idempotenzbegriffe werden verbindlich?
- Wie werden Listen begrenzt und stabil fortgesetzt?
- Wie werden „erneut senden“, Korrektur oder Supersede fachlich modelliert?
- Welche maximale Textgröße gilt?
- Wie wird ein späterer Infrastrukturadapter an RALF Core gebunden?

Keine dieser Fragen legt bereits eine technische API oder Implementierung fest.
