from __future__ import annotations

from pathlib import Path

from pydantic import SecretStr
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="CONFIG_API_", case_sensitive=False)

    apisix_conf_path: Path = Path("/usr/local/apisix/conf/apisix.yaml")
    bind_host: str = "0.0.0.0"
    bind_port: int = 9000
    shared_secret: SecretStr | None = None
