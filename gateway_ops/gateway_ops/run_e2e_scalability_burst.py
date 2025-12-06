from __future__ import annotations

import datetime as dt
import logging

from ._e2e_common import build_test_environment, run_scenario
from .run_e2e_scalability import (
    _max_replica_count,
    _replica_bounds,
    _replica_metric_name,
    _utc_now,
)

# Fixed load profile for a heavier burst scenario
USER_COUNT = 260
SPAWN_RATE = 40.0
RUN_TIME = "20m"
EXPECTED_SCALE_INCREASE = 2
ENDPOINT_PATH = "round-robin-simple"


def run(*, base_env: dict[str, str] | None = None) -> None:
    env = base_env or build_test_environment()

    resource_id = env["GATEWAY_APP_RESOURCE_ID"]
    resource_group = env["RESOURCE_GROUP_NAME"]
    app_name = env["GATEWAY_APP_NAME"]

    window_start = _utc_now()
    run_scenario(
        test_file="scenario_round_robin.py",
        endpoint_path=ENDPOINT_PATH,
        user_count=USER_COUNT,
        run_time=RUN_TIME,
        spawn_rate=SPAWN_RATE,
        base_env=env,
    )
    window_end = _utc_now() + _metric_slop()

    metric_name = _replica_metric_name(resource_id)
    min_replicas, max_replicas_configured = _replica_bounds(resource_group, app_name)
    observed_max = _max_replica_count(
        resource_id=resource_id,
        metric_name=metric_name,
        window_start=window_start - _metric_slop(),
        window_end=window_end,
    )

    required = min_replicas + EXPECTED_SCALE_INCREASE
    logging.info(
        "Replica bounds configured: min=%s max=%s; observed peak=%s",
        min_replicas,
        max_replicas_configured,
        observed_max,
    )
    if observed_max < required:
        raise RuntimeError(
            f"Replica count did not scale as expected (observed {observed_max}, required >= {required})"
        )
    logging.info(
        "Replica scaling OK (burst): observed peak %s (required >= %s)",
        observed_max,
        required,
    )


def _metric_slop() -> dt.timedelta:
    # ACA metrics arrive on 1m buckets; pad windows by 1 minute.
    return dt.timedelta(minutes=1)


def main(argv: list[str] | None = None) -> int:  # noqa: ARG001
    logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")
    logging.info(
        "Running burst scalability scenario: users=%s, spawn_rate=%s/s, run_time=%s, expected_scale_increase=%s",
        USER_COUNT,
        SPAWN_RATE,
        RUN_TIME,
        EXPECTED_SCALE_INCREASE,
    )
    run()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
