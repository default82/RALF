# Dashy Status Check Problem - Detaillierte Erklärung

## Das Problem

**Symptom:** Alle Services in Dashy zeigen Timeout oder "Unreachable"

**Root Cause:** Dashy führt Status-Checks **client-seitig** (im Browser) durch, nicht server-seitig!

### Wie Dashy Status-Checks funktionieren

```
┌─────────────────────────────────────────────────────────────┐
│                    User Browser                              │
│                                                              │
│  1. Lädt Dashy von http://10.10.40.11:4000        ✅ OK    │
│                                                              │
│  2. Dashy-JavaScript läuft im Browser                       │
│                                                              │
│  3. JavaScript führt HTTP-Requests zu Services aus:         │
│     ├─→ GET http://10.10.20.12:3000      ❌ TIMEOUT        │
│     ├─→ GET http://10.10.100.15:3000     ❌ TIMEOUT        │
│     └─→ GET http://10.10.40.11:4000      ❌ TIMEOUT        │
│                                                              │
│  Problem: Browser kann private IPs nicht erreichen          │
│           (außer User ist im gleichen Netzwerk)             │
└─────────────────────────────────────────────────────────────┘
```

### Warum funktioniert das nicht?

**Scenario 1: User von extern (z.B. Internet)**
- User öffnet Dashy über Port-Forward oder externe IP
- Browser lädt Dashy-UI erfolgreich
- JavaScript versucht `http://10.10.20.12:3000` zu erreichen
- **10.10.20.12 ist eine private IP** → Browser kann sie nicht erreichen
- Result: Timeout

**Scenario 2: User im gleichen Netzwerk (10.10.0.0/16)**
- User öffnet Dashy
- Browser kann alle 10.10.x.x IPs erreichen
- Status-Checks funktionieren ✅

**Scenario 3: CORS-Problem (auch im Netzwerk möglich)**
- Browser kann IPs erreichen
- Aber Backend-Services senden keine CORS-Header
- Browser blockiert Requests aus Sicherheitsgründen
- Result: Failed request

## Die Lösungen

### Option 1: Status-Checks deaktivieren ⭐ EINFACHSTE

**Vorteile:**
- Sofort funktionsfähig
- Keine weiteren Anpassungen nötig
- Dashy zeigt einfach nur Links

**Nachteile:**
- Keine visuellen Status-Indikatoren (grün/rot)
- Man sieht nicht auf einen Blick ob Services laufen

**Wann nutzen:**
- Quick-Fix gewünscht
- Status-Checks nicht kritisch
- Services sind stabil

**Implementierung:**
```yaml
appConfig:
  statusCheck: false  # Deaktiviert global
```

---

### Option 2: Interne URLs + Netzwerk-Zugriff ⭐ FÜR INTERNE NUTZER

**Vorteile:**
- Status-Checks funktionieren
- Keine externen Dependencies (kein Caddy nötig)
- Schnell (direkte Verbindung)

**Nachteile:**
- Funktioniert **nur** im internen Netzwerk
- Externe User sehen Timeouts
- Benötigt VPN für Remote-Zugriff

**Wann nutzen:**
- Alle User sind im gleichen Netzwerk
- VPN ist eingerichtet
- Keine externe Erreichbarkeit nötig

**Implementierung:**
```yaml
# Config bleibt wie sie ist
items:
  - title: Gitea
    url: http://10.10.20.12:3000
    statusCheck: true
```

**Zusätzlich nötig:** User muss im 10.10.0.0/16 Netzwerk sein

---

### Option 3: Externe URLs via Caddy ⭐ FÜR EXTERNE NUTZER

**Vorteile:**
- Status-Checks funktionieren von überall
- Sauber und professionell (echte Domains)
- HTTPS mit Let's Encrypt möglich
- Kein VPN nötig

**Nachteile:**
- Erfordert funktionierende Caddy-Config
- DNS muss konfiguriert sein (*.otta.zone)
- Mehr Komplexität

**Wann nutzen:**
- Services sollen von extern erreichbar sein
- Professionelles Setup gewünscht
- Caddy ist bereits eingerichtet

**Implementierung:**
```yaml
items:
  - title: Gitea
    url: https://gitea.otta.zone  # Externe Domain
    statusCheck: true

  - title: Semaphore
    url: https://semaphore.otta.zone
    statusCheck: true
```

**Zusätzlich nötig:**
1. Caddy Reverse Proxy konfiguriert (siehe `caddy-timeout-fixes.md`)
2. DNS A-Records für *.otta.zone
3. Ports 80/443 in Firewall offen

---

## Diagnose-Workflow

### 1. Ist der User im internen Netzwerk?

