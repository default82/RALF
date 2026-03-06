# DNS Runbook - OPNsense Unbound (RALF)

Stand: 2026-03-06

## Ziel

Dieses Runbook beschreibt den Standardweg, um RALF-DNS-Eintraege in OPNsense Unbound zu uebernehmen und reproduzierbar zu verifizieren.

## Voraussetzungen

- OPNsense mit aktivem Unbound DNS
- Interne DNS-Zone gemaess `RALF_DNS_ZONE`
- RALF-Config vorhanden (`bootstrap/bootstrap.env`)

## 1) Artefakte erzeugen

```bash
bash bootstrap/dns-manifest.sh --config bootstrap/bootstrap.env
bash bootstrap/dns-unbound-opnsense.sh --config bootstrap/bootstrap.env
```

Erzeugte Dateien:

- `$RUNTIME_DIR/dns/records.hosts`
- `$RUNTIME_DIR/dns/zone.bind`
- `$RUNTIME_DIR/dns/unbound-host-overrides.csv`
- `$RUNTIME_DIR/dns/unbound-custom-options.conf`

## 2) In OPNsense uebernehmen

Zwei zulaessige Wege:

1. Host-Overrides in Unbound anhand `unbound-host-overrides.csv` anlegen
2. `unbound-custom-options.conf` in Unbound Custom Options eintragen

Anschliessend Unbound neu laden/restarten.

## 3) Verifikation gegen den Resolver

```bash
bash bootstrap/dns-verify.sh --config bootstrap/bootstrap.env
```

Ergebnisdatei:

- `$RUNTIME_DIR/dns/dns-verify.jsonl`

Gate-Empfehlung:

- `OK`: alle Pflicht-FQDNs liefern die erwartete Ziel-IP
- `Warnung`: teilweise korrekt, dokumentierte Restabweichungen
- `Blocker`: zentrale Dienste nicht aufloesbar oder falsche IPs

## 4) Betriebshinweise

- DNS-Aenderungen immer aus den RALF-Artefakten erzeugen, nicht manuell ad hoc.
- Bei IP- oder Dienstaenderungen zuerst `docs/IP-KONVENTION.md` aktualisieren.
- Nach jedem DNS-Update Verifikation erneut ausfuehren und Nachweis ablegen.
