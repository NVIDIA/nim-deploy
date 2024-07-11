# NVIDIA NIM on AWS Sagemaker

## AWS Sagemaker Notebook Configuration

- Login to AWS and navigate to the **Amazon Sagemaker** service
- Configure a SageMaker notebook using instance type `ml.t3.medium`
<br />
<img src="img/sm_01.png" alt="Configure a new notebook" width="550"/>

- Configure the instance with enough storage to accommodate container image pull(s) - `25GB` should be adequate
<br />
<img src="img/sm_02.png" alt="Set notebook instance parameters" width="550"/>

- Ensure IAM role `AmazonSageMakerServiceCatalogProductsUseRole` is associated with your notebook
  - Note you may need to associate additional permissions with this role to permit ECR `CreateRepository` and image push operations
- Configure the Default repository and reference this repo: https://github.com/NVIDIA/nim-deploy.git
- Click **Create notebook instance**
<br />
<img src="img/sm_03.png" alt="Set notebook permissions and git repo" width="550"/>