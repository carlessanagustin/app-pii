# PII models in Docker

PII / PHI / PCI detection and anonymization service plus its surrounding dev stack. Docker Compose for development; Kubernetes + Helm in production.

## Terms

* Personally Identifiable Information (PII)
* Protected Health Information (PHI)
* Payment Card Industry (PCI)

## Subprojects

### 1. `docker-compose.yml` — dev stack

A pure `include:` list assembling fragments under `compose/` into a 9-service dev environment: **ollama** (GGUF LLM server), **presidio-analyzer** / **presidio-anonymizer**, **postgres** + **litellm** proxy + **redis** (the LiteLLM proxy stack), **lobe-chat**, **open-webui** + **playwright** (web UIs + web scraper). Config files (`litellm_config.yaml`, init SQL, TLS certs) live under `config/`. Resource limits are sized for a 6 CPU / 16 GB host.

Bring it up from the repo root:

```bash
cp .env.template .env       # fill OPENAI_API_KEY, MISTRAL_API_KEY, LITELLM_* secrets
make                        # docker compose up -d
make ollama-pull-models     # pull the GGUF PII LLMs into the ollama container
```

See [`CLAUDE.md`](./CLAUDE.md) for the full compose layout, env vars, and operational notes.

#### Service interconnections

```mermaid
graph LR
    subgraph host["Host (ports)"]
        H_OLLAMA[":11434"]
        H_LITELLM[":4000"]
        H_PRESIDIO_AN[":5002"]
        H_PRESIDIO_ANON[":5001"]
        H_LOBE[":3210"]
        H_CHROMA[":8000 💤"]
        H_OPENWEBUI[":8080"]
        H_MINIO_API[":9000 💤"]
        H_MINIO_UI[":9001 💤"]
        H_MILVUS[":19530 💤"]
        H_MILVUS_HTTP[":9091 💤"]
        H_ATTU[":3000 💤"]
    end

    subgraph ollama_net["ollama-net"]
        OLLAMA["ollama\nollama/ollama:0.24.0"]
        LOBE["lobe-chat\nlobehub/lobe-chat:1.143.3"]
    end

    subgraph owebui_net["owebui-net"]
        OPENWEBUI["open-webui\nghcr.io/open-webui/open-webui:v0.9.5"]
        PLAYWRIGHT["playwright\nmcr.microsoft.com/playwright:v1.60.0-noble"]
    end

    subgraph litellm_net["litellm-net"]
        LITELLM["litellm proxy\nghcr.io/berriai/litellm:main-latest"]
        POSTGRES["postgres\npostgres:18-alpine"]
        REDIS["redis\nredis:8-alpine"]
    end

    subgraph presidio_net["presidio-net"]
        P_ANALYZER["presidio-analyzer\n:3000 → host :5002"]
        P_ANON["presidio-anonymizer\n:3000 → host :5001"]
    end

    subgraph chroma_net["chroma-net"]
        CHROMA["chromadb 💤\nchromadb/chroma:1.5.9"]
    end

    subgraph milvus_net["milvus-net 💤"]
        ETCD["etcd 💤\nquay.io/coreos/etcd:v3.6.5"]
        MINIO["minio 💤\nminio/minio:RELEASE.2025-09-07T16-13-09Z"]
        MILVUS["milvus-standalone 💤\nmilvusdb/milvus:v2.6.2"]
        ATTU["milvus-attu 💤\nzilliz/attu:v2.6"]
    end

    subgraph volumes["Named volumes / bind mounts"]
        V_PG[("postgres_data")]
        V_REDIS[("redis_data")]
        V_LCACHE[("litellm_cache")]
        V_LLOGS[("litellm_logs")]
        V_OLLAMA[("./data-ollama")]
        V_CHROMA[("./data-chroma 💤")]
        V_OWUI[("./data-openwebui")]
        V_ETCD[("./data-milvus/etcd 💤")]
        V_MINIO[("./data-milvus/minio 💤")]
        V_MILVUS[("./data-milvus/milvus 💤")]
    end

    subgraph config["config/ (bind mounts, read-only)"]
        C_YAML["litellm_config.yaml"]
        C_SQL["litellm-init-db.sql"]
        C_CERTS["certs/"]
    end

    %% host port bindings (active)
    H_OLLAMA --> OLLAMA
    H_LITELLM --> LITELLM
    H_PRESIDIO_AN --> P_ANALYZER
    H_PRESIDIO_ANON --> P_ANON
    H_LOBE --> LOBE
    H_OPENWEBUI --> OPENWEBUI

    %% host port bindings (commented-out)
    H_CHROMA -.-> CHROMA
    H_MINIO_API -.-> MINIO
    H_MINIO_UI -.-> MINIO
    H_MILVUS -.-> MILVUS
    H_MILVUS_HTTP -.-> MILVUS
    H_ATTU -.-> ATTU

    %% service dependencies (active)
    LOBE -->|OLLAMA_PROXY_URL http://ollama:11434| OLLAMA
    LITELLM -->|DATABASE_URL postgres:5432| POSTGRES
    LITELLM -->|redis cache| REDIS
    LITELLM -->|presidio-net| P_ANALYZER
    LOBE -.->|presidio-net| P_ANALYZER
    OPENWEBUI -->|OLLAMA_BASE_URL http://ollama:11434| OLLAMA
    OPENWEBUI -->|presidio-net| P_ANALYZER
    OPENWEBUI -->|PLAYWRIGHT_WS_URL ws://playwright:3000| PLAYWRIGHT

    %% service dependencies (commented-out connections)
    OPENWEBUI -.->|CHROMA_HTTP_HOST chromadb:8000| CHROMA
    OPENWEBUI -.->|MILVUS_URI milvus-standalone:19530| MILVUS

    %% milvus-net internal dependencies
    MILVUS -.->|ETCD_ENDPOINTS etcd:2379| ETCD
    MILVUS -.->|MINIO_ADDRESS minio:9000| MINIO
    ATTU -.->|MILVUS_URL milvus-standalone:19530| MILVUS

    %% volume mounts (active)
    POSTGRES --- V_PG
    REDIS --- V_REDIS
    LITELLM --- V_LCACHE
    LITELLM --- V_LLOGS
    OLLAMA --- V_OLLAMA
    OPENWEBUI --- V_OWUI

    %% volume mounts (commented-out services)
    CHROMA -.- V_CHROMA
    ETCD -.- V_ETCD
    MINIO -.- V_MINIO
    MILVUS -.- V_MILVUS

    %% config mounts
    LITELLM --- C_YAML
    POSTGRES --- C_SQL
    POSTGRES --- C_CERTS

    classDef svc fill:#dbeafe,stroke:#2563eb,color:#1e3a5f
    classDef svc_off fill:#e5e7eb,stroke:#9ca3af,color:#6b7280,stroke-dasharray:4 3
    classDef vol fill:#fef9c3,stroke:#ca8a04,color:#713f12
    classDef vol_off fill:#f9fafb,stroke:#d1d5db,color:#9ca3af,stroke-dasharray:4 3
    classDef cfg fill:#dcfce7,stroke:#16a34a,color:#14532d
    classDef port fill:#f3f4f6,stroke:#6b7280,color:#111827
    classDef port_off fill:#f9fafb,stroke:#d1d5db,color:#9ca3af

    class OLLAMA,LOBE,OPENWEBUI,PLAYWRIGHT,LITELLM,POSTGRES,REDIS,P_ANALYZER,P_ANON svc
    class CHROMA,ETCD,MINIO,MILVUS,ATTU svc_off
    class V_PG,V_REDIS,V_LCACHE,V_LLOGS,V_OLLAMA,V_OWUI vol
    class V_CHROMA,V_ETCD,V_MINIO,V_MILVUS vol_off
    class C_YAML,C_SQL,C_CERTS cfg
    class H_OLLAMA,H_LITELLM,H_PRESIDIO_AN,H_PRESIDIO_ANON,H_LOBE,H_OPENWEBUI port
    class H_CHROMA,H_MINIO_API,H_MINIO_UI,H_MILVUS,H_MILVUS_HTTP,H_ATTU port_off
```

