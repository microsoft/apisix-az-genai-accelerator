"""Environment variable grouping strategies."""

from __future__ import annotations

import logging
import os
import re
from typing import Any, Iterable

logger = logging.getLogger(__name__)


class GroupingValidationError(ValueError):
    """Raised when grouped environment variables fail validation."""


def _collect_index_map(prefix: str, keys: Iterable[str]) -> dict[int, set[str]]:
    """Collect indices that have any of the provided keys.

    Args:
        prefix: Variable prefix (e.g., "AZURE_OPENAI_")
        keys: Allowed key names for the grouping

    Returns:
        Mapping of index to set of key names present for that index.
    """
    key_pattern = "|".join(map(re.escape, keys))
    pattern = re.compile(rf"^{re.escape(prefix)}({key_pattern})_(\d+)$")

    indices: dict[int, set[str]] = {}
    for env_key in os.environ:
        match = pattern.match(env_key)
        if not match:
            continue
        key_name, index_str = match.groups()
        index = int(index_str)
        indices.setdefault(index, set()).add(key_name)

    return dict(sorted(indices.items()))


def _is_truthy_env_var(env_var: str) -> bool:
    """Return True when the environment variable value is truthy."""

    value = os.environ.get(env_var)
    if value is None:
        return False
    value_lower = value.strip().lower()
    return value_lower in {"true", "1", "yes", "on"}


def collect_indexed_groups(
    prefix: str, required_keys: list[str], optional_keys: list[str] | None = None
) -> dict[int, dict[str, str]]:
    """Collect environment variables grouped by numeric suffix.

    Groups variables matching PREFIX_KEY_N pattern limited to allowed keys.

    Args:
        prefix: Variable prefix (e.g., "AZURE_OPENAI_")
        required_keys: Keys that must be present in each group
        optional_keys: Keys collected if present

    Returns:
        Dictionary mapping index to variable groups
    """
    groups: dict[int, dict[str, str]] = {}
    allowed_keys = set(required_keys + (optional_keys or []))
    key_pattern = "|".join(map(re.escape, allowed_keys))
    pattern = re.compile(rf"^{re.escape(prefix)}({key_pattern})_(\d+)$")

    for env_key, env_value in os.environ.items():
        match = pattern.match(env_key)
        if not match:
            continue
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

        for key in all_keys:
            env_var = f"{prefix}{key}_{index}"
            value = os.environ.get(env_var)

            if value is not None:
                group[key] = value
            elif key in required_keys:
                # Sequential groups stop at first missing required key.
                return groups

        if group:
            groups[index] = group

        index += 1

    return groups


def _validate_indexed_groups(
    groups: dict[int, dict[str, str]], prefix: str, required_keys: list[str]
) -> None:
    """Ensure every indexed group has all required keys."""

    for index, values in groups.items():
        missing_required = [key for key in required_keys if key not in values]
        if missing_required:
            present = ", ".join(sorted(values)) or "none"
            missing = ", ".join(missing_required)
            raise GroupingValidationError(
                f"Indexed group '{prefix}' index {index} is missing required key(s): {missing}. "
                f"Present keys: {present}."
            )


def _validate_sequential_groups(
    prefix: str, required_keys: list[str], optional_keys: list[str] | None = None
) -> None:
    """Validate contiguity and required keys for sequential groups."""

    all_keys = required_keys + (optional_keys or [])
    index_map = _collect_index_map(prefix, all_keys) if all_keys else {}

    if not index_map:
        return

    if 0 not in index_map:
        raise GroupingValidationError(
            f"Sequential group '{prefix}' must start at index 0. Found indices: {sorted(index_map)}."
        )

    max_index = max(index_map)
    missing_indices = [idx for idx in range(0, max_index + 1) if idx not in index_map]
    if missing_indices:
        raise GroupingValidationError(
            f"Sequential group '{prefix}' has gaps at indices {missing_indices}. "
            "Sequential groups must be contiguous."
        )

    for index, present_keys in index_map.items():
        missing_required = [key for key in required_keys if key not in present_keys]
        if missing_required:
            missing = ", ".join(missing_required)
            present = ", ".join(sorted(present_keys)) or "none"
            raise GroupingValidationError(
                f"Sequential group '{prefix}' index {index} is missing required key(s): {missing}. "
                f"Present keys: {present}."
            )


def _enforce_required_groups(
    groups: dict[int, dict[str, str]], prefix: str, require_when_env: str | None
) -> None:
    """Optionally require at least one group when a controlling env var is truthy."""

    if not require_when_env:
        return

    if _is_truthy_env_var(require_when_env) and not groups:
        raise GroupingValidationError(
            f"Group '{prefix}' requires at least one entry because {require_when_env}=true. "
            f"Set {prefix}* variables or unset {require_when_env}."
        )


def apply_grouping_strategy(
    context: dict[str, Any],
    strategy_name: str,
    prefix: str,
    required_keys: list[str],
    optional_keys: list[str] | None = None,
    require_when_env: str | None = None,
) -> None:
    """Apply a custom grouping strategy and add results to context.

    Args:
        context: Context dictionary to update
        strategy_name: "indexed" or "sequential"
        prefix: Environment variable prefix
        required_keys: Required keys in each group
        optional_keys: Optional keys to collect if present
        require_when_env: Env var name that, when truthy, requires at least one group
    """
    logger.debug(f"Applying {strategy_name} strategy for prefix: {prefix}")

    if strategy_name == "indexed":
        groups = collect_indexed_groups(prefix, required_keys, optional_keys)
        _validate_indexed_groups(groups, prefix, required_keys)
    elif strategy_name == "sequential":
        _validate_sequential_groups(prefix, required_keys, optional_keys)
        groups = collect_sequential_groups(prefix, required_keys, optional_keys)
    else:
        raise ValueError(f"Unknown strategy: {strategy_name}")

    _enforce_required_groups(groups, prefix, require_when_env)

    # Always add the key to context, even if empty
    key = f"{prefix.lower().rstrip('_')}_groups"
    context[key] = list(groups.values()) if groups else []
    logger.debug(f"Added {len(groups)} group(s) to context under key: {key}")
