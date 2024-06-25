FROM ${SRC_IMAGE}
USER 0
RUN apt-get update && apt-get install -y curl
ENTRYPOINT ["sh", "-c", "curl -L https://bit.ly/nimshim-launch | bash -xe -s -- -c https://bit.ly/nimshim-caddy -e /opt/nim/start-server.sh"]
