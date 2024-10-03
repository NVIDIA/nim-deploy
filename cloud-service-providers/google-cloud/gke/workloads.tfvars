# Copyright 2024 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


project_id = "<Enter GCP Project ID>>"

##common variables
cluster_name         = "nim-demo-gke"
#cluster_location     = "us-east4-a"
autopilot_cluster    = false ## true = autopilot cluster, false = standard cluster
kubernetes_namespace = "nim"
create_cluster       = true

## network values
create_network  = true
network_name    = "nim-demo-vpc"
subnetwork_name = "nim-demo-subnet"
subnetwork_cidr = "10.100.0.0/16"

create_service_account = false

## CPU node pool values
cpu_pools = [{
  name                   = "cpu-pool"
  machine_type           = "e2-standard-2"
  autoscaling            = false
  min_count              = 1
  max_count              = 3
  enable_gcfs            = true
  disk_size_gb           = 100
  disk_type              = "pd-standard"
  create_service_account = false
}]

## GPU node pool values
## make sure required gpu quotas are available in that region
enable_gpu = true
gpu_pools = [
  {
    name                   = "gpu-pool"
    machine_type           = "g2-standard-4"
    accelerator_type       = "nvidia-l4"
    accelerator_count      = 1
    autoscaling            = true
    min_count              = 1
    max_count              = 3
    disk_size_gb           = 100
    disk_type              = "pd-balanced"
    enable_gcfs            = true
    logging_variant        = "DEFAULT"
    gpu_driver_version     = "DEFAULT"
    create_service_account = false
}]

## NIM specific values
ngc_api_key     = "<NGC API Key>"

#registry_server = "nvcr.io"
registry_server = "us-docker.pkg.dev/nvidia-vgpu-public"
repository = "nim-gke"

model_name      = "llama3-8b-instruct"
gpu_limits      = 1
region_based_vm = "L4 us-east4 g2-standard-24"