# Caddy Reverse Proxy Fix - Web-UI Anleitung

## Problem

Die OPNsense Caddy-Plugin API-Endpunkte sind nicht vollständig dokumentiert. Die aktuellen Konfigurationen haben **falsche Backend-IPs**:

- **Gitea**: Zeigt auf `10.10.40.1` → sollte `10.10.20.12` sein
- **Semaphore**: Zeigt auf `10.10.40.2` → sollte `10.10.100.15` sein

Außerdem fehlen:
- **dashy.otta.zone** → `10.10.40.11:4000`
- **vault.otta.zone** → `10.10.30.10:8080`

---

## Lösung via Web-UI

### Öffne OPNsense Caddy-Konfiguration

1. Browser: `https://10.10.0.1:8443`
2. Login mit Admin-Credentials
3. **Services → Caddy Web Server → Reverse Proxy**

---

## Fix 1: Gitea Backend-IP korrigieren

1. In der **Handler-Liste** suche nach Handler für `gitea.otta.zone`
2. Klicke auf das **Edit-Icon** (Stift)
3. Ändere:
   - **Upstream Domain**: `10.10.40.1` → `10.10.20.12`
   - **Upstream Port**: `3000` (bleibt gleich)
   - **Upstream TLS**: `http://` (bleibt gleich)
4. **Save**

---

## Fix 2: Semaphore Backend-IP korrigieren

1. In der **Handler-Liste** suche nach Handler für `semaphore.otta.zone`
2. Klicke auf **Edit-Icon**
3. Ändere:
   - **Upstream Domain**: `10.10.40.2` → `10.10.100.15`
   - **Upstream Port**: `3000` (bleibt gleich)
   - **Upstream TLS**: `http://` (bleibt gleich)
4. **Save**

---

## Hinzufügen 1: Dashy

### Schritt 1: Domain erstellen

1. Tab: **Domains**
2. Klicke **+ Add**
3. Fülle aus:
   - **Domain**: `dashy.otta.zone`
   - **Port**: `443` (Standard HTTPS)
   - **Certificate**: `otta.zone (ACME Client)`
   - **Enabled**: ✅
4. **Save**

### Schritt 2: Handler erstellen

1. Tab: **Handler**
2. Klicke **+ Add**
3. Fülle aus:
   - **Domain**: `dashy.otta.zone` (aus Dropdown)
   - **Handle Type**: `handle`
   - **Handle Path**: `/*`
   - **Handler**: `reverse_proxy`
   - **Upstream Domain**: `10.10.40.11`
   - **Upstream Port**: `4000`
   - **Upstream TLS**: `http://`
   - **Enabled**: ✅
4. **Save**

---

## Hinzufügen 2: Vaultwarden

### Schritt 1: Domain erstellen

1. Tab: **Domains**
2. Klicke **+ Add**
3. Fülle aus:
   - **Domain**: `vault.otta.zone`
   - **Port**: `443`
   - **Certificate**: `otta.zone (ACME Client)`
   - **Enabled**: ✅
4. **Save**

### Schritt 2: Handler erstellen

1. Tab: **Handler**
2. Klicke **+ Add**
3. Fülle aus:
   - **Domain**: `vault.otta.zone`
   - **Handle Type**: `handle`
   - **Handle Path**: `/*`
   - **Handler**: `reverse_proxy`
   - **Upstream Domain**: `10.10.30.10`
   - **Upstream Port**: `8080`
   - **Upstream TLS**: `http://`
   - **Enabled**: ✅
4. **Save**

---

## Konfiguration anwenden

1. Oben rechts: **Apply**
2. Warte bis "Configuration applied successfully" erscheint

---

## Testen

```bash
# Von Proxmox Host oder einem anderen System im Netzwerk
curl -I https://gitea.otta.zone
curl -I https://semaphore.otta.zone
curl -I https://dashy.otta.zone
curl -I https://vault.otta.zone
```

**Erwartung**: Alle sollten `HTTP/2 200` oder `HTTP/2 302` (Redirect) zurückgeben, **nicht** `502 Bad Gateway`.

---

## Zusammenfassung der Änderungen

| Domain | Aktuell | Neu | Status |
|--------|---------|-----|--------|
| gitea.otta.zone | 10.10.40.1:3000 | 10.10.20.12:3000 | ✏️ Fix |
| semaphore.otta.zone | 10.10.40.2:3000 | 10.10.100.15:3000 | ✏️ Fix |
| dashy.otta.zone | - | 10.10.40.11:4000 | ➕ Neu |
| vault.otta.zone | - | 10.10.30.10:8080 | ➕ Neu |

---

## DNS-Hinweis

Stelle sicher, dass die DNS-Records für `*.otta.zone` auf die **externe IP** deines Homelabs zeigen. Falls du Split-DNS nutzt, müssen die internen DNS-Records auf die **OPNsense IP** (`10.10.0.1`) zeigen.

### DNS-Check:

```bash
dig gitea.otta.zone
dig semaphore.otta.zone
dig dashy.otta.zone
dig vault.otta.zone
```

---

## Troubleshooting

### Immer noch 502 Bad Gateway?

1. **Backend erreichbar?**
   ```bash
   curl http://10.10.20.12:3000  # Gitea
   curl http://10.10.100.15:3000 # Semaphore
   curl http://10.10.40.11:4000  # Dashy
   curl http://10.10.30.10:8080  # Vaultwarden
   ```

2. **Caddy Logs prüfen**:
   - **System → Log Files → Caddy**
   - Suche nach Fehlern wie "dial tcp" oder "connection refused"

3. **Firewall-Regeln**:
   - **Firewall → Rules → LAN**
   - Stelle sicher, dass Traffic von OPNsense zu den Backend-IPs erlaubt ist

### Let's Encrypt Zertifikat-Fehler?

Falls Let's Encrypt Zertifikate nicht automatisch generiert werden:

1. **Services → Caddy → General Settings**
2. Prüfe **TLS Email**: sollte `kolja.otta@gmail.com` sein
3. Prüfe **Auto HTTPS**: sollte `Enabled (Standard)` sein
4. Ports 80 und 443 müssen von außen erreichbar sein

---

## Alternative: Manuell via Caddyfile

Falls die Web-UI nicht funktioniert, kannst du die Konfiguration auch direkt im Caddyfile bearbeiten (nicht empfohlen, da OPNsense das überschreibt):

```bash
ssh root@10.10.0.1
vi /usr/local/etc/caddy/Caddyfile
```

Aber **Achtung**: Die Web-UI überschreibt manuelle Änderungen beim nächsten "Apply"!
