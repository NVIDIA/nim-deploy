# Stage 1: Build Caddy with custom modules
FROM golang:1.18-alpine AS builder

# Install xcaddy
RUN go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest

# Build Caddy with the request_id module
RUN xcaddy build --with github.com/caddyserver/caddy/v2@v2.4.6 --with github.com/caddyserver/replace-response

# Stage 2: Prepare the final image
FROM {{ SRC_IMAGE }}
USER 0

# Copy the custom Caddy binary from the builder stage
COPY --from=builder /usr/bin/caddy /usr/local/bin/caddy

# Environment variables
ENV CADDY_CONF=/opt/caddy-config.json
ENV NIM_ENTRYPOINT=/opt/nvidia/nvidia_entrypoint.sh
ENV NIM_CMD=/opt/nim/start-server.sh

# Copy the launch script and configuration file
COPY launch.sh caddy-config.json /opt/

# Install curl (if needed)
RUN apt-get update && \
    apt-get install -y curl && \
    chmod a+x /usr/local/bin/caddy /opt/launch.sh

# Entrypoint
ENTRYPOINT ["sh", "-xe", "-c", "/opt/launch.sh -c $CADDY_CONF -e $NIM_ENTRYPOINT -a $NIM_CMD"]