# RALF Todo-Liste - Sortiert nach Installationsreihenfolge

## ✅ ABGESCHLOSSEN

### Phase 1.1 - PostgreSQL
- ✅ Container deployed (CT 2010, svc-postgres, 10.10.20.10:5432)
- ✅ PostgreSQL 16.11 installiert
- ✅ Datenbanken provisioniert (semaphore, gitea)
- ✅ UTF-8 Locale konfiguriert
- ✅ Snapshots erstellt (pre-install, post-install)

### Phase 1.2 - Semaphore  
- ✅ Container deployed (CT 10015, ops-semaphore, 10.10.100.15:3000)
- ✅ PostgreSQL-Backend konfiguriert
- ✅ Admin-User anlegen (kolja@homelab.lan)
- ✅ IaC Toolchain installiert (Ansible 2.20.2, OpenTofu 1.11.4, Terragrunt 0.99.1)
- ✅ UTF-8 Locale konfiguriert

### Phase 1.3 - Gitea (Container)
- ✅ Container deployed (CT 2012, svc-gitea, 10.10.20.12:3000)
- ✅ Gitea 1.22.6 installiert
- ✅ PostgreSQL-Backend konfiguriert
- ✅ UTF-8 Locale konfiguriert
- ✅ SSH auf Port 2222 konfiguriert

---

## 🔄 IN ARBEIT / NÄCHSTE SCHRITTE

### Phase 1.3 - Gitea (Setup) - PRIORITÄT 1
1. Web-UI Initial Setup durchführen (http://10.10.20.12:3000)
2. Admin-Accounts anlegen:
   - kolja (kolja@homelab.lan)
   - ralf (ralf@homelab.lan)
3. Organisation "RALF" erstellen
4. SSH-Keys für Semaphore hinterlegen

### Phase 1.2 - Semaphore (Konfiguration) - PRIORITÄT 2
5. Zweiten Admin-Account anlegen (ralf@homelab.lan)
6. SSH-Keypair generieren für Ansible
7. SSH-Key in Semaphore hinterlegen
8. Git-Repository hinzufügen (GitHub → später Gitea)
9. Ansible-Inventar hinzufügen (hosts.yml)
10. Umgebungsvariablen in Semaphore anlegen:
    - PROXMOX_API_URL
    - PROXMOX_API_TOKEN_ID
    - PROXMOX_API_TOKEN_SECRET
    - GITEA_DB_PASS
    - PG_SUPERUSER_PASS

### Phase 1.4 - Repository-Migration - PRIORITÄT 3
11. Repository auf Gitea erstellen (RALF/ralf)
12. Code von GitHub nach Gitea pushen
13. Semaphore Git-Remote auf Gitea umstellen
14. Lokale .git/config aktualisieren
15. GitHub-Repo als Backup/read-only

### Phase 1.5 - Terragrunt-Setup - PRIORITÄT 4
16. Root-Konfiguration erstellen (iac/terragrunt.hcl)
17. Stack-Dependencies definieren
18. Test: terragrunt run-all plan

---

## 📋 PHASE 2 - Sicherheit & Secrets

19. Vaultwarden deployen (CT 3010, svc-vaultwarden, 10.10.30.10:8080)
20. Admin-Accounts anlegen (kolja, ralf)
21. Alle bisherigen Credentials in Vaultwarden speichern
22. Secrets-Management-Workflow dokumentieren

---

## 📋 PHASE 3 - Mail-Server

23. Maddy Mail-Server deployen (CT 4010, svc-mail, 10.10.40.10)
24. Mail-Accounts anlegen:
    - kolja@homelab.lan
    - ralf@homelab.lan
25. SMTP/IMAP/Submission konfigurieren

---

## 📋 PHASE 4 - Reverse Proxy & DNS

26. OPNsense Caddy-Plugin via API konfigurieren
27. Reverse-Proxy-Regeln für alle Services
28. DNS-Einträge via Unbound API
29. TLS-Zertifikate (Let's Encrypt oder Self-Signed)

---

## 📋 PHASE 5 - Observability

30. Prometheus deployen (CT 8010, svc-prometheus, 10.10.80.10:9090)
31. Grafana deployen (CT 8012, svc-grafana, 10.10.80.12:3000)
32. Loki deployen (CT 8014, svc-loki, 10.10.80.14:3100)
33. node-exporter auf allen Containern
34. promtail auf allen Containern
35. Grafana-Dashboards importieren

---

## 📋 PHASE 6 - Plattform-Dienste

36. NetBox deployen (CT 4012, svc-netbox, 10.10.40.12:8000)
37. Snipe-IT deployen (CT 4014, svc-snipeit, 10.10.40.14:8080)
38. Alle Container in NetBox dokumentieren

---

## 📋 PHASE 7 - Automatisierung & KI

39. n8n deployen (CT 10020, ops-n8n, 10.10.100.20:5678)
40. n8n mit PostgreSQL verbinden
41. n8n Workflows erstellen:
    - Container-Health-Check
    - Backup-Trigger
    - Alert-Routing
    - Log-Aggregation
    - Credential-Rotation
    - KI-Assistant
    - Report-Generator

---

## 📋 PHASE 8 - Kommunikation (Matrix)

42. Synapse deployen (CT 4030, svc-synapse, 10.10.40.30)
43. Element deployen (CT 4032, svc-element, 10.10.40.32:8080)
44. Matrix-Accounts anlegen (kolja, ralf)
45. RALF-Bot erstellen mit Chat-Commands
46. n8n → Matrix Integration

---

## 📋 PHASE 9 - One-Liner Deploy

47. Master-Pipeline in Semaphore
48. Terragrunt run-all orchestrieren
49. deploy-all.yml Ansible-Playbook
50. Backup vor Deploy
51. Health-Checks nach Deploy
52. Rollback-Mechanismus

---

## 🔧 KONTINUIERLICH

- Backup-Automatisierung einrichten
- Monitoring erweitern
- Dokumentation aktualisieren
- Tests schreiben

