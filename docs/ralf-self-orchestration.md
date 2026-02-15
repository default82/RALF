# RALF Self-Orchestration

## Vision

Nach der Bootstrap-Phase kann RALF sich selbst orchestrieren und alle weiteren Services automatisch deployen.

## Bootstrap-Phase (Manuell, P1-Services)

```
1. PostgreSQL (CT 2010)  ← Database Backend
2. Gitea (CT 2012)       ← Git Repository (RALF Code)
3. Semaphore (CT 10015)  ← Ansible Orchestration
4. n8n (CT 4012)         ← Workflow Orchestration
5. exo (CT 4013)         ← AI Assistant
```

**Status:** ✅ **Alle P1-Services deployed und laufen!**

## Self-Orchestration Flow

### 1. RALF clont sich selbst

```bash
# Semaphore hat bereits Zugriff auf Gitea
# Repository: http://10.10.20.12:3000/ralf/ralf.git
# Credentials: Semaphore SSH Key in Gitea

# RALF Code ist in Semaphore verfügbar unter:
# /tmp/semaphore/<project-id>/<repository-id>/
```

### 2. n8n liest Service Catalog

```javascript
// n8n Workflow: Service Catalog Reader
const catalogPath = '/tmp/semaphore/ralf/catalog/projects/';
const fs = require('fs');

// Lese alle Service-Definitionen
const services = fs.readdirSync(catalogPath)
  .filter(f => f.endsWith('.yaml'))
  .map(f => {
    const yaml = require('js-yaml');
    return yaml.load(fs.readFileSync(catalogPath + f));
  });

// Filtere nach Priorität und Status
const toDeployP2 = services.filter(s =>
  s.priority === 'P2' &&
  s.status !== 'deployed'
);

return { services: toDeployP2 };
```

### 3. n8n erstellt Semaphore Tasks

Für jeden Service:

```javascript
// n8n HTTP Request Node zu Semaphore API
POST http://10.10.100.15:3000/api/project/<project-id>/tasks

{
  "template_id": <template-id>,
  "environment": {
    "SERVICE_NAME": "vaultwarden",
    "ANSIBLE_PLAYBOOK": "iac/ansible/playbooks/deploy-vaultwarden.yml",
    "INVENTORY": "iac/ansible/inventory/hosts.yml"
  },
  "message": "Auto-deployment via n8n orchestration"
}
```

### 4. Semaphore führt Ansible aus

```yaml
# Semaphore Task Template
name: "Deploy Service from Catalog"
playbook: "{{ ANSIBLE_PLAYBOOK }}"
inventory: "{{ INVENTORY }}"
environment: "production"

# Wird ausgeführt mit:
ansible-playbook \
  -i iac/ansible/inventory/hosts.yml \
  iac/ansible/playbooks/deploy-vaultwarden.yml
```

### 5. exo assistiert bei Entscheidungen

```python
# n8n ruft exo API auf für Entscheidungen
import requests

prompt = f"""
Service: {service_name}
Dependencies: {dependencies}
Current Status: {current_status}

Frage: Sollten wir diesen Service jetzt deployen?
- Sind alle Dependencies erfüllt?
- Gibt es Konflikte mit laufenden Services?
- Welche Deployment-Reihenfolge empfiehlst du?
"""

response = requests.post(
    "http://10.10.40.13:52415/v1/chat/completions",
    json={
        "model": "llama3.2:3b",
        "messages": [{"role": "user", "content": prompt}]
    }
)

decision = response.json()['choices'][0]['message']['content']
```

### 6. n8n überwacht Deployment

