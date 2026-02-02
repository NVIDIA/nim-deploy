# NVIDIA AI Blueprints on Oracle Cloud Infrastructure (OCI)

Deploy NVIDIA AI Blueprints on Oracle Kubernetes Engine (OKE) with GPU instances.

## Available Blueprints

| Blueprint | Description | H100 GPUs | A100 GPUs |
|-----------|-------------|-----------|-----------|
| [RAG](RAG%20Blueprint%20on%20OKE%20Guide.md) | Retrieval Augmented Generation - document Q&A with LLM | 4-8 | 4-9 |
| [AIQ](AIQ%20Blueprint%20on%20OKE%20Guide.md) | AI-Q Research Assistant - agentic workflows with RAG | 4-10 | 5-13 |
| [Data Flywheel](Data%20Flywheel%20Blueprint%20on%20OKE%20Guide.md) | Continuous model optimization using production data | 2-6 | 2-6 |
| [VSS](VSS%20Blueprint%20on%20OKE%20Guide.md) | Video Search and Summarization - AI video analysis | 8 | 9 |

## Prerequisites

- **OCI Account** with GPU instance access
- **NGC API Key** - [Sign up](https://ngc.nvidia.com/setup/api-key)
- **OCI CLI** configured
- **kubectl** and **Helm 3.x**

## Quick Start

1. Create an OKE cluster with GPU nodes (see individual guides for requirements)
2. Configure kubectl access
3. Follow the blueprint guide for your use case

## Blueprint Details

### RAG (Retrieval Augmented Generation)
Production-ready document Q&A using NVIDIA NIM, NeMo Retriever, and Milvus vector database. Supports PDF ingestion with text, tables, and charts.

### AIQ (AI-Q Research Assistant)
Agentic research assistant built on top of RAG. Combines multiple LLMs for instruction-following and reasoning tasks. Requires RAG Blueprint deployed first.

### Data Flywheel
Automated model optimization pipeline using production traffic logs. Evaluates candidate models and performs LoRA fine-tuning with NeMo Customizer.

### VSS (Video Search and Summarization)
Intelligent video analysis using Vision Language Models (VLM) and LLMs. Enables natural language search across video content with automatic summarization.

## Resources

- [NVIDIA AI Blueprints](https://github.com/NVIDIA-AI-Blueprints)
- [NVIDIA NGC](https://ngc.nvidia.com)
- [Oracle Kubernetes Engine (OKE)](https://www.oracle.com/cloud/cloud-native/container-engine-kubernetes/)
