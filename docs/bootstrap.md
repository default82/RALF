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

---

## Credential-Management

### Passwort-Generierung

RALF verwendet automatisch generierte Passwörter für alle Services. Die Generierung erfolgt durch `bootstrap/generate-credentials.sh`.

**Zeichensatz (optimiert für HTTP Basic Auth Kompatibilität):**
- Großbuchstaben: `A-Z` (ohne I, L, O) = 23 Zeichen
- Kleinbuchstaben: `a-z` (ohne i, l, o) = 23 Zeichen
- Ziffern: `2-9` (ohne 0, 1) = 8 Zeichen
- Sonderzeichen: `-` und `_` = 2 Zeichen
- **Gesamt: 56 Zeichen**

**Passwort-Länge:**
- Einheitlich **32 Zeichen** für alle Passwörter (Admin-Accounts, Datenbank-User, Mail-Accounts)
- **Entropie: ~189 bit**

**Begründung der Zeichensatz-Wahl:**
- **Keine problematischen Sonderzeichen:** `?`, `%`, `!`, `@`, `#`, `&`, `*`, `+` verursachen Probleme bei:
  - HTTP Basic Authentication (URL-Encoding erforderlich)
  - Shell-Expansion (`*`, `?`, `!`)
  - YAML/JSON-Escaping
- **Nur `-` und `_`:** Funktionieren garantiert in allen Kontexten ohne Escaping
- **Maximum Compatibility über Maximum Security:** Praktikabilität in Multi-Service-Umgebung

**Verwendung:**
```bash
# Credentials generieren
bash bootstrap/generate-credentials.sh

# Credentials laden
source /var/lib/ralf/credentials.env
```

**Wichtig:**
- Alle Passwörter werden in `/var/lib/ralf/credentials.env` gespeichert
- Automatisches Backup bei jeder Regenerierung: `credentials.env.backup.YYYYMMDD_HHMMSS`
- **Nie** Credentials in Git committen (`.gitignore` beachten)

### Credential-Rotation

Nach Passwort-Regenerierung müssen existierende Services aktualisiert werden:

1. **PostgreSQL Database User:**
   ```bash
   pct exec 2010 -- su - postgres -c "psql <<EOF
   ALTER USER gitea WITH PASSWORD '\$GITEA_PG_PASS';
   ALTER USER semaphore WITH PASSWORD '\$SEMAPHORE_PG_PASS';
   EOF"
   ```

2. **Gitea Admin Users:**
   ```bash
   pct exec 2012 -- bash -c "cd /var/lib/gitea && \
     sudo -u git /usr/local/bin/gitea admin user change-password \
     --username kolja --password '\$GITEA_ADMIN1_PASS' \
     --must-change-password=false --config /etc/gitea/app.ini"
   ```

3. **Semaphore Config & Users:**
   ```bash
   # Update config.json database password
   pct exec 10015 -- python3 -c "import json; \
     cfg=json.load(open('/etc/semaphore/config.json')); \
     cfg['postgres']['pass']='\$SEMAPHORE_PG_PASS'; \
     json.dump(cfg, open('/etc/semaphore/config.json','w'), indent=2)"

   # Restart Semaphore
   pct exec 10015 -- systemctl restart semaphore

   # Update user passwords
   pct exec 10015 -- /usr/local/bin/semaphore users change-by-login \
     --login kolja --password '\$SEMAPHORE_ADMIN1_PASS' \
     --config /etc/semaphore/config.json
   ```
