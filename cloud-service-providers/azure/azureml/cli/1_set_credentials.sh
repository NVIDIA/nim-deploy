#!/bin/bash
set -x
source config.sh

CREATE_RESOURCE_GROUP=false
CREATE_CONTAINER_REGISTRY=false
CREATE_WORKSPACE=false

for i in "$@"; do
  case $i in
    --create_new_resource) CREATE_RESOURCE_GROUP=true ;;
    -*|--*) echo "Unknown option $i"; exit 1 ;;
  esac
  case $i in
    --create_new_container_registry) CREATE_CONTAINER_REGISTRY=true ;;
    -*|--*) echo "Unknown option $i"; exit 1 ;;
  esac
  case $i in
    --create_new_workspace) CREATE_WORKSPACE=true ;;
    -*|--*) echo "Unknown option $i"; exit 1 ;;
  esac
done

# Create new resource group
if $CREATE_RESOURCE_GROUP then
    az group create --name $resource_group --location $location
fi

# Create new container registry
if $CREATE_CONTAINER_REGISTRY then
    az acr create --resource-group $resource_group --name $acr_registry_name --sku Basic
fi

# Create new workspace
if $CREATE_WORKSPACE; then
    az ml workspace create --name $workspace --resource-group $resource_group --location $location --container-registry /subscriptions/${subscription_id}/resourceGroups/${resource_group}/providers/Microsoft.ContainerRegistry/registries/${acr_registry_name}
fi

# Assign role permission to read secrets from workspace connections
az role assignment create \
  --assignee $email_address \
  --role "Azure Machine Learning Workspace Connection Secrets Reader" \
  --scope /subscriptions/$subscription_id/resourcegroups/$resource_group/providers/Microsoft.MachineLearningServices/workspaces/$workspace

# Configure default resource group and workspace
az configure --defaults group=$resource_group workspace=$workspace
