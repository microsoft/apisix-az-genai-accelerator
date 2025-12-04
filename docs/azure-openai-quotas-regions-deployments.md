[← Back to README](../README.md)

# Why this gateway works: quotas, regions, deployments (Azure AI Foundry / Azure OpenAI)

The short version: **throttling is not evenly distributed across Azure**. “HTTP 429” is usually telling you _this_ backend is out of capacity _right now_ — and that capacity is heavily influenced by **region** (and sometimes by the **deployment** and **SKU** you chose). If you have more than one backend, you can route around the bottleneck.

This document explains the mental model so you can design your backends and routing intentionally.

---

## Table of contents

- [The mental model (the one that matters)](#the-mental-model-the-one-that-matters)
- [How this repo uses that model](#how-this-repo-uses-that-model)
- [Practical guidance (what to do in real deployments)](#practical-guidance-what-to-do-in-real-deployments)
- [Getting more quota/capacity](#getting-more-quotacapacity)
- [TL;DR](#tldr)

---

## The mental model (the one that matters)

### 1) Azure OpenAI resources live in a region

Each Azure OpenAI (or Azure AI Foundry OpenAI) **resource** is created in a specific **Azure region**, and your requests are served out of that region’s capacity pools.

If you hit 429 in one region, **another region can still be healthy**.

### 2) Quotas/capacity are effectively “regional buckets”

Even when limits are shown “per model” in the portal, they’re typically scoped in a way that makes **region** the practical boundary for real-world throttling.

**Provisioned throughput capacity is explicitly regional**:

> “PTU quota for each provisioned deployment type is granted to a subscription regionally and limits the total number of PTUs that can be deployed in that region …”  
> Source: Microsoft Learn (Provisioned deployments).  
> https://learn.microsoft.com/en-us/azure/ai-foundry/openai/how-to/provisioned-get-started?view=foundry-classic

For standard (non-provisioned) usage, the portal shows rate limits/quotas in a per-region context as well, and 429s commonly reflect local capacity pressure rather than a global limit.

### 3) Deployments are your “named lenses” onto capacity

A **deployment** is the mapping you create between:

- a **model + version**
- a **deployment name**
- and the backend resource’s capacity.

SDKs usually call by deployment name (Azure-style), or call the v1 `model` field (standard OpenAI-style). This gateway supports both patterns by forwarding to your configured Azure deployments.

### 4) Regions + multiple backends = fewer global meltdowns

If you expose **one** backend and it gets throttled, your client has nowhere to go.  
If you expose **many** backends (across regions and/or resources), the gateway can:

- try a different backend **within the same request** on 429/5xx
- route new requests toward backends with better headroom (via weights / priority lanes)

---

## How this repo uses that model

You configure a set of Azure OpenAI backends:

- `AZURE_OPENAI_ENDPOINT_0`, `AZURE_OPENAI_KEY_0`, optional name/weight
- `AZURE_OPENAI_ENDPOINT_1`, `AZURE_OPENAI_KEY_1`, …

These can be:

- **different regions** (recommended),
- different resources in the **same** region (useful for isolation), or
- mixing **Provisioned** and **Standard** backends (common pattern: PTU for steady traffic, PAYG for burst).

On each request, if a backend returns **429** or **5xx**, APISIX immediately attempts other configured backends.

---

## Practical guidance (what to do in real deployments)

### Pick regions deliberately

- Choose regions where your target model is available.
- Prefer regions with independent capacity profiles (different geographies).
- Consider data residency / compliance requirements.

### Keep compatibility simple

- Standardize on a small set of `api-version` values.
- Keep deployment names consistent across regions if you want “drop-in” portability.

### Use weights + priority lanes

- Use weights to bias stable/fast capacity.
- Use `x-priority: high|low` to protect interactive traffic from background jobs.

### Know what 429 really means

429 may be:

- request-rate throttling,
- token-rate throttling,
- transient capacity pressure,
- or a mix.

The gateway doesn’t “solve quotas” — it **routes around local throttling** when you’ve provided alternative capacity.

---

## Getting more quota/capacity

If you genuinely need more capacity, you can request quota increases through Microsoft’s process. Microsoft’s guidance emphasizes quotas and capacity-based limits (rather than automatic scaling).

- Microsoft Learn (Provisioned deployments):  
  https://learn.microsoft.com/en-us/azure/ai-foundry/openai/how-to/provisioned-get-started?view=foundry-classic
- Microsoft Learn (Quotas and limits – Azure OpenAI):  
  https://learn.microsoft.com/en-us/azure/ai-services/openai/quotas-limits?view=rest-azureopenai-2024-05-01-preview
- Microsoft Learn (Q&A: quota increases):  
  https://learn.microsoft.com/en-us/answers/questions/5616163/how-can-i-get-increased-quotas-for-azure-ai-foundr

---

## TL;DR

- **Regions matter.**
- **Multiple backends matter.**
- This gateway works because **capacity isn’t uniformly shared**, so having multiple regional backends gives you something to fail over to when one backend gets hot.

[↑ Back to top](#why-this-gateway-works-quotas-regions-deployments-azure-ai-foundry--azure-openai)
