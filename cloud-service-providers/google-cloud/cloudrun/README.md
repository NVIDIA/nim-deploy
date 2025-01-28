# NVIDIA NIM on GCP CloudRun

This repository demonstrates NVIDIA NIM deployment on Google Cloud Platform CloudRun.


#### Authenticate to Google Cloud
```
$ gcloud auth login
```
#### Create a GCS bucket

A GCS bucket provides model persistence between service restarts and helps
mitigate timeout restrictions and improves performance in the CloudRun deployment:
```
$ gcloud storage buckets create gs://my-model-data
```
#### Define NGC token

An NGC token is required for model and image artifacts. It is a good practice to
store the token in a local file system, insure it is not included in any code repository (`.gitignore`) and
is readable only to the owner; treat it as you would an `~/.ssh/id_rsa` private key.

All programmatic access to the token should be non-exposing syntax such as the following.

Create a file with your NGC token in `source/ngc-token`, then
create a secret from your NGC token for use by the NIM:
```
$ echo -n $(cat source/ngc-token) | gcloud secrets create nim-ngc-token \
    --replication-policy="automatic" \
    --data-file=-
```
#### Define Environment variables

Create an env file to place all exported environment variables.

Here is a complete example:
```
$ cat env
export SERVICE_ACCOUNT_ID=nemoms-vertex-ai-study
export PROJECTID=exploration
export PROJECTUSER=nvidia
export PROJECTNUM=123467890123
export REGION=us-central1
export GCSBUCKET=my-model-data
export SERVICE_NAME=llama-3-8b-instruct
export ARTIFACT_REGISTRY_LOCATION=us
```
#### Choose a model

Edit `Dockerfile` and place the desired model URL from NGC in the FROM statement. e.g.
```
FROM nvcr.io/nim/meta/llama3-8b-instruct:1.0.0
```
#### Create the shim container
```
$ . ./env && ./build_nim.sh
```

#### Deploy the NIM
```
$ . ./env &&  ./run.sh 
```

#### Test the NIM
```
$ export TESTURL=$(gcloud run services list --project ${PROJECTID?} \
  --region ${REGION?} | grep ${SERVICE_NAME?} | \
  awk '/https/ {print $4}')/v1/completions

$ curl -X POST  ${TESTURL?}  \
  -H 'accept: application/json' \
  -H 'Content-Type: application/json' \
  -d '{
  "model": "meta/llama3-8b-instruct",
  "prompt": "Once upon a time",
  "max_tokens": 100,
  "temperature": 1,
  "top_p": 1,
  "n": 1,
  "stream": false,
  "stop": "string",
  "frequency_penalty": 0.0
}'
```
