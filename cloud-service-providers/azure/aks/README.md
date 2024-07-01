# nim on Azure Kubernetes Service (AKS)

Azure Kubernetes Service (AKS) need to be properly created in order to be able deploy NIM on it.  There are two things need to be taken care of.  Make sure you have right GPU for NIM and right driver version as well.  Unfortunately, default GPU driver in AKS usually always a little bit too old for latest NVidia software in general.  Microsoft has no official solution for it yet.  There is a preview version of CLI to solve this issue.  We need to create AKS using preview version of CLI.  Prerequisite section talks about how to set up your local environment to enable you to create AKS from preview version of CLI.

After you are ready to create AKS, Next thing is to choose the right GPU instance.  Only L40S, A100, H100 GPU work for NIM but not all flavor.  Create AKS section has more details about this.

## Prerequisites

Please follow [Pre-rquirement instruction](./prerequisites/README.md) to get ready for AKS creation.

## Create AKS

Please follow [Create AKS instruction](./setup/README.md) to create AKS.

## Deploy NIM

Please follow [Deploy NIM instruction](../../../helm/README.md) to create AKS.
