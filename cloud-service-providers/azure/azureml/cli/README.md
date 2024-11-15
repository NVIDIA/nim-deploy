# Instructions for deploying NIM Models on AzureML

In this example, we will deploy the LLAMA3 8B model on AzureML. The same process can be used to deploy other NIM models. More instructions will be provided later.

You can deploy using either of the two methods:
- Method 1: [Running Azure CLI commmands inside script files](./scripts/)
- Method 2: [Running Azure CLI commands inside a jupyter notebook](./nim_azureml.ipynb)

The instructions to deploy using method 1 are provided below. If you prefer method 2 then proceed with the instructions provided in the jupyter notebook. Note that both methods execute the same Azure CLI commands, so you can use the instructions below to understand the flow of commands in the Jupyter notebook as well.

Note: We recommend to deploy using the jupyter notebook method as it is easy to follow and also contains instructions for deploying NIMs in Airgapped mode.

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

Create a new AzureML workspace with the "Azure ML Secrets Reader" role assignment. All necessary commands are provided in the `1_setup_credentials.sh` script file.

```bash
./1_setup_credentials.sh --create_new_workspace
```

The above command creates a new workspace with the workspace name provided in the `config.sh` file. If the workspace name already exists, omit the `--create_new_workspace` flag to skip the creation process and update the workspace with the necessary role assignments.

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

## Verify Your Connection

Verify your deployment using the `test_chat_completions.sh` script. Modify the URL to your endpoint URL and add the following headers:
`-H 'Authorization: Bearer <your-azureml-endpoint-token>' -H 'azureml-model-deployment: <your-azureml-model-deployment-name>'`

For example:

```bash
curl -X 'POST' \
  'https://llama3-8b-nim-endpoint-aml-1.westeurope.inference.ml.azure.com/v1/chat/completions' \
  -H 'accept: application/json' \
  -H 'Authorization: Bearer xxxxxxxxxxxxxxxxxxxxxx' \
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
  "max_tokens": 16,
  "top_p": 1,
  "n": 1,
  "stream": false,
  "stop": "\n",
  "frequency_penalty": 0.0
}'
```