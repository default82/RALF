# Caddy Timeout Probleme - Lösungen

## Problem: Alle Requests timed out

### Häufigste Ursachen & Fixes

#### 1. **Falsches Backend-Protokoll (HÄUFIGSTE URSACHE)**

**Problem:** Caddy versucht HTTPS zu Backend, aber Backend läuft nur HTTP

**Symptom:**
```
timeout oder "context deadline exceeded"
```

**Fix:**
```caddy
# ❌ FALSCH (verursacht Timeout wenn Backend nur HTTP hat)
gitea.otta.zone {
    reverse_proxy 10.10.20.12:3000
    # Caddy versucht HTTPS (Port 3000 suggeriert HTTPS)
}

# ✅ RICHTIG
gitea.otta.zone {
    reverse_proxy http://10.10.20.12:3000
    # Explizit HTTP erzwingen
}
```

#### 2. **TLS Verification für interne Services**

**Problem:** Caddy versucht TLS-Zertifikate zu verifizieren

**Fix:**
```caddy
gitea.otta.zone {
    reverse_proxy http://10.10.20.12:3000 {
        # Für HTTP-Backends nicht nötig, aber bei HTTPS:
        transport http {
            tls_insecure_skip_verify
        }
    }
}
```

#### 3. **Timeout-Werte zu niedrig**

**Fix:**
```caddy
gitea.otta.zone {
    reverse_proxy http://10.10.20.12:3000 {
        timeout 30s
        dial_timeout 10s
    }
}
```

#### 4. **OPNsense Caddy Plugin - Falsche UI-Einstellungen**

Im OPNsense Web-UI (Services → Caddy → Reverse Proxy):

**Handler-Einstellungen:**
- **Upstream Protocol:** `http` (nicht https!)
- **Upstream Host:** `10.10.20.12`
- **Upstream Port:** `3000`
- **TLS Insecure Skip Verify:** Aktiviert (wenn HTTPS-Backend ohne valides Cert)

#### 5. **DNS-Auflösung schlägt fehl**

**Problem:** Caddy kann Backend-Hostnamen nicht auflösen

**Fix:** IPs statt Hostnamen verwenden:
```caddy
# ❌ FALSCH (wenn DNS nicht funktioniert)
reverse_proxy gitea-container:3000

# ✅ RICHTIG
reverse_proxy http://10.10.20.12:3000
```

#### 6. **Firewall blockiert Traffic**

**Check:**
```bash
# Auf OPNsense
pfctl -sr | grep -E '10.10.(20|40|100)'
```

**Fix:** LAN → LAN Traffic muss erlaubt sein:
```
pass in on $lan from 10.10.0.0/16 to 10.10.0.0/16
```

#### 7. **Caddy läuft nicht**

**Check:**
```bash
service caddy status
ps aux | grep caddy
netstat -an | grep ':80\|:443'
```

**Fix:**
```bash
service caddy start
service caddy restart
```

#### 8. **Falsche Caddyfile-Syntax**

**Check:**
```bash
caddy validate --config /usr/local/etc/caddy/Caddyfile
```

**Häufige Fehler:**
- Fehlende Klammern `{}`
- Falsche Einrückung (bei manual_config)
- Kommas in JSON-ähnlicher Syntax

---

## Empfohlene Caddy-Konfiguration für RALF Services

### Minimale funktionierende Config:

```caddy
# /usr/local/etc/caddy/Caddyfile

{
    # Global Options
    admin off
    auto_https disable_redirects
}

gitea.otta.zone {
    reverse_proxy http://10.10.20.12:3000 {
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-For {remote_host}
        header_up X-Forwarded-Proto {scheme}
    }
}

semaphore.otta.zone {
    reverse_proxy http://10.10.100.15:3000 {
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-For {remote_host}
        header_up X-Forwarded-Proto {scheme}
    }
}

dashy.otta.zone {
    reverse_proxy http://10.10.40.11:4000 {
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-For {remote_host}
        header_up X-Forwarded-Proto {scheme}
    }
}

vault.otta.zone {
    reverse_proxy http://10.10.30.10:8080 {
        header_up X-Real-IP {remote_host}
        header_up X-Forwarded-For {remote_host}
        header_up X-Forwarded-Proto {scheme}
    }

    # Vaultwarden WebSocket Support
    reverse_proxy /notifications/hub http://10.10.30.10:3012 {
        header_up Connection {http.request.header.Connection}
        header_up Upgrade {http.request.header.Upgrade}
    }
}
```

### Mit automatischem HTTPS (Let's Encrypt):

```caddy
{
    email admin@otta.zone
}

gitea.otta.zone {
    reverse_proxy http://10.10.20.12:3000
}

semaphore.otta.zone {
    reverse_proxy http://10.10.100.15:3000
}

dashy.otta.zone {
    reverse_proxy http://10.10.40.11:4000
}

vault.otta.zone {
    reverse_proxy http://10.10.30.10:8080
    reverse_proxy /notifications/hub http://10.10.30.10:3012
}
```

---

## Debug-Workflow

1. **Caddy läuft?**
   ```bash
   service caddy status
   ```

2. **Config valide?**
   ```bash
   caddy validate --config /usr/local/etc/caddy/Caddyfile
   ```

3. **Backends erreichbar von OPNsense?**
   ```bash
   curl -v http://10.10.20.12:3000
   ```

4. **Caddy Logs checken:**
   ```bash
   tail -f /var/log/caddy/error.log
   tail -f /var/log/caddy/access.log
   ```

5. **Test mit curl (von OPNsense):**
   ```bash
   curl -v -H "Host: gitea.otta.zone" http://localhost:80
   curl -v -H "Host: gitea.otta.zone" https://localhost:443
   ```

6. **Von extern testen:**
   ```bash
   curl -v http://gitea.otta.zone
   ```

---

## OPNsense Caddy Plugin UI - Korrekte Einstellungen

### General Settings
- **Enable Caddy:** ✅
- **Auto HTTPS:** Optional (nur wenn Let's Encrypt gewünscht)

### Reverse Proxy → Domains
Für jede Domain:
- **Enabled:** ✅
- **Domain:** `gitea.otta.zone`
- **Port:** `443` (für HTTPS) oder `80` (für HTTP)
- **Protocol:** `https` (für external) oder `http`

### Reverse Proxy → Handlers
Für jeden Handler:
- **Enabled:** ✅
- **Domain:** Wähle Domain aus (z.B. gitea.otta.zone)
- **Path:** `/` (oder spezifisch)
- **Upstream Protocol:** `http` ← **WICHTIG!**
- **Upstream Host:** `10.10.20.12`
- **Upstream Port:** `3000`
- **TLS:** Deaktiviert (bei HTTP-Backend)
- **TLS Insecure Skip Verify:** Aktiviert (falls HTTPS-Backend ohne Cert)

---

## Quick Fix Checklist

- [ ] Caddy läuft: `service caddy status`
- [ ] Config valide: `caddy validate`
- [ ] Backends erreichbar: `curl http://10.10.20.12:3000`
- [ ] **Upstream Protocol ist `http://`** ← WICHTIGSTE FIX
- [ ] Ports 80/443 offen in Firewall (WAN)
- [ ] LAN → LAN Traffic erlaubt
- [ ] DNS für *.otta.zone zeigt auf externe IP
- [ ] Caddy Logs prüfen: `/var/log/caddy/`

---

## Support

Führe das Debug-Skript aus:
```bash
bash /tmp/caddy-debug-opnsense.sh
```

Oder direkt auf OPNsense:
```bash
ssh root@10.10.0.1 'bash -s' < /tmp/caddy-debug-opnsense.sh
```