**Test von User-Browser:**
```
Öffne: http://10.10.20.12:3000
```

- ✅ Lädt → User ist im Netzwerk → Option 2 verwenden
- ❌ Timeout → User ist extern → Option 1 oder 3 verwenden

### 2. Funktioniert Caddy?

**Test:**
```bash
curl https://gitea.otta.zone
```

- ✅ HTTP 200 → Caddy funktioniert → Option 3 möglich
- ❌ Timeout/404 → Caddy muss gefixt werden → Option 1 oder 2

### 3. Sind DNS-Records konfiguriert?

**Test:**
```bash
dig gitea.otta.zone
nslookup gitea.otta.zone
```

- ✅ Zeigt externe IP → DNS OK
- ❌ NXDOMAIN → DNS konfigurieren

---

## Vergleich der Optionen

| Kriterium | Option 1: Keine Checks | Option 2: Intern | Option 3: Extern |
|-----------|------------------------|------------------|------------------|
| **Setup-Zeit** | 1 Minute | 1 Minute | 30+ Minuten |
| **Komplexität** | Niedrig | Niedrig | Hoch |
| **Von extern** | ✅ Ja (keine Checks) | ❌ Nein | ✅ Ja |
| **Status-Badges** | ❌ Nein | ✅ Ja | ✅ Ja |
| **VPN nötig** | ❌ Nein | ✅ Ja (für externe) | ❌ Nein |
| **Caddy nötig** | ❌ Nein | ❌ Nein | ✅ Ja |
| **DNS nötig** | ❌ Nein | ❌ Nein | ✅ Ja |
| **HTTPS möglich** | N/A | ❌ Nein | ✅ Ja |

---

## Empfehlung nach Use-Case

### Use-Case: "Ich bin immer im Homelab-Netzwerk"
→ **Option 2 (Interne URLs)**
- Config unverändert lassen
- Status-Checks funktionieren sofort

### Use-Case: "Ich greife manchmal von außen zu (ohne VPN)"
→ **Option 1 (Keine Checks)** oder **Option 3 (Extern)**
- Option 1: Quick-Fix, keine Status-Badges
- Option 3: Professionell, aber Caddy muss funktionieren

### Use-Case: "Ich habe VPN eingerichtet"
→ **Option 2 (Interne URLs)**
- VPN verbinden → Status-Checks funktionieren

### Use-Case: "Ich will ein Production-Setup"
→ **Option 3 (Externe URLs)**
- Alle Services über Caddy
- Let's Encrypt SSL
- Von überall erreichbar

---

## Fix-Skript ausführen

```bash
bash /tmp/fix-dashy-status-checks.sh
```

Das Skript fragt nach der gewünschten Option und konfiguriert Dashy automatisch.

---

## Technische Details

### Warum macht Dashy das client-seitig?

- **Performance:** Server muss nicht ständig Status-Checks durchführen
- **Realtime:** User sieht aktuellen Status in Echtzeit
- **Skalierbarkeit:** Keine Last auf Dashy-Server

### Alternative: Server-seitige Checks

Dashy unterstützt theoretisch auch server-seitige Checks via:
```yaml
appConfig:
  statusCheckUrl: /api/status-check
```

Aber:
- Erfordert Backend-API in Dashy
- Komplexer Setup
- Nicht standardmäßig aktiviert im Dev-Mode

---

## Häufige Fehler

### "Status-Checks funktionieren im Netzwerk auch nicht"

**Ursache:** CORS-Problem

**Lösung:** Backend-Services müssen CORS-Header senden:
```
Access-Control-Allow-Origin: *
```

Oder: Alle Services über gleiche Domain (Caddy)

### "Nach Config-Änderung sehe ich keine Unterschiede"

**Ursache:** Browser-Cache

**Lösung:** Hard-Reload
- Chrome/Firefox: `Ctrl+Shift+R`
- Safari: `Cmd+Shift+R`

### "Externe URLs funktionieren auch nicht"

**Ursache:** Caddy nicht korrekt konfiguriert

**Lösung:**
1. Prüfe Caddy: `scripts/opnsense/caddy-timeout-fixes.md`
2. Teste Caddy: `curl https://gitea.otta.zone`
3. Prüfe DNS: `dig gitea.otta.zone`

---

## Support

**Debug Dashy Status-Checks:**
```bash
# In Browser-Console (F12):
fetch('http://10.10.20.12:3000')
  .then(r => console.log('OK', r.status))
  .catch(e => console.error('FAIL', e))
```

**Debug vom Dashy-Container:**
```bash
pct exec 4001 -- curl -v http://10.10.20.12:3000
```
