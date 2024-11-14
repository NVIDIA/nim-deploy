#!/bin/bash
set -x
source config.sh

# Create new endpoint in this workspace
cp azureml_files/endpoint.yml actual_endpoint_aml.yml
# sed -i "s/endpoint_name_placeholder/${endpoint_name}/g" actual_endpoint_aml.yml
sed -i '' "s|endpoint_name_placeholder|$endpoint_name|g" actual_endpoint_aml.yml
echo "Creating Online Endpoint ${endpoint_name}"
az ml online-endpoint create -f actual_endpoint_aml.yml --resource-group $resource_group --workspace-name $workspace
rm actual_endpoint_aml.yml
