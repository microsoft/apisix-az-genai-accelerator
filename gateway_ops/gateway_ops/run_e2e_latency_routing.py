from __future__ import annotations

import logging

from ._e2e_common import run_scenario


def run(*, base_env: dict[str, str] | None = None) -> None:
    run_scenario(
        test_file="scenario_latency_routing.py",
        endpoint_path="latency-routing",
        user_count=2,
        run_time="5m",
        base_env=base_env,
    )


def main(argv: list[str] | None = None) -> int:  # noqa: ARG001
    logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")
    run()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
