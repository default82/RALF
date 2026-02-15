# n8n LLM Integration - Hybrid Architecture

## Überblick

n8n ist deployed und läuft auf **http://10.10.40.12:5678**

**Architektur:** Hybrid-Setup mit n8n als Orchestrator und separaten GPU-VMs für Inference
**Dokumentation:** Siehe `llm-hybrid-architecture.md` für vollständige Architektur-Details

## Ollama VM

- **VM-ID:** 4013
- **Hostname:** svc-ollama
- **IP:** 10.10.40.13
- **Port:** 11434 (Standard)
- **Specs:** 8 Cores, 16GB RAM

## Aktuelle Konfiguration

### n8n Container
- **Container:** CT 4012 (web-n8n)
- **IP:** 10.10.40.12
- **Port:** 5678
- **Datenbank:** PostgreSQL (n8n_user@10.10.20.10/n8n)
- **Status:** ✅ Deployed und läuft

### Ollama VM
- **Status:** ✅ VM läuft, Ollama installiert und konfiguriert
- **Externe Erreichbarkeit:** ✅ Port 11434 offen, lauscht auf 0.0.0.0
- **Installiertes Modell:** ✅ phi3:mini (2.2 GB, Q4_0 quantization)
- **Verified:** ✅ API-Tests erfolgreich, n8n kann Ollama erreichen

## Ollama für externe Verbindungen konfigurieren

Um Ollama für n8n verfügbar zu machen:

### Option 1: Systemd Environment (empfohlen)

```bash
# SSH in Ollama VM
ssh ubuntu@10.10.40.13

# Systemd override erstellen
sudo mkdir -p /etc/systemd/system/ollama.service.d/
sudo tee /etc/systemd/system/ollama.service.d/override.conf << EOF
[Service]
Environment="OLLAMA_HOST=0.0.0.0:11434"
EOF

# Service neu starten
sudo systemctl daemon-reload
sudo systemctl restart ollama

# Verify
sudo systemctl status ollama
curl http://localhost:11434/api/tags
```

### Option 2: Environment File

```bash
# Edit /etc/environment oder /etc/default/ollama
OLLAMA_HOST=0.0.0.0:11434

# Service neu starten
sudo systemctl restart ollama
```

## Modelle herunterladen

```bash
# SSH in Ollama VM
ssh ubuntu@10.10.40.13

# Kleine LLMs für Testing
ollama pull phi3:mini          # 2.3 GB - schnell, effizient
ollama pull llama3.2:3b        # 2.0 GB - Meta's kleines Modell
ollama pull mistral:7b-instruct # 4.1 GB - gutes Allround-Modell

# Liste installierte Modelle
ollama list
```

## n8n Workflow-Beispiele

### 1. HTTP Request Node zu Ollama

```json
{
  "nodes": [
    {
      "name": "Ollama HTTP Request",
      "type": "n8n-nodes-base.httpRequest",
      "position": [250, 300],
      "parameters": {
        "url": "http://10.10.40.13:11434/api/generate",
        "method": "POST",
        "jsonParameters": true,
        "options": {},
        "bodyParametersJson": "={\n  \"model\": \"phi3:mini\",\n  \"prompt\": \"{{ $json.prompt }}\",\n  \"stream\": false\n}"
      }
    }
  ]
}
```

### 2. Chat mit Ollama (Streaming)

```json
{
  "model": "llama3.2:3b",
  "messages": [
    {
      "role": "system",
      "content": "Du bist ein hilfreicher Assistent für RALF Homelab."
    },
    {
      "role": "user",
      "content": "Erkläre was n8n ist."
    }
  ],
  "stream": false
}
```

### 3. Code Generate Endpoint

```bash
curl -X POST http://10.10.40.13:11434/api/generate \
  -H "Content-Type: application/json" \
  -d '{
    "model": "phi3:mini",
    "prompt": "Write a Python function to calculate fibonacci",
    "stream": false
  }'
```

## n8n Community Nodes für LLM

n8n hat folgende Community Nodes für LLMs:

- **@n8n/n8n-nodes-langchain** - LangChain Integration (OpenAI-kompatibel)
- **n8n-nodes-ollama** - Direkte Ollama-Integration

Installation in n8n:

