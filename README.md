# RALF

RALF wird bewusst neu entwickelt. Die bisherige Infrastrukturarbeit bleibt in der Git-Historie als wertvoller Prototyp erhalten, bildet aber nicht mehr die Grundlage des Hauptprojekts.

RALF entsteht von innen nach außen. Der erste Baustein ist ein eigenständiger Dienst:

## Dienst 001: Database Service

Der Database Service ist eine gemeinsam nutzbare Datenbankplattform. Er kann isolierte Database Allocations für RALF-eigene Komponenten und externe Anwendungen verwalten. PostgreSQL ist die erste Referenzimplementierung des Providers, aber keine dauerhafte Produktbindung des öffentlichen Vertrags.

Die erste fachliche Spezifikation trennt den fähigkeitsorientierten RALF-Vertrag ausdrücklich vom konkreten PostgreSQL-Provider:

- [Architektur des Database Service](docs/architecture/database-service.md)
- [RALF Database Contract 0.1](docs/contracts/database-service-v0.1.md)
- [Database Allocation Contract 0.1](docs/contracts/database-allocation-v0.1.md)
- [Provider 001: PostgreSQL](docs/providers/postgresql.md)
- [Database-Allocation-Lebenszyklus](docs/lifecycle/database-allocation.md)
- [ADR-0001: providerneutrale Datenbankfähigkeit](docs/decisions/ADR-0001-database-service.md)
- [ADR-0003: gemeinsam nutzbare Datenbankplattform](docs/decisions/ADR-0003-shared-database-platform.md)
- [ADR-0004: PostgreSQL als erster Referenzprovider](docs/decisions/ADR-0004-postgresql-reference-provider.md)
- [ADR-0005: erstes PostgreSQL-Deploymentprofil](docs/decisions/ADR-0005-first-postgresql-deployment-profile.md)

Der erste spezifizierte RALF-native Database Consumer ist **RALF Core**. Seine erste persistente Domäne **Conversation** speichert ausschließlich Unterhaltungen und geordnete Nachrichten. Conversation bleibt zunächst eine Core-Domäne und verwendet nur in der RALF-Core-Allocation einen fachlichen Repository-Vertrag:

- [Architekturrahmen von RALF Core](docs/architecture/ralf-core.md)
- [Conversation-Domäne 0.1](docs/domains/conversation.md)
- [ConversationRepository Contract 0.1](docs/contracts/conversation-repository-v0.1.md)
- [ADR-0002: erster RALF-nativer Consumer](docs/decisions/ADR-0002-first-database-customer.md)

Externe Anwendungen wie Gitea oder optional OpenBao können eigene Allocations mit nativen Datenbankzugriffen erhalten; sie verwenden ConversationRepository nicht. Referenzstandard ist eine logische Datenbank mit eigenen Identitäten pro Consumer. Die verbindliche externe Secrets-Wurzel ist `/secrets`; im Repository stehen ausschließlich nicht geheime Referenzen, und `secrets/` bleibt ausgeschlossen.

Es gibt weiterhin keine Implementierung. Insbesondere existieren noch kein SQL, keine Tabellen, PostgreSQL-Installation, Programmierschnittstelle, Modellruntime, Benutzerverwaltung, Weboberfläche oder Infrastruktur.

Provider 001 beschreibt PostgreSQL als konkrete Referenz hinter dem providerneutralen Vertrag. Das erste deployment-spezifische Profil wählt PostgreSQL Major 18 und die gemeinsame Providerinstanz `postgresql-main`. Ihr initial dokumentierter Minor-Stand ist 18.4; installiert wird später die dann neueste stabile 18.x-Minor-Version. Ein automatischer Wechsel auf PostgreSQL 19 ist ausgeschlossen.

Für die erste Referenzinstallation sind vier isolierte Allocations ausgewählt: Gitea, OpenBao, Semaphore UI und Node-RED. RALF Core erhält noch keine Allocation. OpenBao verwendet in diesem Deployment bewusst PostgreSQL; Node-RED nutzt seine Allocation nur für relationale Flow-Anwendungsdaten, nicht automatisch als internen Speicher.

Der nächste kleine Schritt ist ein zunächst read-only geplanter Implementierungspfad. Vor jeder Mutation werden noch Betriebsform, Netzwerkgrenze, Ressourcen, Backupziel, Rechte unter `/secrets` und kompatible Anwendungsversionen festgelegt. PostgreSQL ist weiterhin nicht installiert.

RALF entsteht transparent durch Vibe Coding: Menschen bestimmen Ziele, Entscheidungen und Grenzen; Coding-Agenten unterstützen die Umsetzung in kleinen, überprüfbaren Schritten.
