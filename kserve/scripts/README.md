This directory containers helper scripts and files for setting up NIM on KServe.


# nim-kserve
Temporary location for documentation an examples showcasing how to deploy and manage NVIDIA NIM with KServe


# Setup Script

This script will do basic setup of a KServe cluster, including the following steps:

1. Create an API key in NGC and add this as a secret in the namespace being used to launch NIMs. This can be accomplished by running:

2. Enable the `NodeSelector` feature of KServe to allow a NIM to request different GPU types.

3. Create all the NIM runtimes in the K8s cluster. Note these will not be used until an InferenceService is created in a later step.

4. Create a PVC called `nim-pvc` in the cluster and download the models into it.

An example PVC is provided in the `scripts` directory using `local-storage`, it is recommended to use a better `StorageClass` that can share model files across nodes.

5. TODO: Automate the NIM Cache creation