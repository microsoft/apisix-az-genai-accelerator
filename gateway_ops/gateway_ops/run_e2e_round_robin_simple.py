from __future__ import annotations

import logging

from ._e2e_common import run_scenario

logger = logging.getLogger(__name__)


def run(*, base_env: dict[str, str] | None = None) -> None:
    run_scenario(
        test_file="scenario_round_robin.py",
        endpoint_path="round-robin-simple",
        user_count=2,
        run_time="3m",
        base_env=base_env,
    )


def main(argv: list[str] | None = None) -> int:  # noqa: ARG001
    logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")
    run()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
