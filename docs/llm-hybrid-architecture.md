# LLM Hybrid-Architektur - Distributed Inference mit GPU-Support

## Architektur-Übersicht

```
┌─────────────────────────────────────────┐
│ n8n Workflow Orchestrator (CT 4012)    │
│ http://10.10.40.12:5678                 │
│                                         │
│ • Empfängt LLM Requests                 │
│ • Load Balancing über Nodes            │
│ • Routing nach Modell/Verfügbarkeit    │
│ • Monitoring & Logging                  │
└─────────────────────────────────────────┘
              │
              │ HTTP API Calls
              ▼
┌─────────────────────────────────────────┐
│          LLM Inference Nodes            │
│                                         │
│ ┌─────────────────────────────────────┐ │
│ │ GPU Node 1 (VM TBD)                 │ │
│ │ • NVIDIA/AMD GPU Passthrough        │ │
│ │ • Ollama/vLLM/TGI                   │ │
│ │ • Große Modelle (70B+)              │ │
│ └─────────────────────────────────────┘ │
│                                         │
│ ┌─────────────────────────────────────┐ │
│ │ GPU Node 2 (VM TBD)                 │ │
│ │ • Zusätzliche GPU-Kapazität         │ │
│ │ • Spezialisierte Modelle            │ │
│ └─────────────────────────────────────┘ │
│                                         │
│ ┌─────────────────────────────────────┐ │
│ │ CPU Node (optional)                 │ │
│ │ • Kleine Modelle (7B-)              │ │
│ │ • Fallback/Testing                  │ │
│ └─────────────────────────────────────┘ │
└─────────────────────────────────────────┘
```

## Komponenten

### 1. n8n Orchestrator (✅ Deployed)
- **Container:** CT 4012 @ 10.10.40.12:5678
- **Rolle:** API Gateway, Load Balancer, Workflow Engine
- **Vorteile:**
  - Visual Workflow Editor
  - Multi-Backend Support (Ollama, OpenAI, Anthropic, etc.)
  - Load Balancing & Routing
  - Error Handling & Retry Logic
  - Monitoring & Logging

### 2. GPU Inference Nodes (⏳ To Be Deployed)

#### Empfohlene VM-Specs pro Node:
```yaml
VM-Typ: QEMU/KVM (nicht LXC!)
CPU: 8-16 Cores
RAM: 32-64 GB (je nach Modellgröße)
Disk: 200 GB+ (für Modelle)
GPU: NVIDIA/AMD via PCIe Passthrough
OS: Ubuntu 24.04 Server
```

#### Inference-Engine Optionen:

**Option A: Ollama** (Einfach, gut für Start)
```bash
# Installation in GPU VM
curl -fsSL https://ollama.com/install.sh | sh

# GPU-Support automatisch erkannt
# API: http://<vm-ip>:11434
```

**Option B: vLLM** (Höchste Performance für Produktion)
```bash
# Installation in GPU VM
pip install vllm

# OpenAI-kompatible API
vllm serve meta-llama/Llama-3.1-70B-Instruct \
  --host 0.0.0.0 \
  --port 8000 \
  --gpu-memory-utilization 0.95
```

**Option C: Text Generation Inference (TGI)** (HuggingFace)
```bash
# Docker-basiert
docker run -p 8080:80 \
  --gpus all \
  ghcr.io/huggingface/text-generation-inference:latest \
  --model-id meta-llama/Llama-3.1-70B-Instruct
```

**Option D: exo** (Experimentell, für Multi-GPU Sharding)
- Verteilt ein Modell über mehrere GPUs/Nodes
- Gut für sehr große Modelle (>70B)
- Aktuell Build-Probleme (Rust-Version)

## GPU-Passthrough Setup

### Proxmox VE Konfiguration

#### 1. IOMMU aktivieren
```bash
# /etc/default/grub
GRUB_CMDLINE_LINUX_DEFAULT="quiet intel_iommu=on iommu=pt"
# Für AMD: amd_iommu=on

update-grub
reboot
```

#### 2. VFIO Module laden
```bash
# /etc/modules
vfio
vfio_iommu_type1
vfio_pci
vfio_virqfd
```

#### 3. GPU für Passthrough vorbereiten
```bash
# GPU IDs finden
lspci -nn | grep -i vga
lspci -nn | grep -i nvidia

# GPU für VFIO reservieren
# /etc/modprobe.d/vfio.conf
options vfio-pci ids=10de:2204,10de:1aef  # Beispiel NVIDIA IDs

update-initramfs -u
reboot
```

#### 4. GPU an VM binden
```bash
# Via Proxmox GUI oder CLI
qm set <VMID> -hostpci0 0000:01:00.0,pcie=1,x-vga=1

# Mit Audio (falls GPU hat Audio)
qm set <VMID> -hostpci0 0000:01:00.0,pcie=1,x-vga=1
```

### GPU VM Template erstellen

