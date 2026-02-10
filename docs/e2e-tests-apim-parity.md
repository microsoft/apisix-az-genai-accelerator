[← Back to README](../README.md)

# E2E tests + APIM parity: why you can trust this gateway

This repo doesn’t just “seem to work.” We run end-to-end scenarios that validate the behaviors people rely on in **APIM-style GenAI gateway patterns**:

- multi-backend routing
- weighted distribution
- latency preference
- retry/failover on real error conditions
- observability signals (backend IDs, timings, request counts)

The goal is **behavioral parity** with the expectations established by APIM GenAI gateway tooling and patterns — while running on a lightweight Azure Container Apps stack.

> Note: “Parity” here means **scenario-level behavior** (routing outcomes, retry semantics, observability), not a claim of official certification.

---

## Table of contents

- [Why this matters (confidence + cost)](#why-this-matters-confidence--cost)
- [What “E2E mode” deploys](#what-e2e-mode-deploys)
- [How to run the suite](#how-to-run-the-suite)
- [Scenarios (what they validate)](#scenarios-what-they-validate)
- [Sample run output (logs)](#sample-run-output-logs)
- [What to look for in telemetry](#what-to-look-for-in-telemetry)
- [TL;DR](#tldr)

---

## Why this matters (confidence + cost)

A production-grade traffic brain (multi-backend, retries, observability, policy surface) usually comes with a heavy platform bill and operational surface area.

This accelerator:

- runs APISIX in **standalone (data-plane) mode** on **Azure Container Apps**
- avoids running an always-on control plane (no etcd quorum, no Admin API service)
- keeps baseline costs in the “small container app” class, while exercising APIM-style gateway behaviors

By contrast, API Management’s higher-end tiers (for always-on GenAI gateway deployments) can easily be in the **$2,000+/month** range in many regions, just for the gateway control plane. Always check the current pricing for your tier/region here:

- https://azure.microsoft.com/pricing/details/api-management/

---

## What “E2E mode” deploys

When enabled (`--deploy-e2e`), the workload deploys **extra components** used by the test harness:

- a **simulator** that can emulate conditions (latency changes, throttling, timeouts)
- a **config API sidecar** used for toolkit-style update flows
- extra routes prefixed for test scenarios
- `GATEWAY_LOG_MODE=dev` for verbose telemetry during test runs

This keeps your normal deployment clean, while letting CI/local runs validate complex flows.

---

## How to run the suite

1. Ensure submodules are present:

```bash
git submodule update --init --recursive
```

2. Deploy with E2E enabled:

```bash
uv run deploy-workload "$ENV" --deploy-e2e
```

3. Run all scenarios:

```bash
uv run run-e2e-tests
```

---

## Scenarios (what they validate)

### `round-robin-simple`

Validates that with equal weights, traffic distributes evenly across backends.

### `round-robin-weighted`

Validates weighted routing (e.g., 2:1) behaves like you expect (more traffic to higher weight backend).

### `latency-routing`

Validates the “prefer fastest backend” pattern:

- simulator starts with PAYG1 fast / PAYG2 slow
- test measures latency, updates preferred backends
- simulator flips to PAYG2 fast / PAYG1 slow
- preferred backend updates follow the observed latency

### `retry-with-payg` / `retry-with-payg-v2`

Validates in-request failover semantics under stress:

- requests continue succeeding when a backend starts throttling / timing out
- backend selection shifts as conditions change
- logs/metrics show backend identifiers and request counts

### `scalability`

Validates autoscaling behavior on ACA:

- generates high concurrent load with a fixed Locust profile (180 users, spawn 20/s, 15m)
- asserts the gateway container app scales replicas above the configured minimum using Azure Monitor `Replicas` / `ReplicaCount` metrics

### `scalability-burst`

Heavier burst profile to prove headroom:

- 260 users, spawn 40/s, 20m sustained run
- requires replicas to climb at least two above the configured minimum

---

## Sample run output (logs)

Below are **sanitized excerpts** from real runs (2025-12-04), kept here because the ASCII charts make it easy to “see” routing.

> We intentionally omit Azure Portal share links and local filesystem paths here to keep the repo clean.

---

### `latency-routing` (excerpt)

```sh
INFO: Running locust scenario 'latency-routing' (users=2, run_time=5m)
[2025-12-04 15:38:05] 👟 Setting up test...
[2025-12-04 15:38:05] ⚙️ Setting initial simulator latencies (PAYG1 fast, PAYG2 slow)
[2025-12-04 15:38:06] ⌚ Measuring API latencies and updating APIM
[2025-12-04 15:38:36] WARNING: Request to PAYG2 timed out
[2025-12-04 15:38:36]     PAYG1: 76 ms
[2025-12-04 15:38:36]     PAYG2: inf ms
[2025-12-04 15:38:36]     Updated preferred backends: {"updated_instances":3}

... later ...

[2025-12-04 15:40:38] ⚙️ Updating simulator latencies (PAYG1 slow, PAYG2 fast)
[2025-12-04 15:41:38] ⌚ Measuring latencies and updating APIM
[2025-12-04 15:41:38]     PAYG2: 86 ms
[2025-12-04 15:41:38]     PAYG1: 236 ms
[2025-12-04 15:41:39]     Updated preferred backends: {"updated_instances":2}

Type  Name                                                                       # reqs  # fails | Avg  Min  Max  Med | req/s
POST  /latency-routing/openai/deployments/.../completions?api-version=2023-05-15   257  0(0.00%) |  37   30  115   37 | 0.86
```

---

### `retry-with-payg` (excerpt)

```sh
INFO: Running locust scenario 'retry-with-payg'
[2025-12-04 15:44:04] 👟 Setting up test...
[2025-12-04 15:44:04] 🚀 Running test...
[2025-12-04 15:50:04] ✔️ Test finished

Type  Name                                                                       # reqs  # fails |  Avg   Min    Max   Med | req/s
POST  /retry-with-payg/openai/deployments/.../chat/completions?api-version=2023-05-15 350 0(0.00%) | 3027   21  18605  880 | 0.97

Response time percentiles (approximated)
50%  66%  75%  80%  90%   95%   98%   99%  99.9% 100%
910 3300 5100 6500 9200 12000 14000 16000 19000 19000
```

---

### `round-robin-simple` (excerpt, includes ASCII chart)

```sh
INFO: Running locust scenario 'round-robin-simple' (users=2, run_time=3m)
[2025-12-04 16:02:34] 🚀 Running test...
[2025-12-04 16:05:34] ✔️ Test finished

Type  Name                                                                       # reqs  # fails | Avg Min Max Med | req/s
POST  /round-robin-simple/openai/deployments/.../completions?api-version=2023-05-15 345 0(0.00%) |  37  29 101  37 | 1.92

Request count by backend (PAYG1 -> Blue, PAYG2 -> Yellow)

   20.00  ┼╭╮╭╮╭─╮╭╮╭─╮╭╮╭─╮╭╮╭─╮
   18.67  ┤│╰╯╰╯ ╰╯╰╯ ╰╯╰╯ ╰╯╰╯ ╰
   17.33  ┤│
   16.00  ┤│
   14.67  ┤│
   13.33  ┤│
   12.00  ┤│
   10.67  ┼╯
    0.00  ┤
```

(Other scenarios such as `round-robin-weighted`, `round-robin-simple-v2`, and `round-robin-weighted-v2` show similar patterns with different weights and paths.)

---

## What to look for in telemetry

Even if you don’t run the full suite, you can validate behavior quickly by checking logs/metrics for:

- **BackendId** (which backend actually served the request)
- **TotalTime / latency** (per backend)
- **Request count distribution** (expected under weights)
- **Retry/failover signals** (429/5xx observed + alternate backend succeeding)

---

## TL;DR

- E2E mode exists so we can validate real-world gateway behaviors (routing, retries, observability).
- The logs make routing behavior obvious.
- If you care about “APIM-like GenAI gateway behavior without the heavy platform bill,” this is the confidence story.

[↑ Back to top](#e2e-tests--apim-parity-why-you-can-trust-this-gateway)
