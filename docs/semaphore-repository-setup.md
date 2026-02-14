# Semaphore Repository Setup

## Task #48: Git Repository zu Semaphore hinzufügen

### Voraussetzungen

✅ SSH-Key "ralf-ansible" in Semaphore Key Store hinzugefügt
✅ Git-Zugriff zu Gitea funktioniert
⏳ Public Key muss zu Gitea hinzugefügt werden
⏳ Repository muss in Semaphore konfiguriert werden

---

## Schritt 1: Public Key zu Gitea hinzufügen

### 1.1 Public Key kopieren

```bash
cat /root/.ssh/semaphore/ralf-ansible.pub
```

**Output:**
```
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN0xqiE0QHJckuvz8dHcTGCrXnwc8yvmok5c5PDwM7PJ ralf-ansible@semaphore
```

### 1.2 In Gitea hinzufügen

1. **Login:** http://10.10.20.12:3000 (kolja)
2. **User Settings** (Zahnrad oben rechts) → **SSH / GPG Keys**
3. **Add Key**
   - **Key Name:** `Semaphore Ansible`
   - **Content:** *(Public Key von oben einfügen)*
   - **Key Type:** `SSH Key`
4. **Add Key** klicken

### 1.3 Zugriff testen

```bash
ssh -i /root/.ssh/semaphore/ralf-ansible -p 2222 git@10.10.20.12
```

**Erwartete Ausgabe:**
```
Hi there, kolja! You've successfully authenticated with the key named Semaphore Ansible...
```

---

## Schritt 2: Repository in Semaphore hinzufügen

### 2.1 Project erstellen

1. **Login:** http://10.10.100.15:3000 (kolja oder ralf)
2. **Projects** → **+ New Project**
3. **Eingaben:**
   - **Project Name:** `RALF Infrastructure`
   - **Description:** `RALF Homelab Infrastructure Automation`
4. **Create** klicken

### 2.2 Repository hinzufügen

Nach dem Erstellen des Projects:

1. **Repositories** Tab
2. **+ New Repository**
3. **Eingaben:**
   - **Repository Name:** `ralf`
   - **URL:** `ssh://git@10.10.20.12:2222/RALF-Homelab/ralf.git`
   - **SSH Key:** `ralf-ansible` *(aus Dropdown auswählen)*
   - **Branch:** `main`
4. **Create** klicken

### 2.3 Repository-Verbindung testen

Nach dem Hinzufügen sollte Semaphore automatisch das Repository clonen.

**Status prüfen:**
- Green Checkmark ✅ = Repository erfolgreich gecloned
- Red X ❌ = Verbindungsfehler (SSH-Key oder URL prüfen)

---

## Schritt 3: Inventory konfigurieren

### 3.1 Inventory erstellen

1. Im Project **RALF Infrastructure**
2. **Inventory** Tab → **+ New Inventory**
3. **Eingaben:**
   - **Name:** `RALF Hosts`
   - **Type:** `File`
   - **Inventory:** *(Pfad zur Inventory-Datei im Repository)*
     ```
     iac/ansible/inventory/hosts.yml
     ```
4. **Create** klicken

### 3.2 Alternative: Static Inventory

Falls die File-basierte Inventory nicht funktioniert:

**Type:** `Static`

**Inventory YAML:**
```yaml
all:
  vars:
    ansible_user: root
    ansible_python_interpreter: /usr/bin/python3
    ansible_ssh_private_key_file: /root/.ssh/semaphore/ralf-ansible

  children:
    p1_bootstrap:
      hosts:
        svc-postgres:
          ansible_host: 10.10.20.10
        svc-gitea:
          ansible_host: 10.10.20.12
        ops-semaphore:
          ansible_host: 10.10.100.15

    p2_services:
      hosts:
        svc-mariadb:
          ansible_host: 10.10.20.11
        web-netbox:
          ansible_host: 10.10.40.30
        web-snipeit:
          ansible_host: 10.10.40.40
```

---

## Repository-Details

### URLs

| Type | URL |
|------|-----|
| **SSH** | `ssh://git@10.10.20.12:2222/RALF-Homelab/ralf.git` |
| **HTTP** | `http://10.10.20.12:3000/RALF-Homelab/ralf.git` |
| **Web** | http://10.10.20.12:3000/RALF-Homelab/ralf |

**Wichtig:** Für Semaphore SSH-URL verwenden (Port 2222)!

### Branches

- **main** - Production (stable)
- **develop** - Development
- **feature/*** - Feature Branches

---

## Troubleshooting

### Repository Clone fehlgeschlagen

**Fehler:** "Permission denied (publickey)"

**Lösung:**
```bash
# 1. Prüfe ob Public Key in Gitea ist
# Login → Settings → SSH Keys → sollte "Semaphore Ansible" Key sehen

# 2. Teste SSH manuell
ssh -i /root/.ssh/semaphore/ralf-ansible -p 2222 git@10.10.20.12

# 3. Prüfe ob Key in Semaphore korrekt ist
# Key Store → ralf-ansible → sollte kompletten Private Key enthalten
```

### Repository URL falsch

**Fehler:** "Could not resolve hostname"

**Problem:** Falsche URL oder falscher Port

**Korrekte URLs:**
- ✅ `ssh://git@10.10.20.12:2222/RALF-Homelab/ralf.git`
- ❌ `ssh://git@10.10.20.12/RALF-Homelab/ralf.git` (Port fehlt)
- ❌ `git@10.10.20.12:2222/RALF-Homelab/ralf.git` (ssh:// Prefix fehlt)

### SSH Host Key Verification Failed

**Fehler:** "Host key verification failed"

**Lösung:** SSH-Host-Key von Gitea akzeptieren
```bash
# Vom Semaphore-Container
pct exec 10015 -- ssh-keyscan -p 2222 10.10.20.12 >> /root/.ssh/known_hosts
```

---

## Verifikation

Nach erfolgreicher Konfiguration:

### 1. Repository Status prüfen

In Semaphore sollte das Repository grün markiert sein mit:
- ✅ Last commit message sichtbar
- ✅ Branch "main" erkannt
- ✅ Commit hash angezeigt

### 2. Test-Task erstellen

Erstelle einen einfachen Test-Task:

**Task Templates** → **+ New Template**
- **Name:** `Repository Test`
- **Playbook Filename:** `tests/bootstrap/smoke.sh`
- **Inventory:** `RALF Hosts`
- **Repository:** `ralf`

**Task ausführen** und prüfen ob Repository erfolgreich gecloned wird.

---

## Nächste Schritte

Nach erfolgreicher Repository-Konfiguration:

1. ✅ Repository in Semaphore verbunden
2. ⏳ Environment Variables konfigurieren (Task #49)
3. Task Templates erstellen für Ansible-Playbooks
4. Erste Deployment-Pipeline testen

---

## Security Notes

- SSH-Key hat nur Read-Zugriff auf Repository (kein Write)
- Key ist Ed25519 (modern und sicher)
- Gitea SSH läuft auf Non-Standard-Port 2222 (zusätzliche Security)
- Known_hosts wird automatisch verwaltet

---

## Reference

- **Semaphore Docs:** https://docs.ansible-semaphore.com/
- **Gitea SSH Setup:** http://10.10.20.12:3000/kolja/ralf/-/settings/keys
- **SSH Key Location:** `/root/.ssh/semaphore/ralf-ansible`
