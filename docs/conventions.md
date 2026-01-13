# Konventionen – RALF Homelab

Dieses Dokument definiert **verbindliche Konventionen** für Benennung, Struktur und Arbeitsweise im RALF‑Homelab.
Ziel ist **Konsistenz**, **Vorhersagbarkeit** und **Automatisierbarkeit**.

---

## 1. Benennung

### 1.1 Hostnames

Format:

```
<dienst>-<zone>
```

Beispiele:

* `semaphore-pg`
* `postgresql-fz`
* `gitea-fz`

### 1.2 Zonen-Suffixe

* `-pg` → Playground (Experimentierzone)
* `-fz` → Functional (stabiler Betrieb)

Zonen sind **logische Flags**, keine eigenen Netzwerke.

---

## 2. Container-IDs (CT-ID)

CT-IDs folgen der Semantik des IP-Bereichs (3. Oktett):

| IP-Bereich | Zweck                   | CT-ID‑Range |
| ---------: | ----------------------- | ----------: |
|         10 | Netzwerk-Infrastruktur  |   1000–1099 |
|         20 | Datenbanken             |   2000–2099 |
|         30 | Backup & Sicherheit     |   3000–3099 |
|         40 | Web & Admin             |   4000–4099 |
|         50 | Verzeichnisdienste      |   5000–5099 |
|         60 | Medien                  |   6000–6099 |
|         70 | Dokumentation & Wissen  |   7000–7099 |
|         80 | Monitoring & Logging    |   8000–8099 |
|         90 | KI & Datenverarbeitung  |   9000–9099 |
|        100 | Automatisierung         | 10000–10099 |
|        110 | Medien & Downloader     | 11000–11099 |
|        200 | Funktionale Sonderfälle | 20000–20099 |

---

## 3. IP-Adressierung

* Gesamtnetz: `10.10.0.0/16`
* Ausschließlich **statische IPs**
* Semantik über das **3. Oktett** (siehe `docs/network-baseline.md`)

Format:

```
10.10.<bereich>.<host>
```

---

## 4. Repository-Struktur

Verbindliche Ablageorte:

* `docs/` – Grundgesetze, Baselines, Konventionen
* `healthchecks/` – Gatekeeper‑Checks (bindend)
* `plans/` – Intents & Pläne
* `changes/` – Änderungen (Change‑Artefakte)
* `incidents/` – Störungen & Lessons Learned
* `services/` – Service‑Steckbriefe
* `iac/` – Infrastructure as Code (OpenTofu / Ansible)
* `pipelines/` – Runner‑Pipelines (Semaphore)
* `tests/` – Smoke‑ und Acceptance‑Tests

**Regel:** Keine Secrets im Repo.

---

## 5. IaC‑Regeln

* Infrastruktur wird mit **OpenTofu** beschrieben
* Konfiguration optional mit **Ansible**
* OpenTofu‑State:

  * initial lokal
  * später migrierbar (Backend)
* Jeder Stack MUSS enthalten:

  * `README.md`
  * Smoke‑Test
  * Rollback‑Strategie

---

## 6. Änderungen & Freigaben

* Keine Ausführung ohne:

  * grüne Network Health Checklist
  * genehmigten Plan
* Jede Änderung erzeugt:

  * ein Change‑Artefakt
  * aktualisierte Dokumentation
  * ein Testergebnis

---

## 7. Externe Erreichbarkeit

* Externe Veröffentlichung ausschließlich über **OPNsense / Caddy**
* Keine direkten Portfreigaben von Containern

---

## 8. Lern‑ & Betriebsprinzip

* Playground darf brechen
* Functional darf nicht brechen
* Erst verstehen, dann automatisieren
* RALF muss erklären können, **warum** etwas geschieht

---

## Änderungslog

* Initiale Konventionen definiert
