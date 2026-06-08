"""Chainlit chat UI bridging the browser to the model-agnostic Pydantic AI agent.

Run:  chainlit run app.py -w   ->  http://localhost:8000
"""
from __future__ import annotations

import chainlit as cl

from agent import make_agent


@cl.on_chat_start
async def on_chat_start() -> None:
    cl.user_session.set("agent", make_agent())
    cl.user_session.set("history", [])
    await cl.Message(
        content="Hi! I can use Agent Skills and MCP tools, over a configurable "
        "model backend. Ask me anything."
    ).send()


@cl.on_message
async def on_message(message: cl.Message) -> None:
    agent = cl.user_session.get("agent")
    history = cl.user_session.get("history") or []

    answer = cl.Message(content="")
    # `async with agent` starts/stops the MCP servers for this turn.
    async with agent:
        async with agent.run_stream(message.content, message_history=history) as result:
            async for delta in result.stream_text(delta=True):
                await answer.stream_token(delta)
        cl.user_session.set("history", result.all_messages())
    await answer.send()
