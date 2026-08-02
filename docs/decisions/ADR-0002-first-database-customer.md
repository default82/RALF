# ADR-0002: RALF Core und Conversation als erster Datenbankkunde

- **Status:** Angenommen
- **Datum:** 2026-08-02

## Kontext

ADR-0001 hat den Database Service als providerneutrale persistente Fähigkeit festgelegt und fachliche Datenzugriffe den jeweiligen Domänenverträgen zugeordnet. Für den nächsten Schritt muss ein realer fachlicher Kunde benannt werden, damit die Abstraktion an einem kleinen, nützlichen Datenbestand präzisiert werden kann, ohne bereits PostgreSQL oder eine technische Schnittstelle zu implementieren.

RALF soll nach dem Architektur-Neustart von innen nach außen zu einem nutzbaren Assistentenkern wachsen. Unterhaltung ist dafür zentral, während Installer-, Inventar-, Memory-, Benutzer- oder Providerdaten noch keinen vergleichbar unmittelbaren Kernnutzen begründen.

## Entscheidung

RALF Core ist der erste fachliche Kunde des Database Service. Seine erste persistente Domäne ist Conversation; der erste dauerhafte fachliche Datenbestand besteht ausschließlich aus Unterhaltungen und deren geordneten Nachrichten.

Conversation bleibt in Version 0.1 Bestandteil von RALF Core und verwendet den domänenspezifischen `ConversationRepository`-Vertrag. Es entsteht kein eigenständig deploybarer Conversation-Microservice.

RALF Core besitzt das Conversation-Modell und dessen fachliches Schema. Der Database Service besitzt diese Fachdomäne nicht; er verwaltet Provider, Fähigkeiten, Datenbanklebenszyklus, kontrollierte Schemaausführung, Health, Backup und Restore. PostgreSQL-spezifische Details bleiben in einem späteren Infrastrukturadapter beziehungsweise Provider.

Andere RALF-Komponenten erhalten keinen direkten Zugriff auf Conversation-Persistenzstrukturen.

## Begründung

- Conversation liefert früh einen erkennbaren Nutzen für den eigentlichen RALF-Kern.
- Ein begrenzter fachlicher Bestand prüft die in ADR-0001 gewählte Repository-Grenze konkret.
- Die Einbettung in RALF Core vermeidet derzeit unnötige Netzwerk-, Deployment- und Betriebsgrenzen.
- Klare Domänen- und Repository-Verträge erlauben eine spätere Auslagerung, falls reale Skalierungs- oder Sicherheitsanforderungen entstehen.
- Nur tatsächlich benötigte Database-Service-Fähigkeiten werden für den ersten Kunden verbindlich.

## Konsequenzen

### Positiv

- Die erste Persistenzentscheidung folgt einem fachlichen Anwendungsfall statt einer generischen Speicherabstraktion.
- Conversation und Database Service besitzen klar getrennte Verantwortlichkeiten.
- PostgreSQL bleibt austauschbarer Referenzprovider hinter der Vertragsgrenze.
- Version 0.1 benötigt weder Benutzer-, Mandanten-, Memory-, Tool- noch Modellpersistenz.
- `json_documents` und `full_text_search` werden für den ersten Kunden nicht verpflichtend.

### Aufwand und Risiken

- RALF Core benötigt später einen sorgfältig begrenzten Infrastrukturadapter.
- Parallelität, Idempotenz, Streaming und endgültige Löschung brauchen weitere Entscheidungen.
- Ohne Benutzer- oder Workspace-Modell gilt zunächst ein einzelner fachlicher Instanzkontext.
- Conversation-Inhalte können sensibel sein und benötigen später Datenschutz-, Export- und Aufbewahrungsverträge.

## Verworfene und zurückgestellte Alternativen

### Installer- oder Inventardaten zuerst

Verworfen, weil der Neustart bewusst zuerst den eigentlichen RALF-Kern entwickelt und keine neue Installations- oder Controllerarchitektur vorzieht.

### Generischer Key-Value- oder CRUD-Speicher

Verworfen, weil eine generische Speicheroberfläche keine klare fachliche Eigentümerschaft schafft und die in ADR-0001 abgelehnte Universal-API wieder einführen würde.

### Langzeitgedächtnis zuerst

Verworfen, weil noch nicht feststeht, was RALF erinnern soll und welche Regeln für Einwilligung, Herkunft, Aufbewahrung und Löschung gelten.

### Eigener Conversation-Microservice

Für 0.1 verworfen, weil keine unabhängigen Skalierungs-, Sicherheits- oder Deploymentanforderungen vorliegen. Hypothetische spätere Skalierung rechtfertigt heute keinen Netzwerkdienst.

### Benutzer- und Mandantenmodell zuerst

Zurückgestellt, weil 0.1 zunächst einen einzelnen RALF-Instanzkontext verwendet. Mehrbenutzer- oder Mandantenfähigkeit benötigt später eine eigene Entscheidung und Migration.

## Nicht entschiedene Punkte

- minimale Verantwortung und Anwendungsschnittstelle von RALF Core,
- Start einer Conversation,
- Orchestrierung und Streaming späterer Modellantworten,
- Idempotenz und konkurrierende Schreibvorgänge,
- Nachrichtenkorrekturen und „erneut senden“,
- maximale Textgröße,
- Export, Aufbewahrung und endgültige Löschung,
- spätere Benutzer- und Workspace-Grenzen,
- Struktur des ersten PostgreSQL-Infrastrukturadapters.

## Nächster Schritt

Als Nächstes wird fachlich entschieden, welche minimale Verantwortung RALF Core zwischen Benutzereingabe, `ConversationRepository` und einer späteren Modellruntime besitzt. Dies ist weiterhin keine PostgreSQL-Installation und keine Implementierung.
