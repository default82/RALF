# Conversation-Domäne 0.1

## Zweck

Die Conversation-Domäne bewahrt den fachlichen Verlauf einer Unterhaltung zwischen einem Menschen und RALF. Sie ist die erste persistente Domäne von RALF Core und umfasst in Version 0.1 ausschließlich Unterhaltungen (`Conversation`) und Nachrichten (`Message`).

Sie verantwortet das Anlegen, die geordnete Nachrichtenablage, den Unterhaltungszustand, den Lebenszyklus einer Assistentenantwort, Archivierung, ausdrückliche Löschung und die konsistente Wiederherstellung eines Gesprächsverlaufs.

Die nachfolgenden Eigenschaftsnamen sind fachliche Begriffe. Sie legen weder Tabellen, SQL-Spalten, Datentypen noch eine Programmiersprache fest.

## Persistenter Umfang 0.1

Version 0.1 speichert ausschließlich `Conversation` und `Message`. Nicht stillschweigend ergänzt werden Benutzerkonten, Organisationen, Mandanten, Workspaces, Erinnerungen, Wissensobjekte, Embeddings, Tool-Aufrufe, Skill-Konfigurationen, Providerinventar, Modellkonfigurationen, Dateien, Anhänge, systemweite Auditdaten, Nutzungsabrechnung oder Telemetrie.

Weitere persistente Domänen benötigen einen konkreten fachlichen Bedarf und eine eigene Entscheidung.

## Fachliches Modell Conversation

| Eigenschaft | Fachliche Bedeutung |
| --- | --- |
| `conversation_id` | Stabile, eindeutige und für Nutzer nicht bedeutungstragende Identität. Eine fortlaufende öffentlich erratbare Nummer ist keine Vertragsvorgabe; das konkrete Format bleibt offen. |
| `title` | Optionaler menschenlesbarer Titel mit später festzulegender Maximallänge. Er darf manuell oder automatisch gesetzt werden und ersetzt keine technische Identität. |
| `status` | Fachlicher Zustand `active` oder `archived`. |
| `revision` | Monoton steigender fachlicher Revisionsstand, der bei Anlage einen vertraglich definierten Initialwert erhält, bei fachlichen Änderungen erhöht wird und später konkurrierende Änderungen erkennbar machen kann. Konkreter Zahlenwert und Technik bleiben offen. |
| `created_at` | Vom System vergebener Erstellungszeitpunkt in UTC mit Zeitzoneninformation. |
| `updated_at` | Vom System vergebener Zeitpunkt der letzten fachlichen Änderung in UTC mit Zeitzoneninformation. |

### Zustände

`active` erlaubt neue Nachrichten und erscheint standardmäßig in aktiven Übersichten.

`archived` bleibt lesbar, lehnt neue Nachrichten standardmäßig ab und kann später durch eine ausdrücklich entworfene Operation reaktiviert werden.

`deleted` ist kein normal gespeicherter Zustand. Löschung ist eine ausdrückliche fachliche Operation und kein dauerhaft sichtbares Pseudolöschen. Tombstones würden eine eigene rechtliche oder technische Begründung benötigen.

## Fachliches Modell Message

| Eigenschaft | Fachliche Bedeutung |
| --- | --- |
| `message_id` | Stabile eindeutige Identität einer Nachricht; das Format bleibt offen. |
| `conversation_id` | Unveränderliche Zuordnung zu genau einer Unterhaltung. |
| `sequence` | Innerhalb einer Unterhaltung eindeutige, monoton steigende Reihenfolge. |
| `role` | Gesprächsseite `user` oder `assistant`. |
| `status` | Lebenszykluszustand abhängig von der Rolle. |
| `content_type` | In 0.1 ausschließlich `text/plain`. |
| `content` | Unicode-Text ohne stille Kürzung oder inhaltlich unbemerkte Normalisierung. |
| `created_at` | Vom System vergebener Erstellungszeitpunkt in UTC mit Zeitzoneninformation. |
| `completed_at` | Abschlusszeitpunkt eines terminalen Nachrichtenzustands, sonst nicht gesetzt. |
| `error` | Optionale providerneutrale Fehlerdarstellung einer fehlgeschlagenen Assistentenantwort. |

Konkrete Datenbanktypen werden nicht festgelegt.

## Nachrichtenreihenfolge

Jede Nachricht erhält ihre Sequenz transaktional innerhalb ihrer Unterhaltung. Zwei Nachrichten derselben Unterhaltung dürfen nie dieselbe Sequenz besitzen. Nachrichten verschiedener Unterhaltungen verwenden unabhängige Sequenzen. Zeitstempel allein bestimmen die Reihenfolge nicht.

## Rollen und Inhalt

Version 0.1 unterstützt ausschließlich `user` und `assistant`. Die später denkbaren Rollen `system` und `tool` gehören nicht zum aktiven Vertrag. Interne Systemanweisungen, Prompts und Toolprotokolle werden nicht als normale Gesprächsnachrichten gespeichert.

