---
title: "Deploy NVIDIA NIM Microservices on Amazon Elastic Kubernetes Service: Beginner Workshop"
weight: 0
---

In this workshop, you will learn how to deploy and manage containerized AI models using <a href="https://www.nvidia.com/en-us/ai/" target="_blank">NVIDIA NIM</a> on Amazon <a href="https://aws.amazon.com/eks/" target="_blank">Elastic Kubernetes Service (EKS)</a>. This workshop is designed for developers and data scientists who are looking to:

* Simplify AI inference deployment: Learn how to leverage a pre-built NIM for faster and easier deployment of AI models into production on EKS
* Optimize performance on NVIDIA GPUs: Gain hands-on experience with deploying NIM that leverage NVIDIA TensorRT for optimized inference on GPUs within your EKS cluster
* Scale AI inference workloads: Explore how to leverage Kubernetes for autoscaling and managing compute resources for your deployed NIM based on demand

![Project Preview](/imgs/AWS_NVIDIA_Diagram_NIM_EKS_Light.png)

---

**Target Audience:** Developers, DevOps Engineers, Data Scientists

**Use Cases:** AI Inference, Scaling with Kubernetes

---

## What You'll Learn

By the end of this workshop, you'll have hands-on experience with:

* Deploying NIM Microservices on EKS: Deploy pre-built NVIDIA NIM for various inference tasks onto your EKS cluster
* Managing NIM deployments: Use kubectl commands to manage, monitor, and scale your deployed NIM
* Scaling inference workloads: Utilize Kubernetes features for autoscaling your NIM deployments based on traffic demands

