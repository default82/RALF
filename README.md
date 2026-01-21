# RALF Homelab (Bootstrap Repo)

Dieses Repository ist die **Source of Truth** für den Aufbau eines Homelab-Systems,
in dem ein zukünftiges System („RALF“) Dienste **planbar, genehmigungsfähig, reproduzierbar**
und **selbstheilend** ausrollen kann.

Aktueller Bootstrap-Stand:
- Remote: GitHub (temporär)
- Runner: Semaphore (wird zuerst installiert)
- Danach: PostgreSQL (Functional) → Gitea (extern via otta.zone) → Repo-Remote umstellen
- Alles läuft in **LXC** unter Proxmox, keine Docker-Deployments.

## Grundprinzipien (nicht verhandelbar)
- Netzwerk ist die Basis: ohne „Network Health“ keine Deployments
- Änderungen passieren kontrolliert: **Intent → Plan → Freigabe → Change**
- Jede Änderung ist rollback-fähig (Snapshots)
- Secrets gehören nicht ins Repo (Semaphore Variablen/Secrets)

## Struktur
- `docs/` – Grundgesetze (z.B. Netzwerk-Baseline)
- `healthchecks/` – bindende Checklisten (Gatekeeper)
- `plans/` – Intents & Pläne (Templates + konkrete Artefakte)
- `changes/` – Changes (Templates + konkrete Artefakte)
- `incidents/` – Störungen, Ursachen, Lessons Learned
- `services/` – Service-Steckbriefe
- `iac/` – Infrastructure as Code (OpenTofu + ggf. Ansible)
- `pipelines/` – Runner-Pipelines (Semaphore)
- `tests/` – Smoke/Acceptance-Tests (Teil der Definition of Done)

## Bootstrap-Reihenfolge (RALF v1)

Der initiale Aufbau von RALF folgt einer festen und bewusst einfachen Reihenfolge.
Ziel ist es, zuerst eine stabile technische Basis zu schaffen, bevor Automatisierung
und logische Steuerung greifen.

### 1. PostgreSQL – Persistente Basis
PostgreSQL wird als erstes System bereitgestellt.

- Zentrale Datenbank für RALF-nahe Dienste (z. B. Semaphore)
- Statische IP
- Zugriff nur aus dem Homelab
- Separate Rollen und Datenbanken pro Dienst

Begründung:  
Automatisierung ohne stabile Persistenz führt zu impliziten Abhängigkeiten und
nicht reproduzierbaren Zuständen. PostgreSQL ist der erste feste Anker.

### 2. Semaphore – Ausführende Instanz („RALF-Hände“)
Semaphore wird auf die bestehende PostgreSQL-Instanz aufgesetzt.

- Führt Ansible-Playbooks aus
- Verwaltet SSH-Keys, Repositories und Inventare
- Enthält selbst keine fachliche Logik

Begründung:  
Semaphore ist kein Steuerzentrum, sondern ein ausführendes Werkzeug.
Es wird erst sinnvoll, wenn eine stabile Datenbasis existiert.

### 3. Repository & Inventar – Source of Truth
Nach funktionierender Ausführungsebene wird das Repository angebunden.

- Inventare (Hosts, Gruppen, Variablen)
- Bootstrap-Playbooks
- Rollen-Struktur

RALF beschreibt den gewünschten Zustand im Repository,
Semaphore setzt ihn um.

### 4. Bootstrap-Playbooks – Minimalstandard
Initiale Playbooks bringen Systeme in einen definierten Grundzustand:

- Paketbasis
- Zeitsynchronisation
- Benutzer / SSH-Zugriff
- Markierung als „RALF-bootstrapped“

Noch keine Fachlogik, keine Dienste.

### 5. Service-Module – Schrittweise Erweiterung
Erst danach folgen eigentliche Dienste (z. B. Gitea, Vaultwarden, Monitoring)
als eigenständige Rollen.

Prinzip:  
**Erst Fundament, dann Hände, dann Plan, dann Logik.**

## Aktueller Bootstrap-Stand

- PostgreSQL als LXC bereitgestellt (persistente Basis)
- Semaphore in Vorbereitung / angebunden an PostgreSQL
- Repository dient aktuell der Planung und Strukturierung
- Automatisierung wird schrittweise aktiviert
- GitHub wird temporär als Remote für Planung und Ideensammlung genutzt

Hinweis:  
Das Repository ist bewusst strukturorientiert. Nicht alle enthaltenen Konzepte
sind bereits produktiv umgesetzt.

## Netzwerk-Hinweis

Die aktuelle IP-Zuordnung (z. B. PostgreSQL im 10.10.20.0/16-Netz)
entspricht dem aktuellen Bootstrap-Stand.
Eine spätere Konsolidierung oder Segmentierung wird durch RALF vorbereitet
und ist bewusst nicht Teil der initialen Phase.




## Zonen
Zonen sind Flags (keine eigenen Netze):
- Playground: Lernen/Experimente, darf „brechen“
- Functional: muss stabil laufen

Siehe: `docs/network-baseline.md`
