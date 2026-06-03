# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

Two parallel subprojects live in this repo (see [`README.md`](./README.md) for a one-screen orientation):

1. **PII / PHI / PCI detection service** — a stateless FastAPI app routing requests through a Pydantic AI agent over LiteLLM, dispatching to either **GLiNER** (in-process token classification, custom LiteLLM provider under `gliner/`) or **Ollama** (out-of-process GGUF instruct LLMs, via LiteLLM's built-in `ollama_chat/`). Both backends return the same `list[Entity]` shape; the deterministic anonymizer is plain Python applied after the agent returns. Source: `app-gliner/`. **The `app-gliner/` directory is self-contained — it owns its Dockerfile, Makefile, requirements.txt, and Python source.**

2. **LiteLLM proxy stack** — `litellm` proxy + `postgres` (key / user metadata) + `redis` (cache), plus TLS certs and bootstrap SQL. Brought up as part of the dev compose stack. **Currently parallel to the PII service runtime path** — the FastAPI app talks to Ollama directly, not through this proxy.

Three CLAUDE.md files cover three layers and are intentionally non-overlapping:

- **This file** — repo-wide: compose stack, LiteLLM proxy, `config/`, host sizing, cross-cutting concerns.
- **[`app-gliner/CLAUDE.md`](./app-gliner/CLAUDE.md)** — the FastAPI service's build context (Dockerfile, Makefile, requirements, the entrypoint shim, why `privatize_this_config.py` sits one level up).
- **[`app-gliner/pii/CLAUDE.md`](./app-gliner/pii/CLAUDE.md)** — package internals: the agent / gliner_provider / anonymize call path, contextvar plumbing, model dispatch, editing checklist.

Dev environment is Docker Compose. Production targets Kubernetes with Helm manifests (when present under `helm/`). There is no test suite or test runner configured. `models-pii.ipynb` at the repo root is an experimentation notebook, not part of the runtime.

## Repository layout (top-level)

```
app-gliner/            FastAPI service — self-contained build context (see app-gliner/CLAUDE.md)
compose/               Compose fragments — see "Compose layout" below
config/                Files mounted into compose services (litellm_config.yaml, litellm-init-db.sql, certs/)
docker-compose.yml     Pure include: list — composes the fragments under compose/
Makefile               Compose orchestration (dc-up/down/restart, ollama-pull-models). Image build lives in app-gliner/Makefile.
.env / .env.template   Required by the LiteLLM proxy stack (see config/litellm_config.yaml)
README.md              Project orientation
```

## Common commands

The root `Makefile` is compose-only. Image build and Python env live in `app-gliner/` — see [`app-gliner/CLAUDE.md`](./app-gliner/CLAUDE.md).

```bash
# Dev stack (all active includes — see compose/) + pull Ollama PII models
make                                # = make dc-up; docker compose up -d
make ollama-pull-models             # pulls the GGUF LLMs listed in Makefile MODELS
make ollama-list-models             # docker exec ollama ollama list

# Stop / reset
make dc-down
make dc-restart                     # dc-clean (rm data-milvus, data-chroma) + dc-up

# Build / run the FastAPI image — see app-gliner/CLAUDE.md (cd app-gliner && make)
```

The compose stack requires `.env` populated from `.env.template` before `make` works (the `litellm` service uses `${OPENAI_API_KEY:?...}` guards that hard-fail on missing values).

**Note on `MODELS`**: the root `Makefile` `MODELS` variable currently holds generic Ollama models (`llama3.1:latest`, `gpt-oss:20b`). The PII-specific GGUF model list is present but commented out. Switch the active block to pull the PII LLMs (`hf.co/distil-labs/...`, etc.) before running `make ollama-pull-models`.

## Compose layout

`docker-compose.yml` is intentionally minimal — only an `include:` list. Every service, network, and volume lives in `compose/*.yml`. Active includes: `ollama`, `presidio-analyzer`, `presidio-anonymizer`, `chromadb`, `postgres`, `litellm`, `redis`, `open-webui`, `lobe-chat`.

| Fragment                    | Active? | Purpose                                                                                                         |
| --------------------------- | ------- | --------------------------------------------------------------------------------------------------------------- |
| `compose/volumes.yml`       | yes     | Named volumes: `postgres_data`, `redis_data`, `litellm_cache`, `litellm_logs`, `kong_db_data`. Loaded first.   |
| `compose/networks.yml`      | yes     | Bridge networks: `chroma-net`, `ollama-net`, `presidio-net`, `litellm_network` (custom subnet/iface).           |
| `compose/ollama.yml`        | yes     | Ollama LLM server (`:11434`). Serves the GGUF PII LLMs pulled by `make ollama-pull-models`.                    |
| `compose/presidio.yml`      | yes     | `presidio-analyzer` (`:5002`) + `presidio-anonymizer` (`:5001`). Auxiliary, not on the PII service path.       |
| `compose/chromadb.yml`      | yes     | ChromaDB vector store (`:8000`). Data in `compose/data-chroma/`.                                               |
| `compose/litellm.yml`       | yes     | LiteLLM proxy stack: `postgres` (SSL, hardened), `litellm` (`:4000`), `redis`. Mounts from `../config/`.       |
| `compose/open-webui.yml`    | yes     | Open WebUI (`:3000`), wired to Ollama. Requires `SERPAPI_API_KEY` for web-search.                              |
| `compose/lobe-chat.yml`     | yes     | LobeChat web UI (`:3210`), wired to `ollama`.                                                                   |
| `compose/milvus.yml`        | no      | Milvus vector DB stack (etcd + MinIO + Milvus). Commented out; data in `data-milvus/`.                         |
| `compose/kong-gateway.yml`  | no      | Kong Enterprise Gateway + dedicated postgres. Requires `KONG_LICENSE_DATA`, `KONG_PG_PASSWORD`. Commented out. |

Cross-fragment merging:
- **Named volumes/networks defined in `volumes.yml` / `networks.yml` resolve from any other fragment** — that's how `compose/litellm.yml` references `postgres_data`, `litellm_network`, etc. without re-declaring them.
- **Relative bind-mount paths in a fragment are resolved relative to that fragment's own directory.** `compose/litellm.yml` therefore mounts config and certs via `../config/...`. If you move a fragment, rewrite its bind paths.

Resource limits (`deploy.resources`) are sized for a **6 CPU / 16 GB RAM host**: memory limits sum to ~14.25 GB (~1.75 GB host headroom), CPU limits sum to 8 (acceptable oversubscription). Redis's `--maxmemory 1gb` is intentionally below its 1.5 GB cgroup limit to leave room for AOF rewrite forks. If you re-tune any service, keep these invariants in mind and re-check the totals.

## LiteLLM proxy

- **Config**: `config/litellm_config.yaml` (model list, router settings, security / cache / rate-limit policy). Mounted read-only at `/app/config.yaml`.
- **DB bootstrap**: `config/litellm-init-db.sql`, mounted into postgres's `docker-entrypoint-initdb.d/`.
- **TLS**: `config/certs/{server.crt,server.key}` mounted into postgres for SSL.
- **Required env vars** (the `litellm` service uses `${VAR:?...}` guards, so missing values hard-fail on `compose up`): `OPENAI_API_KEY`, `MISTRAL_API_KEY`. Plus the soft-defaulted but security-critical: `LITELLM_MASTER_KEY`, `LITELLM_SALT_KEY` (CANNOT be rotated after first use), `POSTGRES_PASSWORD`, `REDIS_PASSWORD`. Copy `.env.template` → `.env` and replace placeholders before first run.
- The proxy sits **parallel to** the PII FastAPI service. The FastAPI app talks to Ollama directly via `OLLAMA_API_BASE`; it does not route through the LiteLLM proxy. Wiring the FastAPI app through the proxy is a deliberate change (new model IDs, auth, base URL) — not a default.

## Key design details

- **`PII_LABELS`** (in `app-gliner/privatize_this_config.py`) drives both backends: GLiNER's zero-shot detection (via `labels_ctx`) and Ollama's system prompt. Adding a label here changes both at once.
- **Stateless FastAPI image** — see `app-gliner/CLAUDE.md` for build mechanics. The image bakes all four GLiNER models and runs `HF_HUB_OFFLINE=1` so `readOnlyRootFilesystem: true` is viable in Kubernetes.
- **Single uvicorn worker** — each worker would re-load 1–2 GB GLiNER model instances. Scale out horizontally with stateless replicas, not workers.
- **Ollama-only `MODELS` list in the root `Makefile`** — these are GGUF LLMs pulled into the Ollama container's volume. The four GLiNER HF model IDs are NOT pulled here (they aren't GGUF); they're baked into the FastAPI image at build time (and listed in both `app-gliner/Dockerfile` and `app-gliner/privatize_this_config.py:ModelName` — change one, change the other).

