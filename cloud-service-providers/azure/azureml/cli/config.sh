#!/bin/bash

# Copyright (c) 2021, NVIDIA CORPORATION. All rights reserved.
# 
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
# 
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

# AzureML Workspace and corresponding container registry related information
subscription_id="ab221ca4-f098-422d-ab2f-5073b3851e68"
resource_group="NIMDeploDemo_rg"
workspace="NIMDeployDemo_ws"
location="southcentralus"

# Azure keyvault creation related information
ngc_api_key="azdwMG00YXNicWVzcnFrN3ZqMnFtcTAyb2U6NzRhZTUxODgtNzBhMS00ZDIzLThlODktZWNkNGQwMTE5OWRh"
keyvault_name="NGC-Credentials"
email_address="mreyesgomez@nvidia.com"

# Container related information
 # NOTE: Verify that your AML workspace can access this ACR

acr_registry_name="nimdeploydemowsacr"

image_name="llama3_8b_nim_ncd"
ngc_container="nvcr.io/nim/meta/llama3-8b-instruct:1.0.3"

# Endpoint related information
endpoint_name="llama3-8b-nim-endpoint-aml-1"

# Deployment related information
deployment_name="llama3-8b-nim-deployment-aml-1"
instance_type="Standard_NC48ads_A100_v4"
