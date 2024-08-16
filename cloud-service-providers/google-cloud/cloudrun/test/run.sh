#!/bin/bash

# Deploy test
gcloud alpha run deploy ${SERVICE_NAME?}-test \
    --project ${PROJECTID?} \
    --no-cpu-throttling  \
    --allow-unauthenticated \
    --region ${REGION?}  \
    --execution-environment gen2 \
    --max-instances 1  \
    --service-account ${SERVICE_ACCOUNT_ID:?}@$PROJECTID.iam.gserviceaccount.com \
    --network default \
    --container nim-test \
    --image ${IMAGE?} \
    --port 3333 \
    --cpu 8 \
    --memory 32Gi 

