#!/bin/bash
set -x
source config.sh

# Create new NIM deployment in the current workspace
echo "Deployment source ACR"
cp azureml_files/deployment.yml actual_deployment_aml.yml

# Get NGC API key from connection
connection_path="\${{azureml://connections/ngc/credentials/NGC_API_KEY}}"

# Replace placeholders in the actual_deployment_aml.yml file
sed -i '' "s|ngc_api_key_placeholder|${connection_path}|g" actual_deployment_aml.yml
sed -i '' "s|endpoint_name_placeholder|$endpoint_name|g" actual_deployment_aml.yml
sed -i '' "s|deployment_name_placeholder|$deployment_name|g" actual_deployment_aml.yml
sed -i '' "s|acr_registry_placeholder|$acr_registry_name|g" actual_deployment_aml.yml
sed -i '' "s|image_name_placeholder|$image_name|g" actual_deployment_aml.yml
sed -i '' "s|instance_type_placeholder|$instance_type|g" actual_deployment_aml.yml

# Display the modified file
cat actual_deployment_aml.yml

# Create the online deployment
echo "Creating Online Deployment ${deployment_name}"
az ml online-deployment create -f actual_deployment_aml.yml --resource-group $resource_group --workspace-name $workspace

# Clean up
rm actual_deployment_aml.yml
