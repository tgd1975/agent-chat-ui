"""Factory for the Claude Agent SDK client.

Ties together the three configurable bits:
  * model      -> a LiteLLM *route* (model_name), not a raw provider model
  * MCP server -> spawned over stdio from mcp/server.py
  * skills     -> discovered from .claude/skills/ (setting_sources=["project"])

The SDK talks the Anthropic Messages API; ANTHROPIC_BASE_URL (see .env) points it
at the LiteLLM proxy, so the actual model is chosen by routing, not code.
"""
from __future__ import annotations

import os
from pathlib import Path

from dotenv import load_dotenv
from claude_agent_sdk import ClaudeSDKClient, ClaudeAgentOptions

load_dotenv()

PROJECT_DIR = Path(__file__).parent.resolve()

SYSTEM_PROMPT = (
    "You are a helpful, friendly assistant in a chat console. "
    "Use available skills and MCP tools when they fit the user's request. "
    "Keep answers clear and concise."
)


def make_client() -> ClaudeSDKClient:
    """Build a configured (but not yet connected) Agent SDK client."""
    options = ClaudeAgentOptions(
        # AGENT_MODEL is a LiteLLM route name (claude-default / farm-gpt / copilot).
        model=os.environ.get("AGENT_MODEL", "claude-default"),
        system_prompt=SYSTEM_PROMPT,
        # --- MCP server wired in: SDK spawns mcp/server.py over stdio ---
        mcp_servers={
            "demo": {
                "type": "stdio",
                "command": "python",
                "args": [str(PROJECT_DIR / "mcp" / "server.py")],
            },
            # For an already-running HTTP MCP server instead, use:
            # "remote": {"type": "http", "url": "http://localhost:9000/mcp"},
        },
        # --- Skills: load .claude/skills/ from this project directory ---
        # setting_sources=["project"] makes the SDK read the project's .claude/
        # settings, which is where Agent Skills (SKILL.md) are discovered.
        cwd=str(PROJECT_DIR),
        setting_sources=["project"],
        # Allow the Skill tool plus this MCP server's tools.
        allowed_tools=["Skill", "mcp__demo__*"],
        # POC convenience. For real side effects, swap this for a can_use_tool
        # callback to add human-in-the-loop approval.
        permission_mode="acceptEdits",
    )
    return ClaudeSDKClient(options=options)