```bash
# Im n8n Container
pct exec 4012 -- su - n8n -c "cd /var/lib/n8n && npm install n8n-nodes-ollama"
pct exec 4012 -- systemctl restart n8n
```

## Testing

### 1. Ollama Health Check

```bash
curl http://10.10.40.13:11434/api/tags
```

Erwartete Antwort:
```json
{
  "models": [
    {
      "name": "phi3:mini",
      "size": 2300000000,
      ...
    }
  ]
}
```

### 2. Einfacher Generate Test

```bash
curl -X POST http://10.10.40.13:11434/api/generate \
  -H "Content-Type: application/json" \
  -d '{
    "model": "phi3:mini",
    "prompt": "Hello, world!",
    "stream": false
  }' | jq '.response'
```

### 3. n8n Webhook + Ollama

1. In n8n: Webhook Node erstellen (GET /ask?prompt=...)
2. HTTP Request Node zu Ollama hinzufügen
3. Response Node für Antwort
4. Testen: `curl "http://10.10.40.12:5678/webhook/ask?prompt=Hello"`

## Performance-Tipps

- **phi3:mini** (2.3GB): Beste Wahl für schnelle Antworten, geringe Latenz
- **llama3.2:3b** (2.0GB): Gutes Verhältnis Geschwindigkeit/Qualität
- **mistral:7b** (4.1GB): Höhere Qualität, langsamer

Mit 16GB RAM kann Ollama 1-2 Modelle gleichzeitig im Speicher halten.

## Firewall / Security

- Ollama läuft in einer separaten VM (nicht Container)
- Keine externe Exposition nötig - nur internes Netzwerk (10.10.x.x)
- n8n-Container kann direkt auf 10.10.40.13:11434 zugreifen

## Status (Completed ✅)

1. ✅ n8n deployed und getestet (CT 4012 @ 10.10.40.12:5678)
2. ✅ Ollama VM erstellt und gestartet (VM 4013 @ 10.10.40.13)
3. ✅ Ollama für externe Connections konfiguriert (systemd override)
4. ✅ phi3:mini LLM-Modell installiert (2.2 GB, 3.8B parameters)
5. ✅ n8n Beispiel-Workflow erstellt (siehe `n8n-ollama-workflow-example.json`)
6. ✅ API-Verbindung von n8n zu Ollama verifiziert

## Workflow importieren

Das Beispiel-Workflow JSON kann direkt in n8n importiert werden:

1. n8n öffnen: http://10.10.40.12:5678
2. Workflows → "Import from File" → `n8n-ollama-workflow-example.json`
3. Workflow aktivieren
4. Testen: `curl "http://10.10.40.12:5678/webhook/llm-test?prompt=Hello"`

## Referenzen

- n8n Docs: https://docs.n8n.io/
- Ollama API: https://github.com/ollama/ollama/blob/main/docs/api.md
- n8n LangChain: https://docs.n8n.io/integrations/builtin/cluster-nodes/root-nodes/n8n-nodes-langchain/

## Hybrid-Architektur für GPU-Support

Die aktuelle Implementierung nutzt eine **Hybrid-Architektur**:

```
n8n Orchestrator (CT 4012)
    │
    ├─ GPU Node 1 (VM, später)
    ├─ GPU Node 2 (VM, später)
    └─ CPU Node (optional)
```

**Vorteile:**
- ✅ n8n als flexibler API Gateway & Load Balancer
- ✅ GPU-VMs können inkrementell hinzugefügt werden
- ✅ Unterstützt Ollama, vLLM, TGI, OpenAI-APIs
- ✅ Visual Workflow Editor für komplexe Routing-Logik
- ✅ Health Checks & Auto-Failover
- ✅ Monitoring & Logging integriert

**Nächste Schritte für GPU-Support:**
1. GPU-Passthrough in Proxmox konfigurieren (siehe `llm-hybrid-architecture.md`)
2. GPU-VM erstellen mit Ollama/vLLM
3. n8n Load-Balancing Workflow erstellen
4. Weitere GPU-Nodes nach Bedarf hinzufügen

**Status:**
- ✅ n8n Orchestrator läuft
- ✅ Architektur dokumentiert
- ⏳ GPU-VMs für später geplant

Siehe `docs/llm-hybrid-architecture.md` für vollständige Implementierungs-Details.
