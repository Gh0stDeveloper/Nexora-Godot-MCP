from __future__ import annotations

import hmac
from collections.abc import Iterable
from typing import Any

from starlette.responses import JSONResponse
from starlette.types import ASGIApp, Receive, Scope, Send


def valid_bearer(authorization: str | None, expected_token: str) -> bool:
    if not expected_token or not authorization:
        return False
    scheme, separator, candidate = authorization.partition(" ")
    if separator != " " or scheme.lower() != "bearer" or not candidate:
        return False
    return hmac.compare_digest(candidate, expected_token)


class BearerTokenMiddleware:
    def __init__(
        self,
        app: ASGIApp,
        *,
        token: str,
        exempt_paths: Iterable[str] = ("/health",),
    ) -> None:
        self.app = app
        self.token = token
        self.exempt_paths = frozenset(exempt_paths)

    async def __call__(
        self,
        scope: Scope,
        receive: Receive,
        send: Send,
    ) -> None:
        if scope["type"] not in {"http", "websocket"}:
            await self.app(scope, receive, send)
            return

        path = str(scope.get("path", ""))
        if path in self.exempt_paths:
            await self.app(scope, receive, send)
            return

        headers = {
            key.decode("latin-1").lower(): value.decode("latin-1")
            for key, value in scope.get("headers", [])
        }
        if not self.token:
            response = JSONResponse(
                {"error": "gateway_auth_not_configured"},
                status_code=503,
            )
            await response(scope, receive, send)
            return

        if not valid_bearer(headers.get("authorization"), self.token):
            response = JSONResponse(
                {"error": "unauthorized"},
                status_code=401,
                headers={"WWW-Authenticate": "Bearer"},
            )
            await response(scope, receive, send)
            return

        await self.app(scope, receive, send)


def sanitize_for_audit(value: Any) -> Any:
    secret_keys = {
        "token",
        "secret",
        "authorization",
        "password",
        "api_key",
        "apikey",
        "code",
    }
    if isinstance(value, dict):
        return {
            key: ("***" if key.lower() in secret_keys else sanitize_for_audit(item))
            for key, item in value.items()
        }
    if isinstance(value, list):
        return [sanitize_for_audit(item) for item in value]
    return value
