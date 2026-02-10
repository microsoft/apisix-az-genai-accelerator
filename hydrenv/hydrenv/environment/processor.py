"""Environment variable processing and normalization."""

from __future__ import annotations

import logging
import os
import re
from typing import Any

logger = logging.getLogger(__name__)

_INT_PATTERN = re.compile(r"^-?\d+$")
_FLOAT_PATTERN = re.compile(r"^-?\d+(?:\.\d+)?$")


def _parse_bool(value: str, *, default: bool = False) -> bool:
    value_lower = value.strip().lower()
    if value_lower in {"true", "1", "yes", "on"}:
        return True
    if value_lower in {"false", "0", "no", "off"}:
        return False
    return default


def coerce_value(value: str) -> bool | int | float | str:
    """Coerce a string value to its appropriate type.

    Args:
        value: String value to coerce

    Returns:
        Coerced value (bool, int, float, or str)
    """
    value_lower = value.lower()

    if value_lower in ("true", "false"):
        return value_lower == "true"

    if _INT_PATTERN.match(value):
        try:
            return int(value)
        except (ValueError, OverflowError):
            return value

    if _FLOAT_PATTERN.match(value):
        try:
            return float(value)
        except (ValueError, OverflowError):
            return value

    return value


def normalize_env() -> dict[str, Any]:
    """Normalize environment variables with lowercase keys and type coercion.

    Returns:
        Dictionary with normalized keys and coerced values
    """
    normalized: dict[str, Any] = {
        k.lower(): coerce_value(v) for k, v in os.environ.items()
    }

    # Add parsed list values
    normalized["ip_whitelist_parsed"] = parse_csv_list("IP_WHITELIST")
    normalized["ip_blacklist_parsed"] = parse_csv_list("IP_BLACKLIST")
    normalized["gateway_e2e_test_mode"] = _parse_bool(
        os.environ.get("GATEWAY_E2E_TEST_MODE", "false")
    )
    log_mode_raw = os.environ.get("GATEWAY_LOG_MODE", "prod")
    log_mode = log_mode_raw.strip().lower()
    normalized["gateway_log_mode"] = log_mode or "prod"

    return normalized


def parse_csv_list(env_var_name: str) -> list[str]:
    """Parse a comma-separated list from an environment variable.

    Args:
        env_var_name: Name of the environment variable

    Returns:
        List of stripped items
    """
    raw = os.environ.get(env_var_name, "")
    if not raw.strip():
        return []
    return [item.strip() for item in raw.split(",") if item.strip()]


def build_context() -> dict[str, Any]:
    """Build the base rendering context from environment variables.

    Returns:
        Context dictionary for template rendering (env vars only)
    """
    logger.debug("Building base rendering context from environment")

    context: dict[str, Any] = {"env": dict(os.environ)}
    context.update(normalize_env())

    return context
