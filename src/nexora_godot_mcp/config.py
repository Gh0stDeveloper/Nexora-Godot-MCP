from __future__ import annotations

from functools import lru_cache
from pathlib import Path
from typing import Literal
from urllib.parse import urlparse

from mcp.server.transport_security import TransportSecuritySettings
from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_prefix="NEXORA_GODOT_",
        extra="ignore",
        case_sensitive=False,
    )

    gateway_host: str = "127.0.0.1"
    gateway_port: int = Field(default=8775, ge=1, le=65535)
    auth_mode: Literal["local", "static", "oauth"] = "static"
    public_token: str = ""

    oauth_issuer_url: str = ""
    oauth_resource_url: str = ""
    oauth_introspection_url: str = ""
    oauth_client_id: str = ""
    oauth_client_secret: str = ""
    oauth_introspection_auth_method: Literal["basic", "client_secret_post"] = "basic"
    oauth_required_scopes: str = "godot:read,godot:write"
    oauth_expected_audience: str = ""
    oauth_validate_audience: bool = True
    oauth_timeout_seconds: float = Field(default=10.0, ge=1.0, le=60.0)

    allowed_hosts: str = "127.0.0.1:*,localhost:*,[::1]:*"
    allowed_origins: str = "http://127.0.0.1:*,http://localhost:*,http://[::1]:*"

    bridge_host: str = "127.0.0.1"
    bridge_port: int = Field(default=9877, ge=1024, le=65535)
    bridge_secret: str = ""
    request_timeout_seconds: float = Field(default=120.0, ge=1.0, le=1800.0)

    permission_profile: Literal["safe", "standard", "unrestricted"] = "standard"
    allow_editor_script: bool = False
    project_root: Path = Path("~/NexoraGodotWorkspace/MyGame")
    godot_binary: str = "godot"
    audit_log: Path = Path("./var/audit.jsonl")
    runtime_log_dir: Path = Path("./var/runs")
    log_level: str = "INFO"

    @property
    def resolved_project_root(self) -> Path:
        return self.project_root.expanduser().resolve()

    @staticmethod
    def _csv(value: str) -> list[str]:
        return [item.strip() for item in value.split(",") if item.strip()]

    def oauth_scope_list(self) -> list[str]:
        return self._csv(self.oauth_required_scopes)

    def transport_security(self) -> TransportSecuritySettings:
        return TransportSecuritySettings(
            enable_dns_rebinding_protection=True,
            allowed_hosts=self._csv(self.allowed_hosts),
            allowed_origins=self._csv(self.allowed_origins),
        )

    @staticmethod
    def _is_secure_or_loopback_url(value: str) -> bool:
        parsed = urlparse(value)
        if parsed.scheme == "https" and bool(parsed.netloc):
            return True
        return parsed.scheme == "http" and parsed.hostname in {
            "127.0.0.1",
            "localhost",
            "::1",
        }

    def validate_runtime(self) -> None:
        errors: list[str] = []
        if self.bridge_host not in {"127.0.0.1", "localhost", "::1"}:
            errors.append("NEXORA_GODOT_BRIDGE_HOST must stay on loopback")
        if len(self.bridge_secret) < 32:
            errors.append("NEXORA_GODOT_BRIDGE_SECRET must contain at least 32 characters")

        if self.auth_mode == "local":
            if self.gateway_host.lower() not in {"127.0.0.1", "localhost", "::1"}:
                errors.append(
                    "NEXORA_GODOT_AUTH_MODE=local requires a loopback gateway host"
                )
        elif self.auth_mode == "static":
            if len(self.public_token) < 32:
                errors.append(
                    "NEXORA_GODOT_PUBLIC_TOKEN must contain at least 32 characters"
                )
            if self.public_token and self.public_token == self.bridge_secret:
                errors.append("public token and bridge secret must be different")
        else:
            required = {
                "NEXORA_GODOT_OAUTH_ISSUER_URL": self.oauth_issuer_url,
                "NEXORA_GODOT_OAUTH_RESOURCE_URL": self.oauth_resource_url,
                "NEXORA_GODOT_OAUTH_INTROSPECTION_URL": self.oauth_introspection_url,
                "NEXORA_GODOT_OAUTH_CLIENT_ID": self.oauth_client_id,
                "NEXORA_GODOT_OAUTH_CLIENT_SECRET": self.oauth_client_secret,
            }
            for name, value in required.items():
                if not value:
                    errors.append(f"{name} is required when auth mode is oauth")
            for name, value in (
                ("NEXORA_GODOT_OAUTH_ISSUER_URL", self.oauth_issuer_url),
                ("NEXORA_GODOT_OAUTH_RESOURCE_URL", self.oauth_resource_url),
                (
                    "NEXORA_GODOT_OAUTH_INTROSPECTION_URL",
                    self.oauth_introspection_url,
                ),
            ):
                if value and not self._is_secure_or_loopback_url(value):
                    errors.append(
                        f"{name} must use HTTPS (HTTP is allowed only on loopback)"
                    )
            scopes = set(self.oauth_scope_list())
            if "godot:read" not in scopes:
                errors.append(
                    "NEXORA_GODOT_OAUTH_REQUIRED_SCOPES must include godot:read"
                )
            if self.permission_profile != "safe" and "godot:write" not in scopes:
                errors.append(
                    "NEXORA_GODOT_OAUTH_REQUIRED_SCOPES must include godot:write "
                    "unless the permission profile is safe"
                )

        if errors:
            raise RuntimeError("; ".join(errors))


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    return Settings()
