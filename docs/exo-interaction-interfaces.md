# exo Interaction Interfaces - Hybrid Setup

## Übersicht

RALF bietet **3 Wege** zur Interaktion mit exo:

```
┌─────────────────────────────────────────┐
│ 1. exo Web Dashboard                    │
│    http://10.10.40.13:52415             │
│    ✅ READY                              │
└─────────────────────────────────────────┘

┌─────────────────────────────────────────┐
│ 2. n8n Chat Proxy                       │
│    http://10.10.40.12:5678/webhook/chat │
│    ✅ READY (siehe Workflow unten)      │
└─────────────────────────────────────────┘

┌─────────────────────────────────────────┐
│ 3. Matrix/Element (Zukunft)             │
│    matrix://exo-bot                     │
│    ⏳ To Be Deployed                    │
└─────────────────────────────────────────┘
```

## 1. exo Web Dashboard (Primär)

### Zugriff
```bash
# Browser öffnen:
http://10.10.40.13:52415

# Oder via SSH Tunnel (von außerhalb):
ssh -L 52415:10.10.40.13:52415 root@proxmox-host
# Dann lokal: http://localhost:52415
```

### Features
- 🎨 **Cluster Management** - Nodes hinzufügen/entfernen
- 📊 **Model Downloads** - HuggingFace Models laden
- 💬 **Chat Interface** - Direkt mit Models chatten
- 📈 **Performance Metrics** - GPU/CPU Usage, Tokens/s
- 🔍 **Debug Mode** - Logs & System Info
- 🖥️ **Node Monitoring** - Status aller Cluster-Nodes

### Screenshots & Navigation
```
Dashboard
├── Home - Cluster Overview
├── Downloads - Model Management
│   ├── Download from HuggingFace
│   └── Local Models
├── Chat - Interactive Interface
│   ├── Model Selection
│   ├── Temperature/Top-p Settings
│   └── Chat History
└── Nodes - Cluster Management
    ├── Add Node
    ├── Node Status
    └── Performance Metrics
```

## 2. n8n Chat Proxy (API Gateway)

### n8n Workflow: exo Chat Proxy

Importiere diesen Workflow in n8n:

```json
{
  "name": "exo Chat Proxy",
  "nodes": [
    {
      "parameters": {
        "path": "chat",
        "responseMode": "lastNode",
        "options": {}
      },
      "id": "webhook-chat",
      "name": "Webhook Chat Trigger",
      "type": "n8n-nodes-base.webhook",
      "typeVersion": 1.1,
      "position": [250, 300]
    },
    {
      "parameters": {
        "method": "POST",
        "url": "http://10.10.40.13:52415/v1/chat/completions",
        "authentication": "none",
        "sendBody": true,
        "specifyBody": "json",
        "jsonBody": "={{ {\n  \"model\": $json.query.model || \"default\",\n  \"messages\": [\n    {\n      \"role\": \"user\",\n      \"content\": $json.query.message || $json.body.message\n    }\n  ],\n  \"stream\": false\n} }}",
        "options": {
          "timeout": 60000
        }
      },
      "id": "exo-request",
      "name": "exo API Request",
      "type": "n8n-nodes-base.httpRequest",
      "typeVersion": 4.2,
      "position": [470, 300]
    },
    {
      "parameters": {
        "respondWith": "json",
        "responseBody": "={{ {\n  \"response\": $json.choices[0].message.content,\n  \"model\": $json.model,\n  \"usage\": $json.usage,\n  \"created\": new Date().toISOString()\n} }}"
      },
      "id": "respond",
      "name": "Respond with Answer",
      "type": "n8n-nodes-base.respondToWebhook",
      "typeVersion": 1.1,
      "position": [690, 300]
    }
  ],
  "connections": {
    "Webhook Chat Trigger": {
      "main": [[{"node": "exo API Request", "type": "main", "index": 0}]]
    },
    "exo API Request": {
      "main": [[{"node": "Respond with Answer", "type": "main", "index": 0}]]
    }
  },
  "tags": [{"name": "exo"}, {"name": "chat"}]
}
```