```bash
#!/usr/bin/env bash
# create-gpu-llm-node.sh

VMID="${1:-5001}"  # GPU Nodes: 5001, 5002, ...
HOSTNAME="llm-gpu-$(echo $VMID | tail -c 3)"
IP="10.10.90.${VMID#50}/16"  # z.B. 10.10.90.1

# VM erstellen
qm create "$VMID" \
  --name "$HOSTNAME" \
  --cores 12 \
  --memory 49152 \
  --net0 virtio,bridge=vmbr0 \
  --ostype l26 \
  --scsihw virtio-scsi-pci

# GPU Passthrough (Beispiel PCI-ID anpassen!)
qm set "$VMID" -hostpci0 0000:01:00.0,pcie=1

# Boot ISO
qm set "$VMID" -ide2 local:iso/ubuntu-24.04-server.iso,media=cdrom

# Disk
qm set "$VMID" -scsi0 local-lvm:200

echo "VM $VMID erstellt. Installation durchführen, dann:"
echo "1. NVIDIA/AMD Treiber installieren"
echo "2. CUDA/ROCm installieren"
echo "3. Inference Engine installieren (Ollama/vLLM/TGI)"
```

## n8n Integration

### Load Balancing Workflow

```json
{
  "name": "LLM Load Balancer",
  "nodes": [
    {
      "name": "Webhook Trigger",
      "type": "n8n-nodes-base.webhook",
      "parameters": {
        "path": "llm-infer"
      }
    },
    {
      "name": "Router",
      "type": "n8n-nodes-base.switch",
      "parameters": {
        "rules": [
          {
            "conditions": [
              {
                "field": "{{ $json.model }}",
                "operation": "contains",
                "value": "70b"
              }
            ],
            "output": "gpu-node-1"
          },
          {
            "conditions": [
              {
                "field": "{{ $json.model }}",
                "operation": "contains",
                "value": "7b"
              }
            ],
            "output": "cpu-node"
          }
        ]
      }
    },
    {
      "name": "GPU Node 1",
      "type": "n8n-nodes-base.httpRequest",
      "parameters": {
        "url": "http://10.10.90.1:11434/api/generate",
        "method": "POST"
      }
    },
    {
      "name": "GPU Node 2 (Fallback)",
      "type": "n8n-nodes-base.httpRequest",
      "parameters": {
        "url": "http://10.10.90.2:11434/api/generate",
        "method": "POST"
      }
    }
  ]
}
```

### Health Check & Auto-Failover

n8n kann automatisch prüfen, welche Nodes verfügbar sind:

```javascript
// Custom Function Node
const nodes = [
  { url: "http://10.10.90.1:11434", name: "GPU-1" },
  { url: "http://10.10.90.2:11434", name: "GPU-2" },
];

const availableNodes = [];

for (const node of nodes) {
  try {
    const response = await $http.get(`${node.url}/api/tags`);
    if (response.status === 200) {
      availableNodes.push(node);
    }
  } catch (error) {
    // Node offline, skip
  }
}

// Route to first available node
return { availableNodes };
```

## Modell-Verteilung

### Kleine Modelle (CPU ausreichend)
- **phi3:mini** (3.8B) - 2.2 GB
- **llama3.2:3b** - 2.0 GB
- **gemma2:2b** - 1.6 GB

### Mittlere Modelle (1x GPU, 16-24 GB VRAM)
- **llama3.1:8b** - 4.7 GB
- **mistral:7b** - 4.1 GB
- **qwen2.5:7b** - 4.7 GB

### Große Modelle (1x GPU, 40-80 GB VRAM)
- **llama3.1:70b** - 40 GB (Q4)
- **mixtral:8x7b** - 26 GB (Q4)
- **qwen2.5:72b** - 41 GB (Q4)

### Sehr große Modelle (Multi-GPU oder exo)
- **llama3.1:405b** - Requires model sharding
- **deepseek-v3** - Requires distributed inference

## Monitoring & Observability

### Metrics sammeln via n8n

```javascript
// Workflow Node: Collect Metrics
const metrics = {
  timestamp: new Date().toISOString(),
  node: "GPU-1",
  request_time_ms: $json.duration,
  tokens_per_second: $json.tokens / ($json.duration / 1000),
  model: $json.model,
  success: true
};

// Store in database oder InfluxDB
return { metrics };
```

### Grafana Dashboard
- Request Latency per Node
- Tokens per Second
- GPU Utilization (via nvidia-smi)
- Queue Depth
- Error Rate

## Migration Path

### Phase 1: Aktuell (✅)
- n8n Orchestrator deployed
- Dokumentation erstellt

### Phase 2: Erste GPU VM (⏳)
1. GPU Passthrough konfigurieren
2. GPU VM erstellen (VMID 5001)
3. Ollama + CUDA installieren
4. Modell laden (llama3.1:8b)
5. n8n anbinden

### Phase 3: Zweite GPU VM (⏳)
1. Zusätzliche GPU VM (VMID 5002)
2. Load Balancing in n8n
3. Auto-Failover konfigurieren

### Phase 4: Skalierung (⏳)
1. Weitere GPU Nodes nach Bedarf
2. Model Sharding mit exo (optional)
3. Kubernetes für Auto-Scaling (optional)

## Kostenoptimierung

### GPU-on-Demand
- GPU VMs nur bei Bedarf starten
- n8n kann VMs via Proxmox API starten
- Auto-Shutdown nach Inaktivität

### Modell-Caching
- Häufig genutzte Modelle permanent im RAM
- Selten genutzte: Download on demand

### Mixed Workloads
- Kleine Anfragen: CPU Nodes
- Große Anfragen: GPU Nodes
- Kosten-Routing in n8n

## Referenzen

- Ollama: https://ollama.com/
- vLLM: https://docs.vllm.ai/
- TGI: https://huggingface.co/docs/text-generation-inference/
- exo: https://github.com/exo-explore/exo
- n8n: https://docs.n8n.io/
- Proxmox GPU Passthrough: https://pve.proxmox.com/wiki/PCI_Passthrough
