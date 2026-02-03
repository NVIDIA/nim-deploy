# NVIDIA AI Workshops on Oracle Cloud Infrastructure (OCI)

Hands-on workshops for deploying NVIDIA AI Blueprints on Oracle Kubernetes Engine (OKE) with GPU instances.

## Available Workshops

| Workshop | Description | Duration | GPUs Required |
|----------|-------------|----------|---------------|
| [RAG on OKE](RAG%20Workshop%20on%20OKE.md) | Deploy a RAG pipeline for document Q&A | 45-60 min | 4-8 H100 / 5-9 A100 |
| [AIQ on OKE](AIQ%20Workshop%20on%20OKE.md) | Deploy an AI-powered research assistant | 60-75 min | 4-10 H100 / 5-13 A100 |
| [VSS on OKE](VSS%20Workshop%20on%20OKE.md) | Deploy video search and summarization | 60-75 min | 8 H100 / 9 A100 |
| [Data Flywheel on OKE](Data%20Flywheel%20Workshop%20on%20OKE.md) | Deploy a model optimization pipeline | 45-60 min | 2-6 H100 / 2-6 A100 |

## Prerequisites

All workshops require:

- **OCI Account** with GPU instance access
- **NGC API Key** - [Sign up](https://ngc.nvidia.com/setup/api-key)
- **OCI CLI** installed and configured
- **kubectl** and **Helm 3.x**

> **Note**: VSS also requires a **HuggingFace Token** with access to `nvidia/Cosmos-Reason2-8B`.

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

## Resources

- [NVIDIA AI Blueprints](https://github.com/NVIDIA-AI-Blueprints)
- [NVIDIA NGC](https://ngc.nvidia.com)
- [NVIDIA NIMs](https://www.nvidia.com/en-us/ai/)
- [Oracle Kubernetes Engine (OKE)](https://www.oracle.com/cloud/cloud-native/container-engine-kubernetes/)
