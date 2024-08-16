#! /bin/bash

sed -e "s;%URL%;${CLOUD_RUN_ENDPOINT_URL?};g" \
    Dockerfile > Dockerfile_build
docker build  -t ${IMAGE?} -f Dockerfile_build .
docker push  ${IMAGE?}

