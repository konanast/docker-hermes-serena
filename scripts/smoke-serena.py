#!/usr/bin/env python3
"""Run explicitly: activates the bundled sample and starts its Python LSP."""
import asyncio
import re
from mcp import ClientSession
from mcp.client.streamable_http import streamable_http_client

async def main():
    async with streamable_http_client("http://serena:9121/mcp") as (read, write, *_):
        async with ClientSession(read, write) as session:
            await session.initialize()
            catalog = {t.name: t for t in (await session.list_tools()).tools}
            instructions = await session.call_tool("initial_instructions", {})
            text = "\n".join(getattr(c, "text", "") for c in instructions.content)
            match = re.search(r"session id is `([^`]+)`", text)
            for name, arguments in [
                ("activate_project", {"project": "/workspace/projects/my-project"}),
                ("get_symbols_overview", {"relative_path": "calculator.py", "depth": 1}),
                ("find_symbol", {"name_path_pattern": "Calculator/add", "relative_path": "calculator.py", "include_body": True}),
            ]:
                schema = getattr(catalog[name], "input_schema", None) or getattr(catalog[name], "inputSchema", {})
                if "session_id" in schema.get("required", []):
                    if not match:
                        raise RuntimeError("Serena requires a session ID but initial_instructions did not return one")
                    arguments["session_id"] = match.group(1)
                result = await session.call_tool(name, arguments)
                print(name, result.model_dump_json())
                if getattr(result, "is_error", getattr(result, "isError", False)):
                    raise RuntimeError(f"{name} failed")
asyncio.run(asyncio.wait_for(main(), 240))
