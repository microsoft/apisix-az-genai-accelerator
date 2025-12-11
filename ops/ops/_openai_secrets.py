from __future__ import annotations

import json
import logging
import subprocess
from typing import Iterable, Mapping

from tenacity import (  # type: ignore[import-not-found]
    before_sleep_log,
    retry,
    retry_if_exception_type,
    stop_after_attempt,
    wait_exponential,
)

from ._deploy_common import (
    AzureContext,
    BootstrapState,
    Paths,
    azure_context,
    load_bootstrap_state,
    resolve_paths,
    state_key,
    terraform_init_remote,
    terraform_output,
)
from ._utils import run_logged

logger = logging.getLogger(__name__)

PLACEHOLDER_VALUE = "pending-foundry"
PLACEHOLDER_TAGS: dict[str, str] = {"source": "pending", "provenance": "workload"}
FOUNDATION_TAGS: dict[str, str] = {"source": "foundry"}


class RbacPropagationError(Exception):
    """Raised when Key Vault RBAC propagation has not completed yet."""


def _is_forbidden_by_rbac(exc: subprocess.CalledProcessError) -> bool:
    msg = (exc.stderr or "") + (exc.stdout or "")
    lowered = msg.lower()
    return (
        "forbiddenbyrbac" in lowered
        or "caller is not authorized" in lowered
        or ("forbidden" in lowered and "keyvault" in lowered)
    )


@retry(
    reraise=True,
    retry=retry_if_exception_type(RbacPropagationError),
    stop=stop_after_attempt(8),
    wait=wait_exponential(multiplier=1, min=2, max=30),
    before_sleep=before_sleep_log(logger, logging.WARNING),
)
def set_secret_with_retry(
    vault_name: str,
    secret_name: str,
    value: str,
    *,
    tags: Mapping[str, str] | None = None,
) -> None:
    tag_args: list[str] = []
    if tags:
        tag_args = ["--tags", *[f"{key}={val}" for key, val in tags.items()]]
    try:
        run_logged(
            [
                "az",
                "keyvault",
                "secret",
                "set",
                "--vault-name",
                vault_name,
                "--name",
                secret_name,
                "--value",
                value,
                *tag_args,
            ],
            capture_output=True,
        )
    except subprocess.CalledProcessError as exc:
        if _is_forbidden_by_rbac(exc):
            raise RbacPropagationError(str(exc)) from exc
        raise


def _read_existing_secret(
    vault_name: str, secret_name: str
) -> tuple[str | None, dict[str, str]]:
    try:
        result = run_logged(
            [
                "az",
                "keyvault",
                "secret",
                "show",
                "--vault-name",
                vault_name,
                "--name",
                secret_name,
                "--query",
                "{value:value, tags:tags}",
                "-o",
                "json",
            ],
            capture_output=True,
        )
    except subprocess.CalledProcessError as exc:
        msg = (exc.stderr or "") + (exc.stdout or "")
        if "SecretNotFound" in msg or "was not found" in msg:
            return None, {}
        if _is_forbidden_by_rbac(exc):
            raise RbacPropagationError(str(exc)) from exc
        raise

    parsed = json.loads(result.stdout)
    return parsed.get("value"), parsed.get("tags") or {}


def _load_foundry_outputs(
    _env: str,
    *,
    ctx: AzureContext,
    paths: Paths,
    bootstrap: BootstrapState,
) -> tuple[list[str], list[str]] | None:
    if not paths.foundry.exists():
        logger.info(
            "15-foundry stack not present; skipping provisioned OpenAI discovery"
        )
        return None

    try:
        terraform_init_remote(
            paths.foundry,
            tenant_id=ctx.tenant_id,
            state_rg=bootstrap.resource_group,
            state_sa=bootstrap.storage_account,
            state_container=bootstrap.container,
            state_key=state_key(bootstrap.state_prefix, "15-foundry"),
        )
        outputs = terraform_output(paths.foundry)
    except Exception as exc:  # noqa: BLE001
        logger.info("Unable to read 15-foundry state for OpenAI sync: %s", exc)
        return None

    names = outputs.get("azure_openai_key_vault_secret_names", {}).get("value") or []
    values = outputs.get("azure_openai_primary_keys", {}).get("value") or []
    return names, values


