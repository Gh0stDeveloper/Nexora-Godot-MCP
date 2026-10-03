from __future__ import annotations

import asyncio
import json
from typing import Any

import pytest

from nexora_godot_mcp.bridge import GodotBridgeClient


@pytest.mark.asyncio
async def test_bridge_protocol_roundtrip() -> None:
    captured: dict[str, Any] = {}

    async def handle(
        reader: asyncio.StreamReader,
        writer: asyncio.StreamWriter,
    ) -> None:
        payload = json.loads((await reader.readline()).decode("utf-8"))
        captured.update(payload)
        writer.write(
            (
                json.dumps(
                    {
                        "request_id": payload["request_id"],
                        "ok": True,
                        "result": {"godot_version": "4.6.3"},
                    }
                )
                + "\n"
            ).encode("utf-8")
        )
        await writer.drain()
        writer.close()
        await writer.wait_closed()

    server = await asyncio.start_server(handle, "127.0.0.1", 0)
    socket = server.sockets[0]
    port = int(socket.getsockname()[1])
    async with server:
        client = GodotBridgeClient(
            host="127.0.0.1",
            port=port,
            secret="s" * 48,
            timeout_seconds=5,
        )
        response = await client.execute(
            operation="system.status",
            params={},
            request_id="req-1",
        )

    assert captured["operation"] == "system.status"
    assert captured["secret"] == "s" * 48
    assert response["result"]["godot_version"] == "4.6.3"
