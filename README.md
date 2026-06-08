# agent-chat-ui

A ChatGPT-style **web chat console in Python** that uses **Agent Skills**
(the open `SKILL.md` standard) and your **MCP servers**, over a **configurable,
model-agnostic LLM backend**.

Three pieces:

| Layer | Tech | Role |
|---|---|---|
| **Web chat UI** | [Chainlit](https://chainlit.io) | Streaming ChatGPT-like front-end. |
| **Agent engine** | [Pydantic AI](https://ai.pydantic.dev) + [pydantic-ai-skills](https://pypi.org/project/pydantic-ai-skills/) | Model-agnostic loop; loads **Skills** (`SKILL.md`), connects **MCP** servers. Works with any model. |
| **LLM router** | [LiteLLM proxy](https://docs.litellm.ai/docs/simple_proxy) | OpenAI-compatible endpoint; routes to GitHub Models / Mistral / Claude / Azure / local. |

## Quick start

```bash
pip install -r requirements.txt
cp .env.example .env        # fill in your keys
litellm --config litellm.config.yaml --port 4000   # terminal 1
chainlit run app.py -w                              # terminal 2 -> http://localhost:8000
```

The MCP server (`mcp/server.py`) is spawned automatically over stdio.

## Run locally in Docker (GitHub Models)

The fastest way to try the whole stack — uses **GitHub Models** (GPT-4o-mini via
your GitHub token), no Azure/quota. See **[LOCAL.md](LOCAL.md)**:

```bash
cp .env.example .env           # set GITHUB_API_KEY=github_pat_...
docker compose up --build      # -> http://localhost:8000
```

## Run in the cloud (Azure)

To host the UI on a public HTTPS URL with **Azure OpenAI** behind the LiteLLM
proxy, see **[DEPLOY-azure.md](DEPLOY-azure.md)** — it containerizes the stack
(`Dockerfile` + `start.sh`) and deploys it to Azure Container Apps.

## Switching models

Edit `litellm.config.yaml` to add routes, then set `AGENT_MODEL` in `.env` to a
route's `model_name` (`github`, `ollama`, `claude-default`, `farm-gpt`,
`copilot`). Restart the app. The agent talks to LiteLLM's OpenAI-compatible
endpoint (`LLM_BASE_URL`), so the model is purely a routing choice.

## Note on Skills

Agent Skills (`SKILL.md`) are an **open standard** (published Dec 2025), so they
are **not tied to Claude** — they work with any tool-capable model. This project
loads them via [pydantic-ai-skills](https://pypi.org/project/pydantic-ai-skills/)
(progressive disclosure: metadata first, full `SKILL.md` + scripts on demand)
from `.claude/skills/`. The same skill files are portable to Claude Code, OpenAI
Codex, Mistral, OpenCode, and other runtimes that adopt the standard.

## License

MIT
