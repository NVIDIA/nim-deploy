# NVIDIA AI Workshops on Oracle Cloud Infrastructure (OCI)

Hands-on workshops for deploying NVIDIA AI on OCI: most use **Oracle Kubernetes Engine (OKE)** with GPU instances; one uses **OCI Data Science Service** for NIM deployment.

## Available Workshops

| Workshop | Description | Duration | GPUs Required |
|----------|-------------|----------|---------------|
| [RAG on OKE](RAG%20Workshop%20on%20OKE.md) | Deploy a RAG pipeline for document Q&A | 45-60 min | 4-8 H100 / 5-9 A100 |
| [AIQ on OKE](AIQ%20Workshop%20on%20OKE.md) | Deploy an AI-powered research assistant | 60-75 min | 4-10 H100 / 5-13 A100 |
| [VSS on OKE](VSS%20Workshop%20on%20OKE.md) | Deploy video search and summarization | 60-75 min | 8 H100 / 9 A100 |
| [Data Flywheel on OKE](Data%20Flywheel%20Workshop%20on%20OKE.md) | Deploy a model optimization pipeline | 45-60 min | 2-6 H100 / 2-6 A100 |
| [NIM on Data Science](NIM%20on%20Data%20Science%20Workshop.md) | Deploy an NVIDIA NIM on OCI Data Science (no OKE) | 45-60 min | 1 H100 / 2 A100 |
| [NIM on OKE](NIM%20on%20OKE%20Workshop.md) | Deploy Nemotron Super 49B NIM on OKE with baked-in Helm values | 45-60 min | 1 H100 / 2 A100 |

## Prerequisites

All workshops require:

- **OCI Account** with GPU instance access
- **NGC API Key** — [Sign up](https://ngc.nvidia.com/setup/api-key)
- **OCI CLI** installed and configured
- **kubectl** and **Helm 3.x**

> **Note**: VSS also requires a **Hugging Face Token** with access to `nvidia/Cosmos-Reason2-8B`.

## Getting Started

1. Choose a workshop from the table above
2. Ensure you have the required GPU quota in your OCI tenancy
3. Follow the step-by-step instructions in the workshop

## What You Will Learn

Each workshop includes:

- **Introduction**: Overview of the AI application and use cases
- **Learn the Components**: Deep dive into the architecture and technologies
- **Setup and Requirements**: Prerequisites and GPU requirements
- **Step-by-step Tasks**: Hands-on deployment instructions
- **Verification**: How to test your deployment
- **Cleanup**: Resource cleanup instructions

## Workshop Descriptions

### RAG (Retrieval Augmented Generation)

Deploy a complete document Q&A system using NVIDIA NIM, NeMo Retriever, and Milvus. This workshop teaches you how to:

- Deploy LLM, embedding, and reranking models
- Integrate with Milvus vector database
- Upload PDFs and ask questions through the RAG Playground

### AIQ (AI-Q Research Assistant)

Deploy an agentic research assistant that builds on RAG. AIQ can plan and execute complex research tasks autonomously. This workshop teaches you how to:

- Deploy RAG as a foundation for AIQ
- Configure cross-namespace service communication
- Use shared LLM configuration to save GPU resources

### VSS (Video Search and Summarization)

Deploy intelligent video analysis using Vision Language Models. This workshop teaches you how to:

- Work with Vision Language Models (VLM)
- Configure multi-database architecture (Milvus, Neo4j, Elasticsearch)
- Enable natural language search across video content

### Data Flywheel

Deploy an automated model optimization pipeline. This workshop teaches you how to:

- Configure remote LLM judge for evaluation
- Manage flywheel jobs via REST API
- Use MLflow for experiment tracking

### NIM on OKE

Deploy **Nemotron Super 49B** as an NVIDIA NIM on **Oracle Kubernetes Engine (OKE)**. This workshop teaches you how to:

- Create an OKE cluster with GPU nodes and configure NGC access
- Install the NVIDIA NIM Operator and optional Node Feature Discovery
- Deploy the NIM using Helm with a **values file baked into the guide** (no separate file to track)
- Test health and chat completions via LoadBalancer

### NIM on Data Science

Deploy an NVIDIA NIM (e.g., Nemotron Super 49B) on **OCI Data Science Service** (not OKE). This workshop teaches you how to:

- Create a Data Science project, model artifact, and model deployment
- Use capacity reservation and a custom NIM container image
- Run inference via the Data Science predict API

## Resources

- [NVIDIA AI Blueprints](https://github.com/NVIDIA-AI-Blueprints)
- [NVIDIA NGC](https://ngc.nvidia.com)
- [NVIDIA NIMs](https://developer.nvidia.com/nim)
- [Oracle Kubernetes Engine (OKE)](https://www.oracle.com/cloud/cloud-native/container-engine-kubernetes/)