```javascript
// n8n Workflow: Monitor Deployment
const taskId = $json.task_id;

// Warte auf Completion
while (true) {
  const status = await $http.get(
    `http://10.10.100.15:3000/api/project/<project-id>/tasks/${taskId}`
  );

  if (status.status === 'success') {
    // Führe Smoke Test aus
    const smokeTest = await runSmokeTest(serviceName);
    if (smokeTest.passed) {
      await markServiceAsDeployed(serviceName);
      break;
    }
  }

  if (status.status === 'failed') {
    await notifyAdmin(serviceName, status.error);
    await askExoForFix(serviceName, status.error);
    break;
  }

  await sleep(10000); // Check every 10s
}
```

## Beispiel: Automatisches Vaultwarden Deployment

### Schritt 1: n8n Trigger (Webhook oder Scheduled)

```
Webhook: POST /ralf/deploy-next-service
→ n8n liest catalog/projects/*.yaml
→ Findet vaultwarden.yaml (P2, not deployed)
```

### Schritt 2: Dependency Check via exo

```
n8n → exo API:
"Vaultwarden requires PostgreSQL. Is CT 2010 healthy?"

exo → Response:
"Yes, PostgreSQL (CT 2010) is running and healthy.
Database vaultwarden exists. Proceed with deployment."
```

### Schritt 3: Semaphore Task erstellen

```
n8n → Semaphore API:
{
  "template": "deploy-service",
  "playbook": "iac/ansible/playbooks/deploy-vaultwarden.yml"
}

Semaphore → Ansible:
ansible-playbook iac/ansible/playbooks/deploy-vaultwarden.yml
```

### Schritt 4: Monitor & Verify

```
n8n polls Semaphore Task Status every 10s
→ Task complete (status: success)
→ n8n runs: bash tests/vaultwarden/smoke.sh
→ Smoke test: 7/10 PASS
→ n8n updates catalog/projects/vaultwarden.yaml:
  status: deployed
  deployed_at: 2026-02-15T11:00:00Z
```

### Schritt 5: Next Service

```
n8n → "Vaultwarden deployed successfully"
n8n → "Next service in queue: NetBox"
n8n → exo: "Should we deploy NetBox now?"
exo → "Yes, dependencies met. Proceed."
→ Repeat flow for NetBox
```

## n8n Master Orchestration Workflow

```json
{
  "name": "RALF Self-Orchestration Master",
  "nodes": [
    {
      "name": "Schedule Trigger",
      "type": "n8n-nodes-base.scheduleTrigger",
      "parameters": {
        "rule": {
          "interval": [{"field": "hours", "value": 1}]
        }
      }
    },
    {
      "name": "Read Service Catalog",
      "type": "n8n-nodes-base.executeCommand",
      "parameters": {
        "command": "cat /tmp/semaphore/ralf/catalog/projects/*.yaml | yq eval -"
      }
    },
    {
      "name": "Filter Undeployed P2 Services",
      "type": "n8n-nodes-base.function",
      "parameters": {
        "functionCode": "const services = $input.all();\nreturn services.filter(s => s.json.priority === 'P2' && s.json.status !== 'deployed');"
      }
    },
    {
      "name": "Ask exo for Deployment Order",
      "type": "n8n-nodes-base.httpRequest",
      "parameters": {
        "url": "http://10.10.40.13:52415/v1/chat/completions",
        "method": "POST",
        "body": {
          "model": "llama3.2:3b",
          "messages": [
            {
              "role": "user",
              "content": "Based on these services and their dependencies, what's the optimal deployment order?\n{{ $json }}"
            }
          ]
        }
      }
    },
    {
      "name": "For Each Service",
      "type": "n8n-nodes-base.splitInBatches"
    },
    {
      "name": "Check Dependencies via exo",
      "type": "n8n-nodes-base.httpRequest"
    },
    {
      "name": "Create Semaphore Task",
      "type": "n8n-nodes-base.httpRequest",
      "parameters": {
        "url": "http://10.10.100.15:3000/api/project/1/tasks",
        "method": "POST"
      }
    },
    {
      "name": "Monitor Task Progress",
      "type": "n8n-nodes-base.wait"
    },
    {
      "name": "Run Smoke Test",
      "type": "n8n-nodes-base.executeCommand"
    },
    {
      "name": "Update Catalog Status",
      "type": "n8n-nodes-base.executeCommand"
    }
  ]
}
```

## Vorteile der Self-Orchestration

### 1. Zero-Touch Deployment
- Nach Bootstrap: Keine manuelle Intervention nötig
- Services werden automatisch in optimaler Reihenfolge deployed
- Dependencies werden automatisch aufgelöst

### 2. AI-Assisted Decision Making
- exo analysiert Dependencies und Konflikte
- Empfiehlt Deployment-Reihenfolge
- Schlägt Fixes bei Fehlern vor

### 3. Visual Monitoring via n8n
- Dashboard zeigt Deployment-Status
- Workflow-Editor für Anpassungen
- Logs und Metriken zentral verfügbar

### 4. Self-Healing
- Smoke Tests nach jedem Deployment
- Bei Fehler: exo schlägt Fix vor
- Automatisches Retry mit Anpassungen

### 5. Incremental Rollout
- P2 Services zuerst
- Dann P3, P4 nach Bedarf
- Jederzeit manuell triggerbar

## Status & Next Steps

### ✅ Bootstrap Complete (P1)
- PostgreSQL deployed
- Gitea deployed (RALF Code verfügbar)
- Semaphore deployed (Ansible ready)
- n8n deployed (Workflows ready)
- exo deployed (AI Assistant starting)

### ⏳ Self-Orchestration Setup
1. **n8n Master Workflow erstellen**
   - Service Catalog Reader
   - Semaphore Task Creator
   - exo Integration
   - Smoke Test Runner

2. **Semaphore Templates konfigurieren**
   - Generic "Deploy Service" Template
   - Environment Variables aus Catalog

3. **exo API testen**
   - Dependency Resolution
   - Deployment Order Optimization
   - Error Analysis & Fix Suggestions

4. **Test mit P2 Service (z.B. Vaultwarden)**
   - Trigger: `curl -X POST http://10.10.40.12:5678/webhook/ralf-deploy`
   - Observe: n8n → exo → Semaphore → Ansible → Service
   - Verify: Smoke Test, Status Update

### 🚀 Danach: Fully Autonomous
- RALF deployed sich selbst
- Alle P2-P4 Services automatisch
- AI-gestützte Entscheidungen
- Self-healing bei Fehlern

## Architektur-Diagramm

```
┌─────────────────────────────────────────────────────────────┐
│                    RALF Self-Orchestration                  │
└─────────────────────────────────────────────────────────────┘

    ┌──────────────┐
    │   Trigger    │ (Webhook, Schedule, Manual)
    └──────┬───────┘
           │
           ▼
    ┌──────────────┐
    │   n8n        │ Read Service Catalog
    │ Orchestrator │ iac/catalog/projects/*.yaml
    └──────┬───────┘
           │
           ├─────────────────┐
           │                 │
           ▼                 ▼
    ┌──────────────┐  ┌──────────────┐
    │     exo      │  │  Semaphore   │
    │ AI Assistant │  │ Task Creator │
    └──────┬───────┘  └──────┬───────┘
           │                 │
           │ "Dependencies   │ POST /api/tasks
           │  OK? Deploy?"   │
           │                 │
           └────────┬────────┘
                    │
                    ▼
             ┌──────────────┐
             │  Semaphore   │ ansible-playbook
             │   Executor   │ deploy-<service>.yml
             └──────┬───────┘
                    │
                    ▼
             ┌──────────────┐
             │   Ansible    │ Configure Service
             │   Playbook   │ in LXC Container
             └──────┬───────┘
                    │
                    ▼
             ┌──────────────┐
             │  Smoke Test  │ tests/<service>/smoke.sh
             └──────┬───────┘
                    │
                    ▼
             ┌──────────────┐
             │ Update Catalog│ status: deployed
             │   Status     │ deployed_at: timestamp
             └──────────────┘
```

## Zusammenfassung

**RALF ist nach Bootstrap vollständig selbst-orchestrierend:**

1. ✅ **Git Repository** (Gitea) - RALF Code verfügbar
2. ✅ **Orchestrator** (n8n) - Workflow Engine
3. ✅ **Executor** (Semaphore) - Ansible Runner
4. ✅ **AI Assistant** (exo) - Entscheidungs-Unterstützung
5. ✅ **Service Catalog** - Alle Services definiert

**Nächster Schritt:** n8n Master Workflow erstellen → RALF deployed sich selbst! 🚀
