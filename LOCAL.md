# Run locally in Docker (no cloud, no API key)

This runs the whole stack on your machine with a **local LLM** (Ollama), so
there are no Azure/OpenAI keys and no quotas involved — ideal for a
tech-feasibility test.

```
Browser → http://localhost:8000
            └─ Chainlit → Claude Agent SDK → LiteLLM (:4000) → Ollama (llama3.2)
```

## Prerequisites

- Docker Desktop / Docker Engine with the Compose plugin
- ~4 GB free RAM and ~3 GB disk (for the model)

## Start

```bash
docker compose up --build
```

What happens:
1. `ollama` starts, `ollama-pull` downloads **llama3.2** once (a few minutes the
   first time), then the `app` image builds and boots LiteLLM + Chainlit.
2. Open **http://localhost:8000** and chat.

Stop with `Ctrl+C`; remove everything (including the model volume) with:

```bash
docker compose down -v
```

## Notes

- **First run is slow** (model download + image build). Later runs are fast; the
  model is cached in the `ollama` volume.
- **Smaller/faster model?** For low-RAM machines use `llama3.2:1b`. Change it in
  **two** places: the `ollama-pull` command in `docker-compose.yml` and the
  `ollama` route's `model:` in `litellm.config.yaml`, then `docker compose up --build`.
- **Tool/skill fidelity** on a small local model is limited — it's enough to prove
  the pipeline (UI → Agent SDK → LiteLLM → model) works end to end. For full
  Skill/MCP fidelity you'd point the same setup at a real Claude key by setting
  `AGENT_MODEL=claude-default` and `ANTHROPIC_API_KEY=...` instead of Ollama.
- **GPU:** the compose uses CPU by default (works everywhere). To use an NVIDIA
  GPU, add a `deploy.resources.reservations.devices` GPU block to the `ollama`
  service.
```