Der einzige Inhaltstyp ist `text/plain`. Markdown ist kein verbindlicher Speichertyp; eine spätere Darstellung darf Text interpretieren. HTML, Bilder, Audio, Video, Binärdaten, Anhänge, strukturierte Tool-Aufrufe und Embeddings sind ausgeschlossen.

Eine erfolgreich abgeschlossene Nachricht enthält nicht leeren Unicode-Text. Eine feste maximale Textlänge wird später als Betriebsgrenze entschieden. Inhalte werden niemals still gekürzt, als HTML ausgeführt oder durch unbemerkte Normalisierung fachlich verändert.

Gesprächsinhalte können personenbezogene, vertrauliche oder sonst sensible Daten enthalten. Der Vertrag behauptet nicht, sie seien geheimnisfrei.

## Nachrichtenlebenszyklus

### Benutzernachricht

Eine Benutzernachricht wird atomar im Zustand `completed` gespeichert. Für sie sind `in_progress`, `failed` und `cancelled` unzulässig.

### Assistentenantwort

| Zustand | Bedeutung |
| --- | --- |
| `in_progress` | Antwort wurde begonnen und ihr Inhalt darf kontrolliert erweitert werden. Sie ist noch nicht endgültig. Pro Unterhaltung ist zunächst höchstens eine solche Antwort zulässig. |
| `completed` | Antwort ist abgeschlossen, ihr Inhalt ist nicht leer und `completed_at` ist gesetzt. |
| `failed` | Antwort konnte nicht abgeschlossen werden. Teilinhalt und eine redigierte providerneutrale Fehlerzusammenfassung dürfen erhalten bleiben. |
| `cancelled` | Antwort wurde bewusst abgebrochen. Teilinhalt darf erhalten bleiben; es folgt kein automatischer Generierungsversuch. |

Nachrichten in `completed`, `failed` oder `cancelled` sind terminal, besitzen `completed_at` und sind fachlich unveränderlich. Eine Korrektur erfordert eine neue Nachricht oder einen später ausdrücklich entworfenen Supersede-Vertrag. Unprotokollierte Bearbeitung abgeschlossener Nachrichten ist in 0.1 ausgeschlossen.

## Fehlerdarstellung

Eine fehlgeschlagene Assistentenantwort darf fachlich höchstens `error_code`, `error_category`, `error_summary` und `retryable` enthalten. Zulässige providerneutrale Kategorien sind zunächst:

- `model_unavailable`
- `generation_failed`
- `generation_cancelled`
- `timeout`
- `content_rejected`
- `storage_failed`
- `unknown`

Nicht gespeichert werden vollständige Stacktraces, API-Schlüssel, Authorization-Header, vollständige Providerantworten, interne Systemprompts, geheime Umgebungsvariablen oder private Modellproviderdaten. Konkrete Providerfehler sind nicht Teil dieses Vertrags.

## Fachliche Invarianten

- Jede Nachricht gehört genau einer Unterhaltung und kann diese Zuordnung nicht wechseln.
- `sequence` ist pro Unterhaltung eindeutig und monoton steigend.
- Benutzernachrichten werden atomar abgeschlossen gespeichert.
- Pro Unterhaltung ist höchstens eine Assistentenantwort `in_progress`.
- Eine archivierte Unterhaltung akzeptiert keine neue Nachricht.
- Eine terminale Nachricht wird nicht überschrieben.
- `completed_at` ist ausschließlich bei `completed`, `failed` oder `cancelled` gesetzt.
- Eine erfolgreich abgeschlossene Textnachricht besitzt nicht leeren Inhalt.
- Der Conversation-Revisionsstand erhöht sich bei fachlichen Änderungen.
- Unterhaltung und Nachrichten werden bei Löschung zusammenhängend behandelt.
- Teilweise gespeicherte fachliche Operationen gelten nicht als erfolgreich.

## Transaktionsgrenzen

### Unterhaltung anlegen

`create_conversation` hinterlässt entweder eine vollständige neue Unterhaltung oder keine Unterhaltung.

### Benutzernachricht anhängen

Folgende Schritte sind eine atomare fachliche Operation:

1. Unterhaltung auf `active` prüfen,
2. nächste Sequenz vergeben,
3. abgeschlossene Benutzernachricht speichern,
4. Conversation-Revision aktualisieren.

### Assistentenantwort beginnen

Folgende Schritte sind atomar:

1. Unterhaltung auf `active` prüfen,
2. sicherstellen, dass keine andere Antwort `in_progress` ist,
3. nächste Sequenz vergeben,
4. Assistentennachricht als `in_progress` anlegen,
5. Conversation-Revision aktualisieren.

### Assistentenantwort abschließen