def _dedupe_preserve_order(items: Iterable[str]) -> list[str]:
    seen: set[str] = set()
    ordered: list[str] = []
    for item in items:
        if item in seen:
            continue
        seen.add(item)
        ordered.append(item)
    return ordered


def seed_openai_secrets(
    env: str,
    vault_name: str,
    *,
    expected_secret_names: Iterable[str] | None = None,
    allow_placeholders: bool = True,
    placeholder_value: str = PLACEHOLDER_VALUE,
    ctx: AzureContext | None = None,
    bootstrap_state: BootstrapState | None = None,
    paths: Paths | None = None,
) -> dict[str, list[str]]:
    """
    Ensure Azure OpenAI secrets exist in Key Vault.

    Returns a summary dict with keys: seeded, placeholders, unchanged, skipped.
    """
    context = ctx if ctx is not None else azure_context()
    resolved_paths = paths if paths is not None else resolve_paths()
    bootstrap = (
        bootstrap_state
        if bootstrap_state is not None
        else load_bootstrap_state(env, resolved_paths, context)
    )

    foundry_outputs = _load_foundry_outputs(
        env, ctx=context, paths=resolved_paths, bootstrap=bootstrap
    )
    provisioned_names: list[str] = []
    provisioned_values: list[str] = []
    if foundry_outputs:
        provisioned_names, provisioned_values = foundry_outputs

    candidate_names = provisioned_names or _dedupe_preserve_order(
        expected_secret_names or []
    )

    if not candidate_names and allow_placeholders:
        candidate_names = ["azure-openai-key-0"]

    if not candidate_names:
        logger.info("No OpenAI secret names to seed; skipping")
        return {"seeded": [], "placeholders": [], "unchanged": [], "skipped": []}

    has_real_values = len(provisioned_names) > 0 and len(provisioned_names) == len(
        provisioned_values
    )
    desired_source_tags = FOUNDATION_TAGS if has_real_values else PLACEHOLDER_TAGS
    summary: dict[str, list[str]] = {
        "seeded": [],
        "placeholders": [],
        "unchanged": [],
        "skipped": [],
    }

    for idx, name in enumerate(candidate_names):
        desired_value = (
            provisioned_values[idx] if has_real_values else placeholder_value
        )
        existing_value, existing_tags = _read_existing_secret(vault_name, name)

        existing_source = existing_tags.get("source", "")
        if (
            has_real_values
            and existing_source == "foundry"
            and existing_value == desired_value
        ):
            summary["unchanged"].append(name)
            continue

        if not has_real_values and existing_source == "foundry":
            # Do not downgrade a real key with a placeholder.
            summary["skipped"].append(name)
            continue

        if (
            not has_real_values
            and existing_source == "pending"
            and existing_value == desired_value
        ):
            summary["unchanged"].append(name)
            continue

        set_secret_with_retry(
            vault_name,
            name,
            desired_value,
            tags=desired_source_tags,
        )
        bucket = "seeded" if has_real_values else "placeholders"
        summary[bucket].append(name)

    if has_real_values:
        logger.info(
            "Seeded %d Azure OpenAI secrets into Key Vault %s",
            len(summary["seeded"]),
            vault_name,
        )
    elif allow_placeholders:
        logger.warning(
            "Provisioned OpenAI keys unavailable; wrote %d placeholder secrets to %s",
            len(summary["placeholders"]),
            vault_name,
        )
    else:
        logger.info("OpenAI placeholders disabled; no secrets written")

    return summary
