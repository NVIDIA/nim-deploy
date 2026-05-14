# Build from this directory so NeMo-Agent-Toolkit and workflow.yaml are in context:
#   docker build -t nat-dynamo-serve .
# For AKS (linux/amd64), especially from Apple Silicon, build and push with:
#   docker buildx build --platform linux/amd64 -t <acr>.azurecr.io/nat-dynamo-serve:latest --push .
#
# Run (mount secrets / override endpoints via env as needed):
#   docker run --rm -p 8080:8080 nat-dynamo-serve

FROM python:3.12-slim-bookworm

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*

COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv

WORKDIR /opt/nat

COPY NeMo-Agent-Toolkit /opt/nat/NeMo-Agent-Toolkit
COPY workflow.yaml /opt/nat/workflow.yaml
COPY prediction_trie.json /opt/nat/prediction_trie.json

WORKDIR /opt/nat/NeMo-Agent-Toolkit

# Editable monorepo installs use setuptools-scm; Docker builds typically have no .git metadata.
ENV SETUPTOOLS_SCM_PRETEND_VERSION=1.0.0+docker
ENV UV_PROJECT_ENVIRONMENT=/opt/nat/NeMo-Agent-Toolkit/.venv
ENV PATH="/opt/nat/NeMo-Agent-Toolkit/.venv/bin:${PATH}"

# Demo package (editable) pulls nvidia-nat[eval,langchain,test] from the repo and registers workflow _types.
RUN --mount=type=cache,target=/root/.cache/uv \
    uv venv --clear \
    && uv pip install -e ./examples/dynamo_integration/latency_sensitivity_demo

# Profiler plugin from monorepo (replaces nvidia-nat[profiler] from PyPI).
RUN --mount=type=cache,target=/root/.cache/uv \
    uv pip install -e /opt/nat/NeMo-Agent-Toolkit/packages/nvidia_nat_profiler

EXPOSE 8080

CMD ["nat", "--log-level", "DEBUG", "serve", "--config_file=/opt/nat/workflow.yaml", "--port", "8080", "--host", "0.0.0.0"]
