```mermaid
---
title: Escalation Path
---
flowchart TB
    REQ["AI agent requests<br/><i>100% enter; most never need a higher tier</i>"]

    subgraph tier1["Tier 1 — Local / edge · ~80–95%+ of turns"]
        direction TB
        L1["Compact SLMs on laptop, workstation, or VPC<br/><b>Example:</b> Nemotron Nano and similar small models"]
    end

    subgraph tier2["Tier 2 — Enterprise foundation · ~single digits–teens %"]
        direction TB
        L2["Larger governed models in your cloud or data center<br/><b>Example:</b> Nemotron Super, Ultra-class deployments"]
    end

    subgraph tier3["Tier 3 — Frontier · smallest share (~few %)"]
        direction TB
        L3["Highest capability, external or specialist APIs<br/><b>Example:</b> Claude, GPT, Gemini, and comparable frontier models"]
    end

    REQ --> tier1
    tier1 -->|"remaining traffic when bar rises"| tier2
    tier2 -->|"rare escalations · policy-approved external use"| tier3

    style tier1 stroke-width:10px,stroke:#1b5e20
    style tier2 stroke-width:5px,stroke:#e65100
    style tier3 stroke-width:2px,stroke:#4a148c

    style L1 font-size:15px
    style L2 font-size:13px
    style L3 font-size:11px
```
