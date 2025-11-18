"""Environment variable grouping strategies."""

from __future__ import annotations

import logging
import os
import re
from typing import Any

logger = logging.getLogger(__name__)


def collect_indexed_groups(prefix: str) -> dict[int, dict[str, str]]:
    """Collect environment variables grouped by numeric suffix.

    Groups variables matching PREFIX_KEY_N pattern.

    Args:
        prefix: Variable prefix (e.g., "AZURE_OPENAI_")

    Returns:
        Dictionary mapping index to variable groups
    """
    groups: dict[int, dict[str, str]] = {}
    pattern = re.compile(rf"^{re.escape(prefix)}([A-Z0-9_]+)_(\d+)$")

    for env_key, env_value in os.environ.items():
        match = pattern.match(env_key)
        if match:
            variable_key = match.group(1)
            index = int(match.group(2))
            groups.setdefault(index, {})[variable_key] = env_value

    return dict(sorted(groups.items()))


def collect_sequential_groups(
    prefix: str, required_keys: list[str], optional_keys: list[str] | None = None
) -> dict[int, dict[str, str]]:
    """Collect environment variables sequentially until required keys are missing.

    Args:
        prefix: Variable prefix (e.g., "GATEWAY_CLIENT_")
        required_keys: Keys that must be present to continue
        optional_keys: Keys to collect if present (optional)

    Returns:
        Dictionary mapping index to variable groups
    """
    groups: dict[int, dict[str, str]] = {}
    index = 0
    all_keys = required_keys + (optional_keys or [])

    while True:
        group: dict[str, str] = {}
        has_all_required = True

        for key in all_keys:
            env_var = f"{prefix}{key}_{index}"
            value = os.environ.get(env_var)

            if value is not None:
                group[key] = value
            elif key in required_keys:
                has_all_required = False
                break

        if not has_all_required:
            break

        if group:
            groups[index] = group

        index += 1

    return groups


def apply_grouping_strategy(
    context: dict[str, Any],
    strategy_name: str,
    prefix: str,
    required_keys: list[str],
    optional_keys: list[str] | None = None,
) -> None:
    """Apply a custom grouping strategy and add results to context.

    Args:
        context: Context dictionary to update
        strategy_name: "indexed" or "sequential"
        prefix: Environment variable prefix
        required_keys: Required keys in each group
        optional_keys: Optional keys to collect if present
    """
    logger.debug(f"Applying {strategy_name} strategy for prefix: {prefix}")

    if strategy_name == "indexed":
        groups = collect_indexed_groups(prefix)
    elif strategy_name == "sequential":
        groups = collect_sequential_groups(prefix, required_keys, optional_keys)
    else:
        raise ValueError(f"Unknown strategy: {strategy_name}")

    # Always add the key to context, even if empty
    key = f"{prefix.lower().rstrip('_')}_groups"
    context[key] = list(groups.values()) if groups else []
    logger.debug(f"Added {len(groups)} group(s) to context under key: {key}")
