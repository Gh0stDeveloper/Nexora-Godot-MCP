from __future__ import annotations

import logging
from typing import Any

import httpx
from mcp.server.auth.provider import AccessToken, TokenVerifier

from .config import Settings

logger = logging.getLogger("nexora_godot_mcp.auth")


def normalize_scopes(value: Any) -> list[str]:
    if isinstance(value, str):
        return [scope for scope in value.replace(",", " ").split() if scope]
    if isinstance(value, list):
        return [str(scope) for scope in value if str(scope)]
    return []


def normalize_audiences(value: Any) -> set[str]:
    if isinstance(value, str):
        return {value}
    if isinstance(value, list):
        return {str(item) for item in value if str(item)}
    return set()


class IntrospectionTokenVerifier(TokenVerifier):
    """Validate OAuth access tokens with an RFC 7662 introspection endpoint."""

    def __init__(self, settings: Settings) -> None:
        self.settings = settings

    async def verify_token(self, token: str) -> AccessToken | None:
        form: dict[str, str] = {
            "token": token,
            "token_type_hint": "access_token",
        }
        auth: httpx.BasicAuth | None = None
        if self.settings.oauth_introspection_auth_method == "basic":
            auth = httpx.BasicAuth(
                self.settings.oauth_client_id,
                self.settings.oauth_client_secret,
            )
        else:
            form["client_id"] = self.settings.oauth_client_id
            form["client_secret"] = self.settings.oauth_client_secret

        try:
            async with httpx.AsyncClient(
                timeout=self.settings.oauth_timeout_seconds
            ) as client:
                if auth is None:
                    response = await client.post(
                        self.settings.oauth_introspection_url,
                        data=form,
                        headers={"Accept": "application/json"},
                    )
                else:
                    response = await client.post(
                        self.settings.oauth_introspection_url,
                        data=form,
                        auth=auth,
                        headers={"Accept": "application/json"},
                    )
            response.raise_for_status()
            payload = response.json()
        except (httpx.HTTPError, ValueError) as exc:
            logger.warning("OAuth token introspection failed: %s", exc)
            return None

        if not isinstance(payload, dict) or payload.get("active") is not True:
            return None

        scopes = normalize_scopes(payload.get("scope")) or normalize_scopes(
            payload.get("scp")
        )

        if self.settings.oauth_validate_audience:
            expected = (
                self.settings.oauth_expected_audience
                or self.settings.oauth_resource_url
            )
            audiences = normalize_audiences(payload.get("aud"))
            audiences.update(normalize_audiences(payload.get("resource")))
            if expected not in audiences:
                logger.warning(
                    "OAuth token rejected because audience/resource does not match"
                )
                return None

        client_id = str(
            payload.get("client_id")
            or payload.get("azp")
            or payload.get("sub")
            or "unknown-client"
        )
        subject_raw = payload.get("sub")
        subject = str(subject_raw) if subject_raw is not None else None

        expires_at: int | None = None
        raw_exp = payload.get("exp")
        if isinstance(raw_exp, int):
            expires_at = raw_exp
        elif isinstance(raw_exp, str) and raw_exp.isdigit():
            expires_at = int(raw_exp)

        return AccessToken(
            token=token,
            client_id=client_id,
            scopes=scopes,
            expires_at=expires_at,
            resource=self.settings.oauth_resource_url,
            subject=subject,
            claims=payload,
        )
