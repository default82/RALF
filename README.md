# RALF

RALF wird bewusst neu entwickelt. Die bisherige Infrastrukturarbeit bleibt in der Git-Historie als wertvoller Prototyp erhalten, bildet aber nicht mehr die Grundlage des Hauptprojekts.

RALF entsteht von innen nach außen. Der erste Baustein ist ein eigenständiger Dienst:

## Dienst 001: Database Service

PostgreSQL ist die erste Referenzimplementierung des Database Service. Ausschlaggebend sind ACID-Eigenschaften, umfassende SQL-Unterstützung, klare Rollenverwaltung sowie etablierte Möglichkeiten für Backup und Replikation. Weitere Datenbanksysteme sollen später über denselben fachlichen Dienstvertrag unterstützt werden; PostgreSQL ist keine dauerhafte Produktbindung des Gesamtprojekts.

Der nächste Schritt ist ausschließlich die gemeinsame Spezifikation des Database Service:

- Aufgaben und Verantwortlichkeiten,
- Schnittstellen und Konfiguration,
- Lebenszyklus,
- Backup und Wiederherstellung,
- Health Checks,
- Vertrag zwischen RALF und dem Datenbankdienst.

Es gibt derzeit noch keine Implementierung. Insbesondere existieren noch kein Installer, Controller, Webinterface, Provider, Connector, Datenmodell, ORM, REST-Endpunkt, `pgvector`, Modellruntime oder Reverse Proxy.

RALF entsteht transparent durch Vibe Coding: Menschen bestimmen Ziele, Entscheidungen und Grenzen; Coding-Agenten unterstützen die Umsetzung in kleinen, überprüfbaren Schritten.