### Usage

```bash
# Simple GET Request
curl "http://10.10.40.12:5678/webhook/chat?message=Erkläre%20was%20RALF%20ist"

# POST Request mit Model-Auswahl
curl -X POST http://10.10.40.12:5678/webhook/chat \
  -H "Content-Type: application/json" \
  -d '{
    "message": "Was ist self-orchestration?",
    "model": "llama3.2:3b"
  }'

# Response:
{
  "response": "Self-orchestration bedeutet...",
  "model": "default",
  "usage": {
    "prompt_tokens": 15,
    "completion_tokens": 42,
    "total_tokens": 57
  },
  "created": "2026-02-15T11:10:00Z"
}
```

### Mobile Access

Via Shortcuts App (iOS) oder Tasker (Android):

```yaml
# iOS Shortcut
Name: "Ask exo"
Action: Get contents of URL
  URL: http://10.10.40.12:5678/webhook/chat
  Method: POST
  Headers:
    Content-Type: application/json
  Body:
    message: [Ask for input]
Show: Result.response
```

## 3. Matrix Integration (Zukunft)

### Architektur

```
Element Client (Mobile/Web)
    ↓
Matrix Synapse Server (CT 11010)
    ↓
n8n Matrix Bot (Webhook)
    ↓
exo API (CT 4013)
    ↓
Response zurück
```

### Setup-Schritte (wenn gewünscht)

#### A. Matrix Synapse deployen

```bash
# Container erstellen
bash bootstrap/create-matrix.sh

# Container-ID: 11010
# IP: 10.10.110.10
# Port: 8008 (HTTP)
```

#### B. Matrix Bot registrieren

```bash
# In Matrix Container
pct exec 11010 -- register_new_matrix_user \
  -c /etc/matrix-synapse/homeserver.yaml \
  -u exo-bot \
  -p <bot-password> \
  --admin

# Bot Access Token erhalten
curl -X POST http://10.10.110.10:8008/_matrix/client/r0/login \
  -d '{
    "type": "m.login.password",
    "user": "exo-bot",
    "password": "<bot-password>"
  }'
```

#### C. n8n Matrix-exo Bridge Workflow

```json
{
  "name": "Matrix-exo Bridge",
  "nodes": [
    {
      "name": "Matrix Webhook",
      "type": "n8n-nodes-base.webhook",
      "parameters": {
        "path": "matrix-bot"
      }
    },
    {
      "name": "Filter Bot Messages",
      "type": "n8n-nodes-base.if",
      "parameters": {
        "conditions": {
          "string": [
            {
              "value1": "={{ $json.body.sender }}",
              "operation": "notEqual",
              "value2": "@exo-bot:homelab.lan"
            }
          ]
        }
      }
    },
    {
      "name": "exo API",
      "type": "n8n-nodes-base.httpRequest",
      "parameters": {
        "url": "http://10.10.40.13:52415/v1/chat/completions",
        "method": "POST",
        "body": {
          "messages": [
            {
              "role": "user",
              "content": "={{ $json.body.content.body }}"
            }
          ]
        }
      }
    },
    {
      "name": "Send Matrix Response",
      "type": "n8n-nodes-base.httpRequest",
      "parameters": {
        "url": "http://10.10.110.10:8008/_matrix/client/r0/rooms/{{ $json.body.room_id }}/send/m.room.message",
        "method": "POST",
        "headers": {
          "Authorization": "Bearer {{ $credentials.matrix_bot_token }}"
        },
        "body": {
          "msgtype": "m.text",
          "body": "={{ $json.choices[0].message.content }}"
        }
      }
    }
  ]
}
```

#### D. Matrix Synapse als Application Service registrieren

```yaml
# /etc/matrix-synapse/exo-bot.yaml
id: exo_bot
url: http://10.10.40.12:5678/webhook/matrix-bot
as_token: <generate-random-token>
hs_token: <generate-random-token>
sender_localpart: exo-bot
namespaces:
  users:
    - exclusive: true
      regex: "@exo-bot:homelab.lan"
  aliases: []
  rooms: []
```