## Learn the Components
### **GPUs in Elastic Kubernetes Service (EKS)**
[GPUs](https://aws.amazon.com/ec2/instance-types/#Accelerated_Computing) let you accelerate specific workloads running on your nodes such as machine learning and data processing. EKS provides a range of machine type options for node configuration, including machine types with [NVIDIA H100, A100, L40S, L4 and more](https://aws.amazon.com/ec2/instance-types/#Accelerated_Computing).

### **NVIDIA NIM Microservices**
[NVIDIA NIM](https://www.nvidia.com/en-us/ai/) are a set of easy-to-use inference microservices for accelerating the deployment of foundation models on any cloud or data center and helping to keep your data secure.

### **NVIDIA AI Enterprise**
[NVIDIA AI Enterprise](https://www.nvidia.com/en-us/data-center/products/ai-enterprise/) is an end-to-end, cloud-native software platform that accelerates data science pipelines and streamlines development and deployment of production-grade co-pilots and other generative AI applications. Available through the [AWS Marketplace](https://aws.amazon.com/marketplace/pp/prodview-ozgjkov6vq3l6?sr=0-1&ref_=beagle&applicationId=AWSMPContessa).

## What You'll Need
* AWS Account - This account will require:
   * Permissions to deploy EC2 instances in an EKS Cluster
   * Service quota (1 or more) to launch EC2 G6 Type instances
   * Minimum EC2 instance type: g6.4xlarge
* An NVIDIA API Key: 
   * Click this <a href="https://nvdam.widen.net/s/tmbxdkxmmd/create-build-account-and-api-key-3">link</a>, and follow the instructions on how to create an account and generate an API Key. An API key will be required to download the NVIDIA NIM.



<i>**Request Quota for Amazon EC2 G Type"**

NVIDIA NIM require an Amazon EC2 Accelerated Computing instance (G type). You will most likely need to request a service quota increase for this. In your AWS account, navigate to Service Quotas, then AWS Services, search and select Amazon Elastic Cloud Compute (EC2). Then search and select “Running On-Demand G and VT instances”. If your account has less than 8 vCPUs for this instance type, request a quota increase of 8 or more EC2 vCPUs. </i>


*Note: Costs may vary depending upon the region in which you deploy the stack, and how much time you spend exploring the NIM containers outside of the prescribed workshop steps. When you are not working on the EC2 instance, make sure to shut it down so you do not incur costs of the instance running.*

## Prerequisites

1. Please make sure you have the <a href="https://nvdam.widen.net/s/tmbxdkxmmd/create-build-account-and-api-key-3">NVIDIA API key</a> ready, to download the NIM docker images
2. To prepare for the command-line management of your Amazon EKS clusters, you need to install several tools. Use the Cloud Shell Terminal in the AWS Console, and follow the instructions below to install the tools that will enable you to set up credentials, create and modify clusters, and work with clusters once they are running.
    * Please make sure to install <a href="https://docs.aws.amazon.com/eks/latest/eksctl/installation.html">eksctl</a> (following the "For Unix" instructions) and <a href="https://helm.sh/docs/intro/install/#from-script"> Helm</a> (following the "From Script" instructions) 

## Task 1: Set up the necessary Infrastructure

[Amazon Elastic Kubernetes Service](https://docs.aws.amazon.com/eks/latest/userguide/what-is-eks.html) (Amazon EKS) is the premiere platform for running [Kubernetes](https://kubernetes.io/docs/concepts/overview/) clusters.
Amazon EKS simplifies building, securing, and maintaining Kubernetes clusters. It can be more cost effective at providing enough resources to meet peak demand than maintaining your own data centers.

In order to deploy an NVIDIA NIM on an EKS Cluster, we need to create the right resources and deploy the necessary tools. 

  
---

**Get started with Amazon EKS**

As described in this [User Guide](https://docs.aws.amazon.com/eks/latest/userguide/getting-started.html) on how to get started, there are two "getting started" guides available for creating a new Kubernetes cluster with nodes in Amazon EKS.

For the purpose of this workshop, we will be using `eksctl` - a simple command line utility for creating and managing Kubernetes clusters on Amazon EKS. 

Please follow the instructions below, to create an EKS Cluster with GPU-based instances.

At the end of the tutorial, you will have a running Amazon EKS cluster that you can deploy applications to. This is the fastest and simplest way to get started with Amazon EKS.


---
1. **Create Cluster**

    1.   Open the AWS CloudShell:

    ![Open_Terminal](/./imgs/open_terminal.png)

    2. Specify the following parameters:
    
    ```
        export CLUSTER_NAME=nim-eks-workshop
        export CLUSTER_NODE_TYPE=g6.4xlarge
        export NODE_COUNT=1
    ```

    3. Create EKS Cluster:
    ```
    eksctl create cluster --name=$CLUSTER_NAME --node-type=$CLUSTER_NODE_TYPE --nodes=$NODE_COUNT
    ```
    <i>Please note, cluster creation takes several minutes. During creation you’ll see several lines of output.</i>

---

2. **Verify the creation of the Cluster**
  
    1. In the search bar at the top, type in "Cloudformation" and select the first result
    ![CloudFormation_Search](/./imgs/CloudFormation_Search.png)
    
    2. In the "Stacks" tab, verify that all Stacks have been created successfully and the status is "CREATE_COMPLETE"

    ![Stacks_Complete](/./imgs/Stack_Complete.png)
    
    3. In the search bar at the top, type in "EKS" and select "Elastic Kubernetes Service"

    ![EKS_Search](/./imgs/eks_search_result.png)

    
    4. In the "Clusters" tab, wait until the value in column "Status" changes to "Active" with a green check mark

    
    ![Cluster_Runnning](/./imgs/cluster_running.png)

    5. Click on the "nim-eks-workshop" link, then click on the "Compute" tab. Verify that there is a Node group running, with status "Active", under the "Node Groups" section

    ![Cluster_Runnning](/./imgs/Node_group_active.png)
    
    
    6. In the CloudShell terminal, execute the below command to verify the nodes are visible

    ```
    kubectl get nodes -o wide
    ```

    The result should be something similar to:

    ![Get_nodes_result](/./imgs/Get_nodes_result.png)

---

2. **(OPTIONAL) Setup Storage Configuration**

    
    1. Enable OIDC for the cluster

       ```
        eksctl utils associate-iam-oidc-provider --cluster $CLUSTER_NAME --approve
       ```                 
    
    2. Create an IAM Role for the EBS CSI Driver

        ```
         eksctl create iamserviceaccount \
          --name ebs-csi-controller-sa \
          --namespace kube-system \
          --cluster $CLUSTER_NAME \
          --role-name AmazonEKS_EBS_CSI_DriverRole \
          --attach-policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy \
          --approve
        ```
   
    3. Install EBS CSI driver

       ```
        eksctl create addon \
         --name "aws-ebs-csi-driver" \
         --cluster $CLUSTER_NAME\
         --region=$AWS_DEFAULT_REGION\
         --service-account-role-arn arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):role/AmazonEKS_EBS_CSI_DriverRole\
         --force
        ```                    
   
    4. Get status of the driver, must be STATUS=ACTIVE

        ```
        eksctl get addon \
         --name "aws-ebs-csi-driver" \
         --region $AWS_DEFAULT_REGION \
         --cluster $CLUSTER_NAME
        ```

    5. Create the EBS storage class file

       ```
       cat <<EOF >  storage.yaml
       apiVersion: storage.k8s.io/v1
       kind: StorageClass
       metadata:
           name: ebs-sc
       provisioner: ebs.csi.aws.com
       volumeBindingMode: WaitForFirstConsumer
       EOF
       ```

    6. Deploy the EBS storage class 

       ```
       kubectl create -f storage.yaml 
       ```

## Task 2: Deploy the NIM container

1. **Open your Terminal**

![Open_Terminal](/./imgs/open_terminal.png)

2. **Configure NVIDIA API Key**

In order to get started with NIM, we’ll need to make sure we have access to an [NVIDIA API key](https://build.nvidia.com/settings/api-keys). We can export this key to be used an environment variable, by pasting the below in your terminal.

**Replace \<YOUR NVIDIA API KEY> with the NVIDIA API Key you created earlier (please remove the \< and \> too)**

```
export NGC_CLI_API_KEY=<YOUR NVIDIA API KEY>
```

3. **Fetch NIM LLM Helm Chart**

Once we’ve set the NVIDIA API key, we’ll need to fetch the NIM LLM Helm chart from NGC
```
helm fetch https://helm.ngc.nvidia.com/nim/charts/nim-llm-1.7.0.tgz --username='$oauthtoken' --password=$NGC_CLI_API_KEY
```

4. **Create a NIM Namespace**

Namespaces are used to manage resources for a specific service or set of services in kubernetes.
It’s best practice to ensure all the resources for a given service are managed in its corresponding namespace. 

We create a namespace for our NIM service using the following kubectl command:
```
kubectl create namespace nim
```

5. **Configure Secrets**

In order to configure and launch an NVIDIA NIM, it is important to configure the secrets we’ll need to pull all the model artifacts directly from NGC. 

This can be done using your NVIDIA API key:
```
kubectl create secret docker-registry registry-secret --docker-server=nvcr.io --docker-username='$oauthtoken'     --docker-password=$NGC_CLI_API_KEY -n nim

kubectl create secret generic ngc-api --from-literal=NGC_API_KEY=$NGC_CLI_API_KEY -n nim
```

6. **Setup NIM Configuration**

We deploy the LLama 3 8B instruct NIM for this exercise. In order to configure our NIM, we create a custom value file where we configure the deployment:

```bash
# create nim_custom_value.yaml manifest
cat <<EOF > nim_custom_value.yaml
image:
  repository: "nvcr.io/nim/meta/llama3-8b-instruct" # container location
  tag: 1.0.0 # NIM version you want to deploy
model:
  ngcAPISecret: ngc-api  # name of a secret in the cluster that includes a key named NGC_CLI_API_KEY and is an NVIDIA API key
persistence:
  enabled: true
  storageClass: "ebs-sc"
  accessMode: ReadWriteOnce
  stsPersistentVolumeClaimRetentionPolicy:
      whenDeleted: Retain
      whenScaled: Retain
imagePullSecrets:
  - name: registry-secret # name of a secret used to pull nvcr.io images, see https://kubernetes.io/docs/tasks/    configure-pod-container/pull-image-private-registry/
EOF
```

**(OPTIONAL)**
If you deployed the optional storage setup from the previous Task, run this command instead:

```bash
# create nim_custom_value.yaml manifest
cat <<EOF > nim_custom_value.yaml
image:
  repository: "nvcr.io/nim/meta/llama3-8b-instruct" # container location
  tag: 1.0.0 # NIM version you want to deploy
model:
  ngcAPISecret: ngc-api  # name of a secret in the cluster that includes a key named NGC_CLI_API_KEY and is an NVIDIA API key
persistence:
  enabled: true
  storageClass: "ebs-sc"
  accessMode: ReadWriteOnce
  stsPersistentVolumeClaimRetentionPolicy:
      whenDeleted: Retain
      whenScaled: Retain
imagePullSecrets:
    - name: registry-secret # name of a secret used to pull nvcr.io images, see https://kubernetes.io/docs/tasks/    configure-pod-container/pull-image-private-registry/
EOF
```


7. **Launching NIM deployment**
   
Now we can deploy our NIM microservice to the namespace we created:

```
helm install my-nim nim-llm-1.7.0.tgz -f nim_custom_value.yaml --namespace nim
```

## Task 3: Run Inference using the NIM Container

1. **Get Pod Status**

If you are operating on a fresh persistent volume or similar, you may have to wait a little while for the model to download.

You can check the status of your deployment by opening your terminal and running

```
kubectl get pods -n nim
```
And check that the pods have become "Ready".

2. **Start Port Forwarding**

We can make inference requests to see what type of feedback we’ll receive from the NIM service. 

In order to do this, we enable port forwarding on the service to be able to access the NIM from our localhost on port 8000

```
kubectl -n nim port-forward service/my-nim-nim-llm 8000:8000
```
3. **Send a Request**

Next, we can open **another terminal tab**

![New_shell_terminal](/./imgs/Get_nodes_result.png)


and try the following request:
```
curl -X 'POST' \
  'http://localhost:8000/v1/chat/completions' \
  -H 'accept: application/json' \
  -H 'Content-Type: application/json' \
  -d '{
  "messages": [
    {
      "content": "You are a polite and respectful chatbot helping people plan a vacation.",
      "role": "system"
    },
    {
      "content": "What should I do for a 4 day vacation in Greece?",
      "role": "user"
    }
  ],
  "model": "meta/llama3-8b-instruct",
  "max_tokens": 128,
  "top_p": 1,
  "n": 1,
  "stream": false,
  "stop": "\n",
  "frequency_penalty": 0.0
}'
```

If you get a chat completion from the NIM service, that means the service is working as expected!

## Cleanup

To teardown and delete the deployed infrastructure from your AWS account execute the below command in the cloud shell terminal:

```
eksctl delete cluster --name=$CLUSTER_NAME --disable-nodegroup-eviction --wait
```

<i>Please note, cluster and nodegroup deletion takes several minutes. During this process, you’ll see several lines of output.</i>

---



