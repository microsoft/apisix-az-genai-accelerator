"""Key Vault integration for environment preprocessing."""

from __future__ import annotations

import logging
import os
from typing import Any

logger = logging.getLogger(__name__)


def enhance_context_with_key_vault(context: dict[str, Any]) -> dict[str, Any]:
    """Enhance rendering context with Key Vault-related variables.

    Args:
        context: Existing rendering context

    Returns:
        Enhanced context with Key Vault variables
    """
    # Key Vault is enabled when this function is called
    context["use_key_vault"] = True

    # Add Key Vault related environment variables if available
    kv_vars = [
        "KEY_VAULT_NAME",
        "KEY_VAULT_URI",
        "ACA_MANAGED_IDENTITY_CLIENT_ID",
        "AZURE_CLIENT_ID",  # Alternative name for managed identity
    ]

    kv_context = {}
    for var in kv_vars:
        value = os.environ.get(var)
        if value:
            kv_context[var.lower()] = value

    context.update(kv_context)

    logger.debug(
        f"Enhanced context with Key Vault variables: {list(kv_context.keys())}"
    )

    return context
