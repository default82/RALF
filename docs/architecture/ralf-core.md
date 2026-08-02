# RALF Core – Architekturrahmen 0.1

## Zweck

RALF Core ist die erste fachliche Komponente von RALF und der erste spezifizierte RALF-native Database Consumer. Der Core koordiniert fachliche Abläufe des Assistenten, ohne selbst Datenbankbetrieb, Providerverwaltung oder Infrastrukturinstallation zu übernehmen. Er ist weder der einzige mögliche Consumer noch Eigentümer des Database Service oder einer Providerinstanz.

Die erste persistente Domäne im Core ist **Conversation**. Sie bewahrt Unterhaltungen und deren geordnete Nachrichten. Für Version 0.1 bleibt sie ein klar abgegrenzter Bestandteil von RALF Core und wird nicht als eigenständig deploybarer Netzwerkdienst ausgelegt.

## Architekturmodell

```text
Benutzer
   │
   ▼
RALF Core
   │
   └── Conversation-Domäne
          │
          ▼
      ConversationRepository
          │
          ▼
      PostgreSQL-Infrastrukturadapter
          │
          ▼
      RALF-Core-Allocation
          │
          ▼
      PostgreSQL-Provider

Database Service ── verwaltet Provider und RALF-Core-Allocation
```

Die Darstellung beschreibt Verantwortungsgrenzen, keine Prozess-, Netzwerk- oder Programmierschnittstelle:

- RALF Core besitzt das fachliche Conversation-Modell.
- Der Repository-Vertrag gehört zur Conversation-Domäne.
- Ein späterer Infrastrukturadapter übersetzt diesen Domänenvertrag in die Persistenzmechanismen des ausgewählten Providers.
- Der Database Service verwaltet die RALF-Core-Allocation, Provider, Fähigkeiten, Datenbanklebenszyklus, Schemaausführung, Health, Backup und Restore, besitzt aber nicht die fachliche Conversation-Domäne.
- PostgreSQL-spezifische Persistenzdetails bleiben im späteren PostgreSQL-Adapter beziehungsweise Provider.
- Andere RALF-Komponenten greifen nicht direkt auf den persistenten Conversation-Datenbestand zu.
- Externe Database Consumer verwenden weder RALF Core noch ConversationRepository.

## Erste fachliche Verantwortung

RALF Core soll zunächst nur die Grenze zwischen Benutzereingabe, Conversation-Domäne und einer späteren Modellruntime sauber tragen. Die minimale konkrete Orchestrierungsverantwortung ist noch zu entscheiden.

Der Core ist in diesem Architekturstand verantwortlich für:

- das Einhalten der fachlichen Conversation-Regeln,
- die Verwendung des `ConversationRepository` als Persistenzgrenze,
- die Unterscheidung von Core-Health und Conversation-Persistenz-Readiness,
- die Trennung fachlicher Fehler von Providerrohfehlern.

Nicht festgelegt werden bereits Anwendungsschnittstelle, Ausführungsmodell, Streaming, Modellaufruf oder technische Repository-Anbindung.

## Conversation bleibt eine Core-Domäne

Ein eigener Conversation-Microservice wird für 0.1 nicht vorgesehen. Unterhaltung ist eine zentrale Kernfunktion des Assistenten; ein zusätzlicher Netzwerkdienst würde derzeit Betriebs-, Deployment- und Schnittstellenkomplexität erzeugen, ohne dass unabhängige Skalierungs- oder Sicherheitsanforderungen bekannt sind.

Die Domänengrenze bleibt durch Modell, Invarianten und Repository-Vertrag dennoch explizit. Eine spätere Auslagerung ist möglich, wenn reale Anforderungen sie rechtfertigen. Hypothetische Skalierung allein ist dafür kein Grund.

## Verhältnis zum Database Service

Die RALF-Core-Allocation fordert für Conversation die Fähigkeiten `relational_storage`, `transactions`, `schema_migrations`, `constraints` und `indexes`. Backup und Restore bleiben Pflichtfähigkeiten ihres Allocation-Vertrags, werden aber nicht durch ConversationRepository aufgerufen.

Der fachliche Conversation-Schemastand gehört RALF Core beziehungsweise der Conversation-Domäne. Spätere Migrationspakete werden dort versioniert; der Database Service plant, validiert und führt ausschließlich freigegebene Migrationen aus. Ein Start von RALF Core löst keine stille Migration aus.

Im Normalbetrieb nutzt RALF Core ausschließlich seine allocation-eigene `application_identity`. Schemaänderungen bleiben der `migration_identity` vorbehalten; Backup und Monitoring verwenden weiterhin getrennte Identitäten.

## Verhältnis zu einer späteren Modellruntime

Die Conversation-Domäne speichert Gesprächsverläufe, führt aber keine Modellinferenz aus. Eine spätere Core-Orchestrierung kann Benutzernachrichten persistieren, eine Assistentenantwort beginnen und eine Modellruntime ansprechen. Reihenfolge, Streaming- und Fehlerablauf dieser Koordination sind noch nicht entschieden.

Conversation kennt keine Modellinstanz, Modell-ID, Provideradresse oder Provider-Credentials. Eine spätere nicht geheime Ausführungsreferenz benötigt eine eigene Entscheidung.

## Health und Readiness

RALF Core kann grundsätzlich gesund sein, obwohl Conversation-Persistenz nicht bereit ist.

**Core healthy** bedeutet zunächst, dass der Core-Prozess grundsätzlich läuft und die Conversation-Domäne initialisierbar ist.

**Conversation persistence ready** setzt zusätzlich voraus:

- Database Service ist `ready`,
- alle benötigten Fähigkeiten sind vorhanden,
- das Conversation-Schema ist kompatibel,
- keine erforderliche Migration steht aus,
- die allocation-eigene `application_identity` besitzt die minimal notwendigen Rechte,
- eine Lese- und Schreibtransaktion kann sicher ausgeführt werden.

Beispiel: `healthy = true`, aber `conversation_persistence_ready = false` mit dem providerneutralen Grund `schema_migration_required`.

## Nicht-Verantwortlichkeiten

RALF Core übernimmt in diesem Schritt weder Installer- oder Infrastrukturaufgaben noch Datenbankadministration. Ebenfalls nicht definiert werden Webinterface, Authentifizierung, Benutzer- oder Mandantenverwaltung, Modellruntime, Tool-Ausführung, Langzeitgedächtnis, Wissensspeicher, Streaming oder Netzwerkprotokolle.

## Offene Core-Frage

Für RALF Core bleibt zu entscheiden, welche minimale Verantwortung er zwischen Benutzereingabe, `ConversationRepository` und einer späteren Modellruntime besitzt. Der nächste projektweite Schritt ist gemäß ADR-0003 zunächst die Spezifikation des PostgreSQL-Referenzproviders und des Allocation-Lebenszyklus, weiterhin ohne Installation oder Implementierung.
