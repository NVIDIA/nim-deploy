# NIM on Oracle Cloud Infrastructure (OCI) OKE

To deploy NIM on Oracle Cloud Infrastructure (OCI) successfully, it’s crucial to choose the correct GPU shapes and ensure that the appropriate NVIDIA drivers are installed. 

When you select a GPU shape for a managed node pool or self-managed node in OKE, you must also select a compatible Oracle Linux GPU image that has the CUDA libraries pre-installed. The names of compatible images include 'GPU'. OCI offers Oracle Linux (OEL) providing the possibility to use pre-installed GPU drivers. This simplifies the deployment process for NIM.


## Prerequisites

Please follow [Pre-rquirement instruction](./prerequisites/README.md) to get ready for OKE creation.

## Create OKE

Please follow [Create OKE instruction](./setup/README.md) to create OKE.

## Deploy NIM

Please follow [Deploy NIM instruction](../../../helm/README.md) to deploy NIM.
