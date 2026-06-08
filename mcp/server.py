"""A minimal example MCP server with a couple of demo tools.

Spawned automatically by the agent over stdio (see agent.py). Replace these
tools with your own, or point agent.py at a different/real MCP server instead.

Run standalone (for debugging):  python mcp/server.py
"""
from __future__ import annotations

import datetime as _dt

from mcp.server.fastmcp import FastMCP

mcp = FastMCP("demo")


@mcp.tool()
def current_time(timezone: str = "UTC") -> str:
    """Return the current date and time. `timezone` is informational only (UTC clock)."""
    now = _dt.datetime.now(_dt.timezone.utc)
    return f"{now.isoformat(timespec='seconds')} ({timezone})"


@mcp.tool()
def add(a: float, b: float) -> float:
    """Add two numbers and return the sum."""
    return a + b


@mcp.tool()
def word_count(text: str) -> int:
    """Count the number of whitespace-separated words in `text`."""
    return len(text.split())


if __name__ == "__main__":
    mcp.run()
