Bootstrap-Reihenfolge (RALF v1)

Der initiale Aufbau von RALF folgt einer festen Reihenfolge. Ziel ist es, zuerst eine stabile technische Basis zu schaffen, bevor Automatisierung und Logik greifen.

1. PostgreSQL – Persistente Basis

PostgreSQL wird als erstes System bereitgestellt.
Es dient als zentrale, persistente Datenbasis für RALF-nahe Dienste (z. B. Semaphore) und spätere Erweiterungen.

Bereitstellung als LXC

Statische IP

Netzwerkzugriff nur aus dem Homelab

Separate Rollen und Datenbanken pro Dienst

Begründung:
Automatisierung ohne stabile Persistenz führt zu impliziten Abhängigkeiten und schwer reproduzierbaren Zuständen. PostgreSQL ist daher der erste feste Anker.

2. Semaphore – Ausführende Instanz („RALF-Hände“)

Semaphore wird auf die bestehende PostgreSQL-Instanz aufgesetzt und übernimmt die Ausführung von Ansible-Playbooks.

Verbindet sich mit PostgreSQL

Hält keine eigene Logik, sondern führt definierte Abläufe aus

Verwaltet SSH-Keys, Repositories und Inventare

Begründung:
Semaphore ist kein Steuerzentrum, sondern ein ausführendes Werkzeug. Es wird erst sinnvoll, wenn eine stabile Datenbasis existiert.

3. Repository & Inventar – Source of Truth

Erst nach funktionierender Ausführungsebene wird das Repository angebunden:

Inventare (Hosts, Gruppen, Variablen)

Bootstrap-Playbooks

Rollen-Struktur

Begründung:
RALF soll reproduzierbar handeln. Das Repository beschreibt den gewünschten Zustand, Semaphore setzt ihn um.

4. Bootstrap-Playbooks – Minimalstandard

Initiale Playbooks bringen Systeme in einen definierten Grundzustand:

Paketbasis

Zeitsynchronisation

Benutzer / SSH-Zugriff

Markierung als „RALF-bootstrapped“

Noch keine Fachlogik, keine Dienste.

5. Service-Module – Schrittweise Erweiterung

Erst danach folgen eigentliche Dienste (Gitea, Vaultwarden, Monitoring, etc.) als eigenständige Rollen.

Prinzip:

Erst Fundament, dann Hände, dann Plan, dann Logik.
