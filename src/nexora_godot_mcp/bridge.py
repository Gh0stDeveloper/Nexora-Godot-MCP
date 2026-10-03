from __future__ import annotations

import asyncio
import json
from typing import Any


class GodotBridgeError(RuntimeError):
    pass


class GodotBridgeClient:
    def __init__(
        self,
        *,
        host: str,
        port: int,
        secret: str,
        timeout_seconds: float,
    ) -> None:
        self.host = host
        self.port = port
        self.secret = secret
        self.timeout_seconds = timeout_seconds

    async def health(self) -> dict[str, Any]:
        return await self.execute(
            operation="system.status",
            params={},
            request_id="health",
            timeout_seconds=10.0,
        )

    async def execute(
        self,
        *,
        operation: str,
        params: dict[str, Any],
        request_id: str,
        timeout_seconds: float | None = None,
    ) -> dict[str, Any]:
        timeout = timeout_seconds or self.timeout_seconds
        try:
            reader, writer = await asyncio.wait_for(
                asyncio.open_connection(
                    self.host,
                    self.port,
                    limit=8 * 1024 * 1024,
                ),
                timeout=timeout,
            )
        except (OSError, TimeoutError) as exc:
            raise GodotBridgeError(f"Godot editor bridge unavailable: {exc}") from exc

        payload = {
            "request_id": request_id,
            "secret": self.secret,
            "operation": operation,
            "params": params,
        }
        try:
            writer.write(
                (json.dumps(payload, ensure_ascii=False) + "\n").encode("utf-8")
            )
            await asyncio.wait_for(writer.drain(), timeout=timeout)
            raw = await asyncio.wait_for(reader.readline(), timeout=timeout)
        except (OSError, TimeoutError) as exc:
            raise GodotBridgeError(f"Godot bridge request failed: {exc}") from exc
        finally:
            writer.close()
            try:
                await writer.wait_closed()
            except OSError:
                pass

        if not raw:
            raise GodotBridgeError("Godot bridge closed the connection without a response")
        try:
            body = json.loads(raw.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError) as exc:
            raise GodotBridgeError("Godot bridge returned invalid JSON") from exc
        if not isinstance(body, dict):
            raise GodotBridgeError("Godot bridge response must be a JSON object")
        if body.get("ok") is not True:
            raise GodotBridgeError(str(body.get("error", "unknown bridge error")))
        result = body.get("result", {})
        if not isinstance(result, dict):
            raise GodotBridgeError("Godot bridge result must be a JSON object")
        return {
            "request_id": str(body.get("request_id", request_id)),
            "result": result,
        }
