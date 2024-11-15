#!/bin/bash
# set -x

# Define variables
source config.sh

# Get a personal access token for your workspace
echo "Getting access token for workspace"
token=$(az account get-access-token --query accessToken -o tsv)

url="https://management.azure.com/subscriptions/${subscription_id}/resourceGroups/${resource_group}/providers/Microsoft.MachineLearningServices/workspaces/${workspace}/connections/ngc?api-version=2023-08-01-preview"
verify_url="https://management.azure.com/subscriptions/${subscription_id}/resourceGroups/${resource_group}/providers/Microsoft.MachineLearningServices/workspaces/${workspace}/connections/ngc/listsecrets?api-version=2023-08-01-preview"

# Add a workspace connection to store NGC API key
echo $url
result=$(curl -X PUT "$url" \
-H "Authorization: Bearer $token" \
-H "Content-Type: application/json" \
-d '{
  "properties": {
    "authType": "CustomKeys",
    "category": "CustomKeys",
    "credentials": {
      "keys": {
        "NGC_API_KEY": "'"$ngc_api_key"'"
      }
    },
    "expiryTime": null,
    "target": "_",
    "isSharedToAll": false,
    "sharedUserList": []
  }
}')

echo "Adding NGC API key to workspace: $result"

# Verify if the key got added
echo $verify_url
verify_result=$(curl -X POST "$verify_url" \
-H "Authorization: Bearer ${token}" \
-H "Content-Type: application/json" \
-d '{}'
)

ngc_api_key_value=$(echo "$verify_result" | jq -r '.properties.credentials.keys.NGC_API_KEY')


if [ "$ngc_api_key_value" == "$ngc_api_key" ]; then
  echo "The NGC_API_KEY value matches the provided key."
else
  echo "The NGC_API_KEY value does not match the provided key."
  exit 1
fi
