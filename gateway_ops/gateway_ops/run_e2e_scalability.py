from __future__ import annotations

import datetime as dt
import json
import logging

from ._e2e_common import build_test_environment, run_scenario
from ._utils import ensure, run_logged

USER_COUNT = 180
SPAWN_RATE = 20.0
RUN_TIME = "15m"
EXPECTED_SCALE_INCREASE = 1
ENDPOINT_PATH = "round-robin-simple"


def _utc_now() -> dt.datetime:
    return dt.datetime.now(dt.timezone.utc)


def _replica_bounds(resource_group: str, app_name: str) -> tuple[int, int]:
    ensure(["az"])
    result = run_logged(
        [
            "az",
            "containerapp",
            "show",
            "--name",
            app_name,
            "--resource-group",
            resource_group,
            "--query",
            "{min:properties.template.scale.minReplicas,max:properties.template.scale.maxReplicas}",
            "-o",
            "json",
        ],
        capture_output=True,
    )
    data = json.loads(result.stdout)
    min_replicas = int(data.get("min", 0) or 0)
    max_replicas = int(data.get("max", 0) or 0)
    return min_replicas, max_replicas


def _replica_metric_name(resource_id: str) -> str:
    ensure(["az"])
    result = run_logged(
        [
            "az",
            "monitor",
            "metrics",
            "list-definitions",
            "--resource",
            resource_id,
            "--query",
            "[].name.value",
            "-o",
            "json",
        ],
        capture_output=True,
    )
    names = set(json.loads(result.stdout))
    for candidate in ("Replicas", "ReplicaCount"):
        if candidate in names:
            return candidate
    available = ", ".join(sorted(str(name) for name in names if name))
    raise RuntimeError(
        f"No replica metric found for resource {resource_id}; available metrics: {available or 'none'}"
    )


def _max_replica_count(
    *,
    resource_id: str,
    metric_name: str,
    window_start: dt.datetime,
    window_end: dt.datetime,
) -> int:
    ensure(["az"])
    result = run_logged(
        [
            "az",
            "monitor",
            "metrics",
            "list",
            "--resource",
            resource_id,
            "--metric",
            metric_name,
            "--interval",
            "PT1M",
            "--aggregation",
            "Maximum",
            "--start-time",
            window_start.isoformat(),
            "--end-time",
            window_end.isoformat(),
            "-o",
            "json",
        ],
        capture_output=True,
    )
    payload = json.loads(result.stdout)
    series = payload.get("value", [])
    maxima: list[float] = []
    for metric in series:
        for timeseries in metric.get("timeseries", []):
            for sample in timeseries.get("data", []):
                value = sample.get("maximum")
                if value is not None:
                    maxima.append(float(value))
    if not maxima:
        raise RuntimeError(
            f"No replica metric datapoints returned for {metric_name}; raw response: {payload}"
        )
    return int(max(maxima))


def run(
    *,
    base_env: dict[str, str] | None = None,
) -> None:
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
    window_end = _utc_now() + dt.timedelta(minutes=2)

    metric_name = _replica_metric_name(resource_id)
    min_replicas, max_replicas_configured = _replica_bounds(resource_group, app_name)
    observed_max = _max_replica_count(
        resource_id=resource_id,
        metric_name=metric_name,
        window_start=window_start - dt.timedelta(minutes=1),
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
        "Replica scaling OK: observed peak %s (required >= %s)",
        observed_max,
        required,
    )


def main(argv: list[str] | None = None) -> int:  # noqa: ARG001
    logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")
    logging.info(
        "Running fixed scalability scenario: users=%s, spawn_rate=%s/s, run_time=%s, expected_scale_increase=%s",
        USER_COUNT,
        SPAWN_RATE,
        RUN_TIME,
        EXPECTED_SCALE_INCREASE,
    )
    run()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