> **Legend:** 💤 = commented out in `docker-compose.yml` (dashed borders/lines). Pink node = one-shot init container (exits after completion). Uncomment the relevant fragment in `docker-compose.yml` to enable: `compose/chromadb.yml`, `compose/milvus.yml`.

### 2. `app/` — FastAPI PII service

A stateless FastAPI app whose endpoints route through a Pydantic AI agent over LiteLLM, dispatching to one of two backends: **GLiNER** (in-process token classification, baked into the image) or **Ollama** (out-of-process GGUF instruct LLMs, reached over the compose network). Both backends return the same `list[Entity]` shape; the deterministic anonymizer is plain Python applied after the agent returns.

The directory is self-contained — it owns its `Dockerfile`, `Makefile`, `requirements.txt`, and source. Build the image from `app/`:

```bash
cd app
make                # docker build -t pii:1.0 . (bakes all four GLiNER models)
```

See [`app/CLAUDE.md`](./app/CLAUDE.md) for the build context, and [`app/ppi/CLAUDE.md`](./app/ppi/CLAUDE.md) for the package internals (call path, backend dispatch, editing rules).

## Architecture

![architecture](./images/architecture.drawio.svg)

### Other architecture ideas

* Architecture 1

![architecture](./images/pii_model_k8s_architecture.svg)

* Architecture 2

![architecture](./images/kong_auth_model_routing_flow.svg)
