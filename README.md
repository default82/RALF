# RALF

RALF wird bewusst neu entwickelt. Die bisherige Infrastrukturarbeit bleibt in der Git-Historie als wertvoller Prototyp erhalten, bildet aber nicht mehr die Grundlage des Hauptprojekts.

RALF entsteht von innen nach außen. Der erste Baustein ist ein eigenständiger Dienst:

## Dienst 001: Database Service

PostgreSQL ist die erste Referenzimplementierung des Database Service. Ausschlaggebend sind ACID-Eigenschaften, umfassende SQL-Unterstützung, klare Rollenverwaltung sowie etablierte Möglichkeiten für Backup und Replikation. Weitere Datenbanksysteme sollen später über denselben fachlichen Dienstvertrag unterstützt werden; PostgreSQL ist keine dauerhafte Produktbindung des Gesamtprojekts.

Die erste fachliche Spezifikation trennt den fähigkeitsorientierten RALF-Vertrag ausdrücklich vom konkreten PostgreSQL-Provider:

- [Architektur des Database Service](docs/architecture/database-service.md)
- [RALF Database Contract 0.1](docs/contracts/database-service-v0.1.md)
- [ADR-0001: providerneutrale Datenbankfähigkeit](docs/decisions/ADR-0001-database-service.md)

Der erste Datenbankkunde ist **RALF Core**. Seine erste persistente Domäne **Conversation** speichert ausschließlich Unterhaltungen und geordnete Nachrichten. Conversation bleibt zunächst eine Core-Domäne und verwendet einen fachlichen Repository-Vertrag:

- [Architekturrahmen von RALF Core](docs/architecture/ralf-core.md)
- [Conversation-Domäne 0.1](docs/domains/conversation.md)
- [ConversationRepository Contract 0.1](docs/contracts/conversation-repository-v0.1.md)
- [ADR-0002: erster Datenbankkunde](docs/decisions/ADR-0002-first-database-customer.md)

Es gibt weiterhin keine Implementierung. Insbesondere existieren noch kein SQL, keine Tabellen, PostgreSQL-Installation, Programmierschnittstelle, Modellruntime, Benutzerverwaltung, Weboberfläche oder Infrastruktur.

Der nächste kleine Schritt ist die fachliche Entscheidung, welche minimale Verantwortung RALF Core zwischen Benutzereingabe, ConversationRepository und einer späteren Modellruntime besitzt. Auch danach erfolgt nicht automatisch eine PostgreSQL-Installation.

RALF entsteht transparent durch Vibe Coding: Menschen bestimmen Ziele, Entscheidungen und Grenzen; Coding-Agenten unterstützen die Umsetzung in kleinen, überprüfbaren Schritten.
