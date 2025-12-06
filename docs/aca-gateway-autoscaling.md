[← Back to README](../README.md)

# Autoscaling the gateway on Azure Container Apps

You don’t want to overpay for idle replicas, but you also don’t want latency spikes when traffic jumps. This doc explains the **scaling model we ship for the gateway** on ACA, how to tune it, and how to prove it works.

---

## Table of contents

- [Why this matters](#why-this-matters)
- [How we scale (defaults)](#how-we-scale-defaults)
- [How to tune (what to change)](#how-to-tune-what-to-change)
- [How to validate (scalability scenario)](#how-to-validate-scalability-scenario)
- [What to watch in telemetry](#what-to-watch-in-telemetry)
- [TL;DR](#tldr)

---

## Why this matters

- ACA bills per active replica; keeping the floor low reduces steady-state cost.
- Spiky GenAI traffic (batch jobs, bursty chats) needs **fast scale-out** or users feel it.
- We pair **HTTP concurrency-based scaling** (request backlog) with a **CPU guardrail** so noisy requests don’t pin a replica at 100% and stall scale-out.

---

## How we scale (defaults)

We use ACA built-in scale rules (no KEDA add-ons):

- **HTTP concurrency rule:** scale out when a replica sees more than **60 concurrent HTTP requests** (`gateway_http_concurrency`).
- **CPU guardrail:** scale out when average CPU > **70%** (`gateway_cpu_scale_threshold`).
- **Replica bounds:** **min 2**, **max 20** replicas (`gateway_min_replicas`, `gateway_max_replicas`).
- **Revision mode:** `Single` (consistent with our rolling updates).

Why these numbers:

- 60 concurrent requests keeps per-replica latency modest for typical APISIX/OpenResty workloads with LLM proxying.
- 70% CPU guardrail prevents slow-inflight requests from hogging the worker and delaying scale.
- Min 2 avoids cold-start singletons; max 20 covers the usual spike envelope without runaway cost.

ACA’s control loop polls every ~30s; expect a few minutes for full ramp under sustained load. Scale-in follows ACA’s cooldown (default behavior), so replicas drop only after pressure subsides.

---

## How to tune (what to change)

Edit your stack tfvars (e.g., `infra/terraform/stacks/20-workload/terraform.tfvars.<env>`) and adjust:

- `gateway_http_concurrency` – lower for faster fan-out on concurrent calls; raise if requests are short-lived and you prefer fewer replicas.
- `gateway_cpu_scale_threshold` – lower to bias toward earlier scale-out under CPU-heavy routes.
- `gateway_min_replicas` / `gateway_max_replicas` – set floors/ceilings that match your SLOs and budget.

Apply with your normal workflow:

```bash
uv run deploy-workload "<env>"
```

---

## How to validate (scalability scenario)

- Run the new **scalability** scenario (load + metric assertion):

```bash
uv run run-e2e-scalability --users 180 --spawn-rate 20 --run-time 15m --expected-scale-increase 1
```

What it does:

- Drives high concurrent load via the existing Locust `round-robin` scenario.
- Queries Azure Monitor for the gateway’s `Replicas` / `ReplicaCount` metric.
- Fails if the observed peak replica count doesn’t rise at least the requested amount above `gateway_min_replicas`.

---

## What to watch in telemetry

- **Azure Monitor metrics** on the container app resource:
  - `Replicas` or `ReplicaCount` (max over 1m).
  - `CpuUsagePercentage` (should climb toward threshold before scale-out).
  - `Requests` and `RequestsQueued` (to see backlog relief after scale).
- **Log Analytics** (gateway logs) for latency distribution before/after scale.

---

## TL;DR

- Scaling is **HTTP concurrency-first** with a **CPU safety net**.
- Defaults: **2–20 replicas**, **60 concurrent requests**, **70% CPU**.
- Tune in tfvars, apply, then run `run-e2e-scalability` to prove it.

[↑ Back to top](#autoscaling-the-gateway-on-azure-container-apps)
