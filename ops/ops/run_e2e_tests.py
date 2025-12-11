from __future__ import annotations

import argparse
import logging

from . import (
    run_e2e_latency_routing,
    run_e2e_manage_spikes_with_payg,
    run_e2e_manage_spikes_with_payg_v2,
    run_e2e_prioritization,
    run_e2e_round_robin_simple,
    run_e2e_round_robin_simple_v2,
    run_e2e_round_robin_weighted,
    run_e2e_round_robin_weighted_v2,
    run_e2e_scalability,
    run_e2e_scalability_burst,
    run_e2e_usage_tracking,
)
from ._e2e_common import build_test_environment

SCENARIO_RUNNERS = {
    "round-robin-simple": run_e2e_round_robin_simple.run,
    "round-robin-simple-v2": run_e2e_round_robin_simple_v2.run,
    "round-robin-weighted": run_e2e_round_robin_weighted.run,
    "round-robin-weighted-v2": run_e2e_round_robin_weighted_v2.run,
    "latency-routing": run_e2e_latency_routing.run,
    "manage-spikes-with-payg": run_e2e_manage_spikes_with_payg.run,
    "manage-spikes-with-payg-v2": run_e2e_manage_spikes_with_payg_v2.run,
    "usage-tracking": run_e2e_usage_tracking.run,
    "prioritization": run_e2e_prioritization.run,
    "scalability": run_e2e_scalability.run,
    "scalability-burst": run_e2e_scalability_burst.run,
}


def main(argv: list[str] | None = None) -> int:
    logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")
    parser = argparse.ArgumentParser(
        prog="run-e2e-all",
        description="Run all APIM/GenAI toolkit end-to-end scenarios sequentially.",
    )
    parser.add_argument(
        "--skip",
        action="append",
        choices=list(SCENARIO_RUNNERS.keys()),
        help="Scenario keys to skip; can be provided multiple times.",
    )
    parser.add_argument(
        "--stop-on-failure",
        action="store_true",
        help="Stop after the first failed scenario instead of continuing.",
    )
    args = parser.parse_args(argv)

    base_env = build_test_environment()
    failures: list[tuple[str, Exception]] = []

    for name, runner in SCENARIO_RUNNERS.items():
        if args.skip and name in args.skip:
            logging.info("Skipping scenario '%s'", name)
            continue
        try:
            runner(base_env=base_env)
        except Exception as exc:  # noqa: BLE001
            failures.append((name, exc))
            logging.error("Scenario '%s' failed: %s", name, exc)
            if args.stop_on_failure:
                break

    if failures:
        failure_names = ", ".join(n for n, _ in failures)
        raise RuntimeError(f"One or more scenarios failed: {failure_names}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
