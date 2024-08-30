# orm-stack-oke-helm-deployment-nim

## Getting started

This stack deploys an OKE cluster with two nodepools:
- one nodepool with flexible shapes
- one nodepool with GPU shapes

And several supporting applications using helm:
- nginx
- cert-manager
- jupyterhub

With the scope of demonstrating [nVidia NIM LLM](https://docs.nvidia.com/nim/large-language-models/latest/introduction.html) self-hosted model capabilities.

**Note:** For helm deployments it's necessary to create bastion and operator host (with the associated policy for the operator to manage the clsuter), **or** configure a cluster with public API endpoint.

In case the bastion and operator hosts are not created, is a prerequisite to have the following tools already installed and configured:
- bash
- helm
- jq
- kubectl
- oci-cli

[![Deploy to Oracle Cloud](https://oci-resourcemanager-plugin.plugins.oci.oraclecloud.com/latest/deploy-to-oracle-cloud.svg)](https://cloud.oracle.com/resourcemanager/stacks/create?zipUrl=https://github.com/ionut-sturzu/nim_on_oke/archive/refs/heads/main.zip)


## Helm Deployments

### Nginx

[Nginx](https://kubernetes.github.io/ingress-nginx/deploy/) is deployed and configured as default ingress controller.

### Cert-manager

[Cert-manager](https://cert-manager.io/docs/) is deployed to handle the configuration of TLS certificate for the configured ingress resources. Currently it's using the [staging Let's Encrypt endpoint](https://letsencrypt.org/docs/staging-environment/).

### Jupyterhub

[Jupyterhub](https://jupyterhub.readthedocs.io/en/stable/) will be accessible to the address: [https://jupyter.a.b.c.d.nip.io](https://jupyter.a.b.c.d.nip.io), where a.b.c.d is the public IP address of the load balancer associated with the NGINX ingress controller.

JupyterHub is using a dummy authentication scheme (user/password) and the access is secured using the variables:

```
jupyter_admin_user
jupyter_admin_password
```

It also supports the option to automatically clone a git repo when user is connecting and making it available under `examples` directory.

### NIM

The LLM is deployed using [NIM](https://docs.nvidia.com/nim/index.html).

Parameters:
- `nim_image_repository` and `nim_image_tag` - used to specify the container image location
- `NGC_API_KEY` - required to authenticate with NGC services

Models with large context length require GPUs with lots of memory. In case of Mistral, with a context length of 32k, the deployment on A10 instances, fails with the default container settings.

To work around this issue, we can limit the context length using the `--max-model-len` argument for the vLLM. The underlying inference engine used by NIM.

In case of Mistral models, create a file `nim_user_values_override.yaml` file with the content below and provide it as input during ORM stack variable configuration.

## How to deploy?

1. Deploy directly to OCI using the below button:

[
![Deploy to Oracle Cloud]
(https://oci-resourcemanager-plugin.plugins.oci.oraclecloud.com/latest/deploy-to-oracle-cloud.svg)
]
(https://cloud.oracle.com/resourcemanager/stacks/create
?zipUrl=https://github.com/ionut-sturzu/nim_on_oke/archive/refs/heads/main.zip)


2. Deploy via ORM
- Create a new stack
- Upload the TF configuration files
- Configure the variables
- Apply

3. Local deployment

- Create a file called `terraform.auto.tfvars` with the required values.

```
# ORM injected values

region            = "uk-london-1"
tenancy_ocid      = "ocid1.tenancy.oc1..aaaaaaaaiyavtwbz4kyu7g7b6wglllccbflmjx2lzk5nwpbme44mv54xu7dq"
compartment_ocid  = "ocid1.compartment.oc1..aaaaaaaaqi3if6t4n24qyabx5pjzlw6xovcbgugcmatavjvapyq3jfb4diqq"

# OKE Terraform module values
create_iam_resources     = false
create_iam_tag_namespace = false
ssh_public_key           = "<ssh_public_key>"

## NodePool with non-GPU shape is created by default with size 1
simple_np_flex_shape   = { "instanceShape" = "VM.Standard.E4.Flex", "ocpus" = 2, "memory" = 16 }

## NodePool with GPU shape is created by default with size 0
gpu_np_size  = 1
gpu_np_shape = "VM.GPU.A10.1"

## OKE Deployment values
cluster_name           = "oke"
vcn_name               = "oke-vcn"
compartment_id         = "ocid1.compartment.oc1..aaaaaaaaqi3if6t4n24qyabx5pjzlw6xovcbgugcmatavjvapyq3jfb4diqq"

# Jupyter Hub deployment values
jupyter_admin_user     = "oracle-ai"
jupyter_admin_password = "<admin-passowrd>"
playbooks_repo         = "https://github.com/ionut-sturzu/nim_notebooks.git"

# NIM Deployment values
nim_image_repository   = "nvcr.io/nim/meta/llama3-8b-instruct"
nim_image_tag          = "latest"
NGC_API_KEY            = "<ngc_api_key>"
```

- Execute the commands

```
terraform init
terraform plan
terraform apply
```

After the deployment is successful, get the Jupyter URL from the Terraform output and run it in the browser.
Log in with the user/password that you previously set.
Open and run the **NVIDIA_NIM_model_interaction.ipynb** notebook.

## Known Issues

If `terraform destroy` fails, manually remove the LoadBalancer resource configured for the Nginx Ingress Controller.

After `terrafrom destroy`, the block volumes corresponding to the PVCs used by the applications in the cluster won't be removed. You have to manually remove them.