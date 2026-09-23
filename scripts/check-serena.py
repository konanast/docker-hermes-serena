#!/usr/bin/env python3
"""Real MCP initialize/list-tools probe; does not activate a project or call an LLM."""
import asyncio
from mcp import ClientSession
from mcp.client.streamable_http import streamable_http_client

async def check():
    async with streamable_http_client("http://127.0.0.1:9121/mcp") as (read, write, *_):
        async with ClientSession(read, write) as session:
            await session.initialize()
            tools = {t.name for t in (await session.list_tools()).tools}
            required = {"initial_instructions", "activate_project", "find_symbol", "get_symbols_overview"}
            assert required <= tools, f"Missing tools: {required - tools}"
            print("MCP ready: activation and symbol tools present")
asyncio.run(asyncio.wait_for(check(), 15))
