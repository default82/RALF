# RALF

RALF wird bewusst neu entwickelt. Die bisherige Infrastrukturarbeit bleibt in der Git-Historie als wertvoller Prototyp erhalten, bildet aber nicht mehr die Grundlage des Hauptprojekts.

RALF entsteht von innen nach außen. Der erste Baustein ist ein eigenständiger Dienst:

## Dienst 001: Database Service

PostgreSQL ist die erste Referenzimplementierung des Database Service. Ausschlaggebend sind ACID-Eigenschaften, umfassende SQL-Unterstützung, klare Rollenverwaltung sowie etablierte Möglichkeiten für Backup und Replikation. Weitere Datenbanksysteme sollen später über denselben fachlichen Dienstvertrag unterstützt werden; PostgreSQL ist keine dauerhafte Produktbindung des Gesamtprojekts.

Die erste fachliche Spezifikation trennt den fähigkeitsorientierten RALF-Vertrag ausdrücklich vom konkreten PostgreSQL-Provider:

- [Architektur des Database Service](docs/architecture/database-service.md)
- [RALF Database Contract 0.1](docs/contracts/database-service-v0.1.md)
- [ADR-0001: providerneutrale Datenbankfähigkeit](docs/decisions/ADR-0001-database-service.md)

Es gibt derzeit noch keine Implementierung. Insbesondere existieren noch kein Installer, Controller, Webinterface, Provider, Connector, Datenmodell, ORM, REST-Endpunkt, `pgvector`, Modellruntime oder Reverse Proxy.

Der nächste kleine Schritt ist die fachliche Entscheidung, welche Daten zuerst gespeichert werden und welche RALF-Komponente der erste Datenbankkunde wird. Auch danach erfolgt nicht automatisch eine PostgreSQL-Installation.

RALF entsteht transparent durch Vibe Coding: Menschen bestimmen Ziele, Entscheidungen und Grenzen; Coding-Agenten unterstützen die Umsetzung in kleinen, überprüfbaren Schritten.
