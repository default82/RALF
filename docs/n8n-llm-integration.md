# n8n LLM Integration mit Ollama

## Überblick

n8n ist deployed und läuft auf **http://10.10.40.12:5678**

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
- **Status:** ✅ VM läuft, Ollama installiert
- **Problem:** Port 11434 ist "closed" - Ollama lauscht nur auf localhost
- **Lösung erforderlich:** Ollama-Konfiguration für externe Verbindungen

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

## Nächste Schritte

1. ✅ n8n deployed und getestet
2. ✅ Ollama VM erstellt und gestartet
3. ⏳ Ollama für externe Connections konfigurieren
4. ⏳ Mindestens ein LLM-Modell installieren (phi3:mini empfohlen)
5. ⏳ n8n Beispiel-Workflow erstellen und testen

## Referenzen

- n8n Docs: https://docs.n8n.io/
- Ollama API: https://github.com/ollama/ollama/blob/main/docs/api.md
- n8n LangChain: https://docs.n8n.io/integrations/builtin/cluster-nodes/root-nodes/n8n-nodes-langchain/
