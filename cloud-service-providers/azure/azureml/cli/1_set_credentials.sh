#!/bin/bash
set -x
source config.sh

CREATE_WORKSPACE=false

for i in "$@"; do
  case $i in
    --create_new_workspace) CREATE_WORKSPACE=true ;;
    -*|--*) echo "Unknown option $i"; exit 1 ;;
  esac
done

# Create new workspace
if $CREATE_WORKSPACE; then
    az ml workspace create --name $workspace --resource-group $resource_group --location $location
fi

# Assign role permission to read secrets from workspace connections
az role assignment create \
  --assignee $email_address \
  --role "Azure Machine Learning Workspace Connection Secrets Reader" \
  --scope /subscriptions/$subscription_id/resourcegroups/$resource_group/providers/Microsoft.MachineLearningServices/workspaces/$workspace

# Configure default resource group and workspace
az configure --defaults group=$resource_group workspace=$workspace
