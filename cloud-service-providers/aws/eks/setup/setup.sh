#!/bin/bash
# Get CloudFormation stack outputs
echo "Fetching CloudFormation stack outputs..."
region=$(aws configure get region)
echo "Fetching current region $region"
efsoutput=$(aws cloudformation describe-stacks --stack-name efs-stack --query "Stacks[0].Outputs" --region "$region")
fileSystemId=$(echo "$efsoutput" | jq -r '.[] | select(.OutputKey=="FileSystemIdOutput") | .OutputValue')
echo "Updating storage file..."
sed -i '' "s/\${FileSystemIdOutput}/$fileSystemId/g" ./setup/storage.yaml
echo "Deploying ebs and efs storage classes." 
kubectl create -f ./setup/storage.yaml 
