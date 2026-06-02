# agent-chat-ui

A ChatGPT/Claude-style **web chat console in Python** that can use **Anthropic
Agent Skills** and your **MCP servers**, with a **configurable LLM backend**.

Three pieces:

| Layer | Tech | Role |
|---|---|---|
| **Web chat UI** | [Chainlit](https://chainlit.io) | Streaming ChatGPT-like front-end. |
| **Agent engine** | [Claude Agent SDK](https://docs.claude.com/en/api/agent-sdk/overview) | Runs the loop, loads **Skills** (`SKILL.md`), connects **MCP** servers. |
| **LLM router** | [LiteLLM proxy](https://docs.litellm.ai/docs/simple_proxy) | Exposes an Anthropic-compatible `/v1/messages` endpoint and routes to Claude / an LLM farm / Copilot / local models. |

## Quick start

```bash
pip install -r requirements.txt
cp .env.example .env        # fill in your keys
litellm --config litellm.config.yaml --port 4000   # terminal 1
chainlit run app.py -w                              # terminal 2 -> http://localhost:8000
```

The MCP server (`mcp/server.py`) is spawned automatically by the SDK over stdio.

## Switching models

Edit `litellm.config.yaml` to add routes, then set `AGENT_MODEL` in `.env` to a
route's `model_name` (`claude-default`, `farm-gpt`, `copilot`). Restart the app.

## Note on Skills

The exact knob for enabling Agent Skills in the Claude Agent SDK evolves between
versions. This scaffold uses `setting_sources=["project"]` plus allowing the
`Skill` tool, which is the current convention — pin the SDK version and verify
against its docs.

## License

MIT
