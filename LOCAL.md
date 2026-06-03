# Run locally in Docker (GitHub Models backend)

Runs the whole stack on your machine and uses **GitHub Models** as the LLM —
i.e. GPT-4o(-mini) via your GitHub account, authenticated with a Personal
Access Token. No Azure, no quota requests.

```
Browser → http://localhost:8000
            └─ Chainlit → Claude Agent SDK → LiteLLM (:4000) → GitHub Models (gpt-4o-mini)
```

> Note: this is **GitHub Models** (a GitHub API product), not the Copilot editor
> subscription. Using your Copilot editor seat to power a standalone app is
> against GitHub's terms; GitHub Models is the supported, API-based equivalent.
> The free dev tier is rate-limited but fine for a feasibility test.

## 1. Get a token

1. GitHub → **Settings → Developer settings → Personal access tokens →
   Fine-grained tokens → Generate new token**.
2. Under **Permissions → Account permissions**, set **Models: Read-only**.
3. Generate and copy the token (`github_pat_…`).

## 2. Configure

```bash
cp .env.example .env
# edit .env and set:  GITHUB_API_KEY=github_pat_...
```

## 3. Run

```bash
docker compose up --build      # -> http://localhost:8000
```

The single container builds, starts LiteLLM + Chainlit, and you can chat.
Stop with `Ctrl+C`; remove with `docker compose down`.

## Notes

- **Model:** defaults to `gpt-4o-mini` (reliable on the free tier). For the bigger
  model, change the `github` route in `litellm.config.yaml` to `github/gpt-4o`.
- **Rate limits:** the free GitHub Models tier has low per-minute limits. If you
  see 429s, wait a moment or switch to `gpt-4o-mini`. It's enough to prove the
  pipeline (UI → Agent SDK → LiteLLM → model) works.
- **Other backends:** the same image supports Anthropic, an internal OpenAI-
  compatible LLM farm (`farm-gpt`), Azure (`copilot`), or a local model
  (`ollama`) — just change `AGENT_MODEL` and the matching keys in `.env` /
  `docker-compose.yml`.
