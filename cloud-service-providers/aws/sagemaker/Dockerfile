FROM {{ SRC_IMAGE }}
USER 0

ENV CADDY_BINURL=https://caddyserver.com/api/download?os=linux&arch=amd64
ENV CADDY_CONF=/opt/caddy-config.json
ENV NIM_ENTRYPOINT=/opt/nvidia/nvidia_entrypoint.sh
ENV NIM_CMD=/opt/nim/start-server.sh

COPY launch.sh caddy-config.json /opt/

RUN apt-get update && \
    apt-get install -y curl && \
    curl -L -o "/usr/local/bin/caddy" "$CADDY_BINURL" && \
    chmod a+x /usr/local/bin/caddy /opt/launch.sh

ENTRYPOINT ["sh", "-xe", "-c", "/opt/launch.sh -c $CADDY_CONF -e $NIM_ENTRYPOINT -a $NIM_CMD"]
