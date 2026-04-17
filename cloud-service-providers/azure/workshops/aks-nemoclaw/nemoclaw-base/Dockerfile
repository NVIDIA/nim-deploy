# NemoClaw fork baked into docker:dind for jobs that need Docker-in-Docker plus a fixed source tree.
#
# Build from the nemoclaw repository root (parent of this directory):
#   docker build -f Docker-base/Dockerfile -t nemoclaw-dind-src .
#
FROM node:22

ENV OPENSHELL_LOG_LEVEL=debug

COPY ./nemoclaw-src/NemoClaw /nemoclaw-src
#COPY ./nemoclaw /nemoclaw-src/nemoclaw

# Copy local policy overrides
COPY ./nemoclaw-blueprint /nemoclaw-src/nemoclaw-blueprint

RUN curl -LsSf https://raw.githubusercontent.com/NVIDIA/OpenShell/main/install.sh | OPENSHELL_VERSION=v0.0.26 sh

# COPY OpenShell /openshell-src
# COPY prepare-context.sh /usr/local/bin/prepare-context.sh
# RUN chmod 755 /usr/local/bin/prepare-context.sh

# RUN echo "Installing OpenShell..."
# RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y


# WORKDIR /openshell-src
# RUN set -a && . "$HOME/.cargo/env" && cargo build -p openshell-cli --release
# RUN install -m 755 /openshell-src/target/release/openshell "/usr/local/bin/openshell"