Aktueller Status, finaler Inhalt, Statuswechsel, Abschlusszeitpunkt und Conversation-Revision werden zusammenhängend geprüft beziehungsweise aktualisiert. Dasselbe Prinzip gilt für `failed` und `cancelled`.

### Unterhaltung löschen

Unterhaltung und alle zugehörigen Nachrichten werden als eine fachliche Löschoperation behandelt. Sicherungskopien werden dadurch nicht automatisch außerhalb ihrer Aufbewahrungsregeln verändert.

## Parallelität und Wiederholungen

Verbindlich sind keine doppelte Sequenz, keine stillschweigende doppelte Speicherung und höchstens eine aktive Assistentenantwort je Unterhaltung. Noch offen bleibt, ob erwartete Revisionen, fachliche Operation-IDs oder Idempotency-Keys doppelte Requests und konkurrierende Änderungen erkennen.

Zu klären sind insbesondere doppelte Benutzernachrichten nach Netzwerkfehlern, parallele Antwortstarts und die Wiederholung eines bereits erfolgreichen Abschlusses. Eine konkrete Optimistic-Locking- oder Idempotenztechnik wird nicht vorweggenommen.

## Schemaeigentum und Rollen

Das fachliche Conversation-Schema gehört RALF Core beziehungsweise dieser Domäne. Andere Domänen ändern es nicht direkt. Spätere versionierte Migrationspakete stammen aus der Conversation-Domäne; der Database Service plant, validiert und führt freigegebene Migrationen aus. PostgreSQL-spezifische Artefakte bleiben in einem späteren Provideradapter. Core-Start allein löst keine Migration aus.

RALF Core verwendet im Normalbetrieb ausschließlich `application_role` für Conversation-Lese- und Schreibvorgänge sowie deren Transaktionen. Diese Rolle darf weder Schema und Rollen verändern noch Backups oder Datenbankadministration ausführen. Schemaänderungen verwenden ausschließlich `migration_role`; Backup und Monitoring bleiben `backup_role` und `monitoring_role` vorbehalten.

## Datenschutz und Löschung

- Logs dürfen Gesprächsinhalte nicht unnötig duplizieren.
- Technische Fehlerlogs enthalten Nachrichteninhalte nicht standardmäßig vollständig.
- Eine ausdrückliche Löschoperation entfernt aktive Conversation-Daten zusammenhängend.
- Archivierung ist keine Löschung.
- Backups können gelöschte Daten bis zum Ablauf ihrer Aufbewahrung enthalten.
- Export, Aufbewahrungsfristen, Backup-Löschung und rechtliche Anforderungen benötigen eigene Verträge.

Es wird noch keine Datenschutzautomatik definiert.

## Nicht-Verantwortlichkeiten und spätere Domänen

Conversation verantwortet weder Modellinferenz, Promptaufbau, Modellauswahl, Tokenisierung, Streaming, Tool-Ausführung, semantische Suche, Dateiablage, Benutzeridentität, Authentifizierung, Berechtigungen noch rohe Modellproviderfehler.

Conversation History ist nicht automatisch Langzeitgedächtnis. Spätere Memory-Domänen dürfen Conversation-Daten referenzieren oder ausgewählte Informationen ableiten, benötigen aber eigene Herkunfts-, Aufbewahrungs- und Löschregeln. Sie dürfen Nachrichten nicht stillschweigend als Erinnerungen umdeuten.

Dokumente, Wissensquellen und Retrieval gehören nicht in Conversation. Ebenso kennt die Domäne keine Modellinstanz, Modell-ID, API-Adresse oder Provider-Credentials.

Version 0.1 definiert keine Benutzerkonten, Organisationen, Mandanten oder Workspaces. `user` bezeichnet eine Gesprächsseite, nicht ein authentifiziertes Konto. Jede Installation bildet zunächst einen fachlichen Instanzkontext; Mehrbenutzer- oder Mandantenfähigkeit benötigt eine spätere Entscheidung und Migration.

## Offene Entscheidungen

1. Welche konkrete Anwendungsschnittstelle besitzt RALF Core?
2. Wie wird eine Conversation gestartet?
3. Wie werden Modellantworten später gestreamt?
4. Benötigt 0.1 eine Operation-ID oder einen Idempotency-Key?
5. Wie werden Nachrichtenkorrekturen und „erneut senden“ modelliert?
6. Welche maximale Textgröße gilt?
7. Wie werden Export und endgültige Löschung behandelt?
8. Wann werden Benutzer- oder Workspace-Grenzen eingeführt?
9. Welche Komponente orchestriert Conversation und Modellruntime?
10. Wie wird der erste PostgreSQL-Repositoryadapter strukturiert?

**Unmittelbar nächste Entscheidung:** Welche minimale Verantwortung besitzt RALF Core zwischen Benutzereingabe, `ConversationRepository` und einer späteren Modellruntime?
