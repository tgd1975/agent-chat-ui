"""Chainlit chat UI bridging the browser to the Claude Agent SDK.

Run:  chainlit run app.py -w   ->  http://localhost:8000
"""
from __future__ import annotations

import chainlit as cl
from claude_agent_sdk import AssistantMessage, TextBlock, ToolUseBlock

from agent import make_client


@cl.on_chat_start
async def on_chat_start() -> None:
    client = make_client()
    await client.connect()
    cl.user_session.set("client", client)
    await cl.Message(
        content="Hi! I'm wired to your MCP server and can use skills. Ask me anything."
    ).send()


@cl.on_message
async def on_message(message: cl.Message) -> None:
    client = cl.user_session.get("client")
    await client.query(message.content)

    answer = cl.Message(content="")
    async for event in client.receive_response():
        if isinstance(event, AssistantMessage):
            for block in event.content:
                if isinstance(block, TextBlock):
                    await answer.stream_token(block.text)
                elif isinstance(block, ToolUseBlock):
                    # Surface tool / skill activity as a collapsible step.
                    async with cl.Step(name=block.name, type="tool") as step:
                        step.input = block.input
    await answer.send()


@cl.on_chat_end
async def on_chat_end() -> None:
    client = cl.user_session.get("client")
    if client is not None:
        await client.disconnect()
