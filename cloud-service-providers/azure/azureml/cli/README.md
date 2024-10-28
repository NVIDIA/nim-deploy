# Instructions for deploying NIM Models on AzureML

In this example, we will deploy the LLAMA3 8B model on AzureML. The same process can be used to deploy other NIM models. More instructions will be provided later.

**Prerequisites:**
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli)
- [Azure ML extension](https://learn.microsoft.com/en-us/azure/machine-learning/how-to-configure-cli?view=azureml-api-2&tabs=public)
- [NGC API Key](https://catalog.ngc.nvidia.com/)

## Setup Configuration

Modify the environment variables in the `./config.sh` file according to your needs. Refer to the example provided in `config_example.sh`.

```bash
vim ./config.sh
```

## Login to Azure with Your Credentials

Ensure you have the Azure CLI installed.

```bash
source config.sh
az login
az account set -s ${subscription_id}
```

## Setup AzureML Workspace

The deployment procedure requires an Azure AI Workspace with an associated Azure AI private container registry. The workspace will also require to assign the "Azure ML Secrets Reader" role assignment to the user. The user could use any pre-existent workspace with those characteristics, populating accordingly the names of the resource group, container registry name and workspace name in the config.sh file. 

The `1_setup_credentials.sh` script file, provides the role assigment, optionally it can create the necessary resource group, container registry and workspace (with the required association to the container registry, all using the names provided in the config.sh file) by the use of flags `--create_new_resource_group`, `--create_new_container_registry` and `--create_new_workspace` respectively. 

Create a new AzureML resource group, container registry and workspace (if needed) with the "Azure ML Secrets Reader" role assignment. All necessary commands are provided in the `1_setup_credentials.sh` script file.

```bash
./1_setup_credentials.sh --create_new_resource --create_new_container_registry --create_new_workspace
```

## Store NGC API Key for Use in the AzureML Deployment

The NGC API Key needs to be stored within Azure so the AzureML workspace can access it during deployment. The API key is required to pull the correct model from the NGC model catalog. The key can be stored in Azure Key Vault or provided as a workspace connection to the AzureML workspace.

### Option 1: Store Secret in Azure Key Vault

Create a new Azure Key Vault and securely store the NGC API Key in it. All required commands are provided in the `create_key_vault.sh` script file. It also creates a read access role assignment to enable reading the key from any AzureML endpoint within the workspace.

```bash
./2_create_key_vault.sh
```

### Option 2: Store Key as a Workspace Connection (Recommended)

Create a new workspace connection to store the NGC API Key as a custom credential type. All required commands are provided in the `2_provide_ngc_connection.sh` script.

```bash
./2_provide_ngc_connection.sh
```

This script stores the NGC API Key as a workspace connection credential and verifies if the provided workspace can access it.

## Save NIM Container in Your Container Registry

Pull the NIM Docker container for the model specified in the `config.sh` file. Create another Docker container wrapped around the NIM container for deployment in AzureML and push this new container to an Azure container registry that can be accessed by your AzureML endpoint. All required commands are provided in the `3_save_nim_container.sh` script.

```bash
./3_save_nim_container.sh
```

## Create Managed Online Endpoint

Create an AzureML endpoint to host your NIM deployment. Commands are provided in the `4_create_endpoint.sh` script.

```bash
./4_create_endpoint.sh
```

This command creates an endpoint with the name provided in the `config.sh` file.

## Create AzureML Deployment of the NIM Container

Create an AzureML deployment with the NIM container obtained from the provided Azure container registry. 

**Note:** Ensure that the provided Azure Container Registry (ACR) can be accessed by your AzureML endpoint by checking if your endpoint has the "AcrPull" role assignment on the ACR. [Refer to the documentation](https://learn.microsoft.com/en-us/azure/container-registry/container-registry-roles?tabs=azure-cli).

Required commands are provided in the `5_create_deployment.sh` script.

```bash
./5_create_deployment.sh
```

## Querying the model

Verify your deployment using the `test_chat_completions.sh` script. Modify the URL to your endpoint URL and add the following headers:
`-H 'Authorization: Bearer <your-azureml-endpoint-token>' -H 'azureml-model-deployment: <your-azureml-model-deployment-name>'`

For example:

```bash
curl -X 'POST' \
  'https://llama3-8b-nim-endpoint-aml-1.southcentralus.inference.ml.azure.com/v1/chat/completions' \
  -H 'accept: application/json' \
  -H 'Authorization: Bearer XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX' \
  -H 'azureml-model-deployment: llama3-8b-nim-deployment-aml-1' \
  -H 'Content-Type: application/json' \
  -d '{
  "messages": [
    {
      "content": "You are a polite and respectful chatbot helping people plan a vacation.",
      "role": "system"
    },
    {
      "content": "What should I do for a 4 day vacation in Spain?",
      "role": "user"
    }
  ],
  "model": "meta/llama3-8b-instruct",
  "max_tokens": 400,
  "top_p": 1,
  "n": 1,
  "stream": false,
  "frequency_penalty": 0.0
}'
```

