# RALF

RALF wird bewusst neu entwickelt. Die bisherige Infrastrukturarbeit bleibt in der Git-Historie als wertvoller Prototyp erhalten, bildet aber nicht mehr die Grundlage des Hauptprojekts.

RALF entsteht von innen nach außen. Der erste Baustein ist ein eigenständiger Dienst:

## Dienst 001: Database Service

Der Database Service ist eine gemeinsam nutzbare Datenbankplattform. Er kann isolierte Database Allocations für RALF-eigene Komponenten und externe Anwendungen verwalten. PostgreSQL ist die erste Referenzimplementierung des Providers, aber keine dauerhafte Produktbindung des öffentlichen Vertrags.

Die erste fachliche Spezifikation trennt den fähigkeitsorientierten RALF-Vertrag ausdrücklich vom konkreten PostgreSQL-Provider:

- [Architektur des Database Service](docs/architecture/database-service.md)
- [RALF Database Contract 0.1](docs/contracts/database-service-v0.1.md)
- [Database Allocation Contract 0.1](docs/contracts/database-allocation-v0.1.md)
- [ADR-0001: providerneutrale Datenbankfähigkeit](docs/decisions/ADR-0001-database-service.md)
- [ADR-0003: gemeinsam nutzbare Datenbankplattform](docs/decisions/ADR-0003-shared-database-platform.md)

Der erste spezifizierte RALF-native Database Consumer ist **RALF Core**. Seine erste persistente Domäne **Conversation** speichert ausschließlich Unterhaltungen und geordnete Nachrichten. Conversation bleibt zunächst eine Core-Domäne und verwendet nur in der RALF-Core-Allocation einen fachlichen Repository-Vertrag:

- [Architekturrahmen von RALF Core](docs/architecture/ralf-core.md)
- [Conversation-Domäne 0.1](docs/domains/conversation.md)
- [ConversationRepository Contract 0.1](docs/contracts/conversation-repository-v0.1.md)
- [ADR-0002: erster RALF-nativer Consumer](docs/decisions/ADR-0002-first-database-customer.md)

Externe Anwendungen wie Gitea oder optional OpenBao können eigene Allocations mit nativen Datenbankzugriffen erhalten; sie verwenden ConversationRepository nicht. Referenzstandard ist eine logische Datenbank mit eigenen Identitäten pro Consumer. Die verbindliche externe Secrets-Wurzel ist `/secrets`; im Repository stehen ausschließlich nicht geheime Referenzen, und `secrets/` bleibt ausgeschlossen.

Es gibt weiterhin keine Implementierung. Insbesondere existieren noch kein SQL, keine Tabellen, PostgreSQL-Installation, Programmierschnittstelle, Modellruntime, Benutzerverwaltung, Weboberfläche oder Infrastruktur.

Der nächste kleine Schritt ist die Spezifikation des PostgreSQL-Referenzproviders und des Allocation-Lebenszyklus. Auch danach erfolgt nicht automatisch eine PostgreSQL-Installation.

RALF entsteht transparent durch Vibe Coding: Menschen bestimmen Ziele, Entscheidungen und Grenzen; Coding-Agenten unterstützen die Umsetzung in kleinen, überprüfbaren Schritten.
