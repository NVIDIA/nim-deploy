#! /bin/bash

if [ ! -r ./env ]
then
    echo Please create a file ./env with the required environment variables:
cat <<EOF
export SERVICE_ACCOUNT_ID= # will be created with needed permissions
export PROJECTID=
export PROJECTUSER=
export PROJECTNUM=
export REGION=
export GCSBUCKET=
ARTIFACT_REGISTERY_LOCATION= # e.g.: us
EOF
exit
fi

source ./env

# Articat Registry
echo gcloud artifacts repositories list \
    --project=${PROJECTID?} \
    --location=${ARTIFACT_REGISTRY_LOCATION?} | grep ${PROJECTUSER:?}
if [ $? -eq 1 ]
then
echo gcloud artifacts repositories create --repository-format=docker --project=${PROJECTID?} --location=${ARTIFACT_REGISTRY_LOCATION?} ${PROJECTUSER:?}

fi

export IMAGE=${ARTIFACT_REGISTERY_LOCATION?}-docker.pkg.dev/${PROJECTID:?}/${PROJECTUSER:?}/${SERVICE_NAME?}-l4:1.0

if [ ! -r source/ngc-token ]
then
    echo Please place your NGC token in the file source/ngc-token
    exit
fi
gcloud secrets list --project ${PROJECTID?} | \
    grep nim-ngc-token > /dev/null || echo -n $(cat source/ngc-token) | gcloud secrets create nim-ngc-token \
    --replication-policy="automatic" \
    --data-file=-

docker build -t ${IMAGE?} -f Dockerfile . 

# service account:
if [ ! -r source/sa_created ]
then
   echo create service account key
   gcloud iam service-accounts create $SERVICE_ACCOUNT_ID  \
    --description="NIM VertexAI study" \
    --display-name="NIM"

  gcloud projects add-iam-policy-binding ${PROJECTID:?} \
    --member=serviceAccount:${SERVICE_ACCOUNT_ID:?}@$PROJECTID.iam.gserviceaccount.com \
    --role="roles/aiplatform.user"

  gcloud projects add-iam-policy-binding $PROJECTID \
    --member=serviceAccount:$SERVICE_ACCOUNT_ID@$PROJECTID.iam.gserviceaccount.com \
    --role "roles/storage.objectViewer" --role "roles/viewer"

  gcloud projects add-iam-policy-binding $PROJECTID \
    --member=serviceAccount:$SERVICE_ACCOUNT_ID@$PROJECTID.iam.gserviceaccount.com \
    --role "roles/secretmanager.secretAccessor"

  gsutil iam ch serviceAccount:$SERVICE_ACCOUNT_ID@$PROJECTID.iam.gserviceaccount.com:objectViewer,legacyBucketReader $BUCKET

  touch source/sa_created
else
  echo using existing service account key
fi

echo export IMAGE=${IMAGE?} >> env
docker push ${IMAGE?}

echo =================================
echo please source ./env before run.sh
echo =================================