## Gotchas

- **For package internals** (call path, contextvar plumbing, `ollama/`→`ollama_chat/` rewrite, `PromptedOutput` requirement, overlap resolution, etc.), see `app-gliner/pii/CLAUDE.md`. **For build / Python env / Dockerfile**, see `app-gliner/CLAUDE.md`. This file deliberately does not duplicate either.
- **`pydantic-ai-slim[litellm]` import paths vary by version.** `app-gliner/pii/agent.py` tries `pydantic_ai.models.litellm.LiteLLMModel` first, then falls back to `pydantic_ai.models.openai.OpenAIModel` with a `LiteLLMProvider`. Pin or upgrade pydantic-ai rather than working around its current shape.
- **`SERPAPI_API_KEY`** must be set for Open-WebUI's web-search (Open-WebUI is currently active in the include list).
- **The litellm proxy comment header in `compose/litellm.yml` documents required env vars** — Compose's `${OPENAI_API_KEY:?...}` guards make the failure mode loud and fast if you forget.

## Production

- Helm manifests live in `helm/` (when present). Keep the deployment stateless: do not mount writable volumes onto the FastAPI image. The Ollama service has its own volume for GGUF weights and is the only stateful piece on the PII service path; postgres + redis are stateful when the LiteLLM proxy is deployed.
