#!/bin/bash

# Deploy NIM in standby mode on an alternate port while the service is configured via the yaml below
gcloud alpha run deploy ${SERVICE_NAME?} \
    --project ${PROJECTID?} \
    --no-cpu-throttling  \
    --gpu-type nvidia-l4 \
    --allow-unauthenticated \
    --region ${REGION?}  \
    --execution-environment gen2 \
    --max-instances 1  \
    --service-account ${SERVICE_ACCOUNT_ID:?}@$PROJECTID.iam.gserviceaccount.com \
    --network default \
    --container nim \
    --image ${IMAGE?} \
    --port 3333 \
    --cpu 8 \
    --memory 32Gi \
    --gpu 1 \
    --set-env-vars=NIM_CACHE_PATH=/opt/nim/.cache \
    --set-secrets="NGC_API_KEY=nim-ngc-token:latest" \
    --command /home/nemo/entrypoint_0.sh

# Fetch the base service definition in yaml
gcloud run services describe ${SERVICE_NAME?} \
    --project ${PROJECTID?} \
    --region ${REGION?}  \
    --format export > ${SERVICE_NAME?}.yaml

# Modify service parameters to accomidate the startup time requuirements of the NIM
cp  ${SERVICE_NAME?}.yaml  ${SERVICE_NAME?}.yaml.orig
output=$(mktemp)
sed -e '/failureThreshold: 1/r'<(cat <<EOF
          initialDelaySeconds: 240
EOF
) ${SERVICE_NAME?}.yaml > $output
sed -e 's;/home/nemo/entrypoint_0.sh;/opt/nim/start-server.sh;' $output >  ${SERVICE_NAME?}.yaml
sed -e 's;failureThreshold: 1;failureThreshold: 5;' ${SERVICE_NAME?}.yaml > $output
sed -e 's;\([Pp]\)ort: 3333;\1ort: 8000;' $output >  ${SERVICE_NAME?}.yaml
sed -e '/timeoutSeconds: 300/r'<(cat <<EOF
      volumes:
      - csi:
          driver: gcsfuse.run.googleapis.com
          volumeAttributes:
            bucketName: ${GCSBUCKET?}
        name: gcs-1
EOF
) ${SERVICE_NAME?}.yaml > $output
sed -e '/timeoutSeconds: 240/r'<(cat <<EOF
        volumeMounts:
        - mountPath: /opt/nim/.cache
          name: gcs-1
EOF
) $output >  ${SERVICE_NAME?}.yaml
sed -e '/ingress-status: all/r'<(cat <<EOF
    run.googleapis.com/launch-stage: BETA
EOF
) ${SERVICE_NAME?}.yaml > $output
mv $output  ${SERVICE_NAME?}.yaml

# Redeploy the NIM on its openai_api port with the new settings
gcloud run services replace ${SERVICE_NAME?}.yaml  --project ${PROJECTID?} --region ${REGION?}



