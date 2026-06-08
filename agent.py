"""Model-agnostic agent engine, built on Pydantic AI.

This replaces the Claude-specific Agent SDK so the whole stack is no longer tied
to Claude. It implements the *open* Agent Skills standard (SKILL.md, via
pydantic-ai-skills) and connects MCP servers — both work with ANY tool-capable
model, not just Claude.

The model is selected by routing through the LiteLLM proxy (OpenAI-compatible
endpoint), so the underlying LLM (GitHub Models / Mistral / local / Claude / …)
is a config choice (AGENT_MODEL = a LiteLLM route), not a code change.
"""
from __future__ import annotations

import os
from pathlib import Path

from dotenv import load_dotenv
from pydantic_ai import Agent
from pydantic_ai.models.openai import OpenAIChatModel
from pydantic_ai.providers.openai import OpenAIProvider
from pydantic_ai.mcp import MCPToolset
from pydantic_ai_skills import SkillsToolset

load_dotenv()

PROJECT_DIR = Path(__file__).parent.resolve()

SYSTEM_PROMPT = (
    "You are a helpful, friendly assistant in a chat console. "
    "Use available skills and MCP tools when they fit the user's request. "
    "Keep answers clear and concise."
)


def make_agent() -> Agent:
    """Build a model-agnostic agent with Skills + MCP wired in."""
    # OpenAI-compatible endpoint — defaults to the LiteLLM proxy. AGENT_MODEL is
    # a LiteLLM route name (e.g. "github", "ollama", "claude-default").
    base_url = os.environ.get("LLM_BASE_URL", "http://localhost:4000/v1")
    api_key = (
        os.environ.get("LLM_API_KEY")
        or os.environ.get("ANTHROPIC_AUTH_TOKEN")
        or "sk-local-master"
    )
    model_name = os.environ.get("AGENT_MODEL", "github")

    model = OpenAIChatModel(
        model_name,
        provider=OpenAIProvider(base_url=base_url, api_key=api_key),
    )

    # --- Agent Skills: the OPEN SKILL.md standard, discovered from .claude/skills/ ---
    # Progressive disclosure (metadata first, full SKILL.md + scripts on demand)
    # is handled by the toolset; works with any tool-capable model.
    skills = SkillsToolset(directories=[str(PROJECT_DIR / ".claude" / "skills")])

    # --- MCP: spawn the demo server over stdio ---
    demo_mcp = MCPToolset(str(PROJECT_DIR / "mcp" / "server.py"))

    return Agent(
        model,
        instructions=SYSTEM_PROMPT,
        toolsets=[skills, demo_mcp],
    )
