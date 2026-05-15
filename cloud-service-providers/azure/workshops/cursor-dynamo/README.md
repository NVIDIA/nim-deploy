# Cursor Dynamo Workshop

## Executive overview

Organizations that deploy AI agents at scale face a predictable tension: **volume, latency, and cost** at the base of the stack versus **depth of reasoning and capability** at the top. The most sustainable pattern is not “one model for everything,” but a **deliberate escalation path**: handle the majority of work on governed, cost-efficient infrastructure, and reserve the most capable (and expensive) models for tasks that truly need them.

### Escalation Path

The diagram below summarizes how agent traffic can be shaped from high-throughput, local inference through enterprise-class foundation models to frontier providers when the task demands it.

```mermaid
flowchart TB
    REQ["AI agent requests<br/><i>all workloads enter here</i>"]

    subgraph tier1["Tier 1 — Local / edge (wide base)"]
        direction TB
        L1["Compact SLMs on laptop, workstation, or VPC<br/><b>Example:</b> Nemotron Nano and similar small models"]
    end

    subgraph tier2["Tier 2 — Enterprise foundation (narrowing)"]
        direction TB
        L2["Larger governed models in your cloud or data center<br/><b>Example:</b> Nemotron Super, Ultra-class deployments"]
    end

    subgraph tier3["Tier 3 — Frontier (apex)"]
        direction TB
        L3["Highest capability, external or specialist APIs<br/><b>Example:</b> Claude, GPT, Gemini, and comparable frontier models"]
    end

    REQ --> tier1
    tier1 -->|"escalate when complexity, context, or quality bar rises"| tier2
    tier2 -->|"escalate for hardest reasoning, long context, or policy-approved external use"| tier3
```

**How to read this funnel.** Most agent turns should resolve at **Tier 1**: fast feedback loops, data stays close to the user or inside your boundary, and unit economics stay favorable. A smaller fraction escalates to **Tier 2** when tasks need stronger reasoning, richer context, or centralized policy and observability at enterprise scale. Only the **narrow apex** at **Tier 3** should absorb frontier spend—typically for novel problems, long-horizon planning, or capabilities not yet replicated on your own stack.

This workshop’s Dynamo-oriented material supports the **middle and lower parts** of that path: repeatable deployment patterns for high-throughput, GPU-backed inference on Azure so escalation is a **design choice**, not an accident.
