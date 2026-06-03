# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Scope: this file covers the **`app-gliner/` directory** — the Python source root and Docker build context for the PII / PHI / PCI FastAPI service. Two adjacent CLAUDE.md files exist and are intentionally non-overlapping:

- **`../CLAUDE.md`** — repo-wide: compose stack, LiteLLM proxy, `config/`, networks/volumes, host sizing. Read it first for the overall picture.
- **`pii/CLAUDE.md`** — package internals: the agent / gliner_provider / anonymize call path, contextvar plumbing, model dispatch, editing checklist. Read it before touching anything inside `pii/`.

Don't duplicate either of those here.

## What `app-gliner/` is

`app-gliner/` is **self-contained**: it owns the FastAPI service's `Dockerfile`, `Makefile`, `requirements.txt`, the runtime source (`pii/` + entrypoint shim), and the shared config module. `docker build .` from this directory works because every `COPY` in the Dockerfile resolves against this directory as the build context. Nothing here depends on files at the repo root — the root tree handles compose orchestration, not the Python image build.

Layout:

```
app-gliner/
├── Dockerfile               Two-stage build: builder pre-downloads GLiNER models → runtime is air-gapped
├── Makefile                 Build/install shortcuts (.DEFAULT_GOAL = docker-build)
├── requirements.txt         FastAPI runtime deps (pinned-by-name, not by version)
├── privatize_this.py        Entrypoint shim: re-exports `app` from pii.api and `main` from pii.cli
├── privatize_this_config.py Shared constants — see "Why this isn't inside pii/" below
└── pii/                     The PII detection package (see pii/CLAUDE.md)
```

## Common commands

Run from `app-gliner/`:

```bash
# Image build (default goal). Bakes all four GLiNER models into the runtime image.
make                              # = make docker-build; docker build -t pii:1.0 .
make docker-push                  # docker push pii:1.0
make docker-run                   # docker run --rm -it pii:1.0 bash  (debug shell, not the app)
make docker-clean                 # docker rmi pii:1.0

# Local Python env (for development without Docker)
make py-venv                      # python3 -m venv .venv
make py-reqs                      # source .venv/bin/activate && pip install -r requirements.txt

# Run the FastAPI app locally (after py-reqs)
.venv/bin/uvicorn privatize_this:app --host 0.0.0.0 --port 8000

# Run the CLI
.venv/bin/python privatize_this.py --input "Jane Doe lives in Madrid"
.venv/bin/python privatize_this.py --input "..." --labels
.venv/bin/python privatize_this.py --input "..." --model gliner/urchade/gliner_multi_pii-v1 --threshold 0.5
.venv/bin/python privatize_this.py --input "..." --model ollama/hf.co/automated-analytics/qwen3-1.7b-pii-masking-gguf
```

There is no test suite or test runner configured here.

## Why `privatize_this_config.py` isn't inside `pii/`

It's the single source of truth for `ModelName` (Literal), `SUPPORTED_MODELS`, `GLINER_MODELS`, `OLLAMA_MODELS`, `DEFAULT_MODEL`, `DEFAULT_THRESHOLD`, `OLLAMA_API_BASE`, `PII_LABELS`, plus the helpers `strip_provider_prefix` and `normalize_model_id`. The `pii/` package imports it as `from privatize_this_config import ...` — i.e. it expects `app-gliner/` (or whatever directory contains both `pii/` and `privatize_this_config.py`) on `sys.path`. Keeping it one level up avoids a circular import dance and gives `privatize_this.py` a single neighbor to read constants from.

**Practical consequence**: when running locally, your CWD must be `app-gliner/` (or `PYTHONPATH=app-gliner`). The Dockerfile sets `WORKDIR /app` and copies both files into the same directory, so this works inside the image too.

**Editing rule**: add new model IDs / labels / defaults here, not inside `pii/`. Then make the corresponding change in `pii/agent.py` per the checklist in `pii/CLAUDE.md`.

## Docker build notes

- **Build context = `app-gliner/`.** Run `make docker-build` from this directory; `docker build -t pii:1.0 .` will then resolve `COPY requirements.txt`, `COPY privatize_this.py privatize_this_config.py ./`, and `COPY pii ./pii` against this directory.
- **Image bakes ~6–10 GB of GLiNER weights.** The builder stage pre-downloads all four GLiNER models into `/hf-cache`; the runtime stage sets `HF_HUB_OFFLINE=1` / `TRANSFORMERS_OFFLINE=1` so no HF network access is needed (and `readOnlyRootFilesystem: true` is viable). Adding/removing a GLiNER model means editing the hardcoded list in the Dockerfile's builder stage **and** `ModelName` in `privatize_this_config.py`.
- **Runtime ENV `OLLAMA_API_BASE=http://ollama:11434`** is the compose-network default. Override at run-time when Ollama lives elsewhere. The `ollama_chat` LiteLLM provider reads it from the process environment.
- **Single uvicorn worker is intentional** (CMD line in the Dockerfile). Each worker would re-load 1–2 GB GLiNER model instances; scale horizontally with stateless replicas instead.
- **No `.dockerignore` in this directory.** If you add one, mirror the whitelist style and keep `__pycache__` out — adding a `.dockerignore` at the build-context root is the only way to slim the image's COPY layers further.

## Gotchas

- **`requirements.txt` is intentionally unpinned by version** (top-level package names only). Pin versions before any production rebuild — silent upgrades of `pydantic-ai-slim`, `litellm`, or `gliner` will break the agent module loader path that `pii/agent.py` already guards against (see `pii/CLAUDE.md`).
- **The repo-root `Makefile` does compose orchestration; this `Makefile` does Python/Docker.** They don't share targets. Running `make` here builds the image; running `make` at the repo root brings the compose stack up.
- **The image is consumed by the compose stack or a Helm chart, not by this Makefile.** `make docker-run` opens a debug shell in the image — it does NOT start the FastAPI service (which would need ports published and an Ollama backend reachable). To run the service interactively, use `uvicorn` from `.venv/` or wire the image into a compose service.