### Element Client Setup

```yaml
# Element Web/Desktop/Mobile
Homeserver: http://10.10.110.10:8008
oder
Homeserver: https://matrix.homelab.lan (mit Reverse Proxy)

Username: dein-user
Password: dein-password

# Im Chat:
/invite @exo-bot:homelab.lan

# Dann einfach Nachrichten schreiben:
"Erkläre mir self-orchestration"
```

## Vergleich der Interfaces

| Feature | exo Dashboard | n8n Proxy | Matrix |
|---------|---------------|-----------|--------|
| **Setup** | ✅ Fertig | ✅ Fertig | ⏳ Requires deployment |
| **UI** | 🎨 Rich Web UI | 🔌 API only | 💬 Chat App |
| **Mobile** | 📱 Browser | 📱 API Call | 📱 Native App |
| **Multi-User** | ❌ Single | ✅ n8n Auth | ✅ Matrix Users |
| **History** | ✅ Dashboard | ❌ None | ✅ Chat History |
| **Notifications** | ❌ None | ⚠️ Webhook only | ✅ Push Notifications |
| **Model Mgmt** | ✅ Full Control | ❌ API only | ❌ API only |
| **Performance** | ⚡ Direct | ⚡ Direct | ⚠️ Extra hop |
| **Best For** | Admin/Power User | Automation/Scripts | Team Chat/Mobile |

## Empfohlene Nutzung

### Tägliche Nutzung
1. **exo Dashboard** - Für Model Management, Performance Monitoring
2. **n8n Proxy** - Für Automation (Semaphore-Integration, Scripts)

### Bei Bedarf später
3. **Matrix** - Wenn du Team-Chat oder mobile Push-Notifications willst

## Automation-Integration

### Semaphore nutzt exo via n8n

```yaml
# In Semaphore Task Template
- name: Ask exo for deployment order
  uri:
    url: http://10.10.40.12:5678/webhook/chat
    method: POST
    body_format: json
    body:
      message: "Given these services {{ services }}, what's the optimal deployment order considering dependencies?"
  register: exo_response

- debug:
    msg: "exo recommends: {{ exo_response.json.response }}"
```

### n8n Self-Orchestration nutzt exo

```javascript
// In n8n Master Workflow
const services = $input.all();
const prompt = `Services to deploy: ${JSON.stringify(services)}
Dependencies: ${JSON.stringify(dependencies)}

Question: What's the optimal deployment order?`;

const response = await $http.post(
  'http://10.10.40.13:52415/v1/chat/completions',
  {
    messages: [{ role: 'user', content: prompt }]
  }
);

return { deploymentOrder: response.choices[0].message.content };
```

## Quick Start Guide

### 1. exo Dashboard öffnen
```bash
# Im Browser:
http://10.10.40.13:52415

# Download ein Model (z.B. llama3.2:3b)
# Dashboard → Downloads → Enter Model Name → Download
```

### 2. n8n Chat Proxy testen
```bash
curl "http://10.10.40.12:5678/webhook/chat?message=Hello%20exo"
```

### 3. Für Matrix (später)
```bash
# Deploy Matrix
bash bootstrap/create-matrix.sh

# Setup Bot (siehe oben)
# Configure n8n Bridge
# Install Element Client
```

## Status

| Interface | Status | URL/Access |
|-----------|--------|------------|
| exo Dashboard | ✅ Running | http://10.10.40.13:52415 |
| n8n Chat Proxy | ✅ Ready (import workflow) | http://10.10.40.12:5678/webhook/chat |
| Matrix/Synapse | ⏳ Not deployed | To be deployed |

## Nächste Schritte

1. ✅ exo Dashboard öffnen und testen
2. ✅ n8n Chat Proxy Workflow importieren
3. ✅ Ersten Chat mit exo testen
4. ⏳ Matrix deployen (optional, bei Bedarf)

**🎉 Hybrid Setup Ready - Du hast jetzt 2 Interfaces zu exo!**
