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


##common variables
cluster_name      = "nim-demo-gke"
cluster_location  = "<GCP Zone for zonal cluster / GCP Region for regional cluster>"
autopilot_cluster = false ## true = autopilot cluster, false = standard cluster

## network values
create_network    = true
network_name      = "nim-demo-vpc"
subnetwork_name   = "nim-demo-subnet"
subnetwork_region = "<GCP region>"
subnetwork_cidr   = "10.100.0.0/16"

## CPU node pool values
cpu_pools = [{
  name         = "cpu-pool"
  machine_type = "e2-standard-2"
  autoscaling  = false
  min_count    = 1
  max_count    = 3
  enable_gcfs  = true
  disk_size_gb = 100
  disk_type    = "pd-standard"
}]

## GPU node pool values
## make sure required gpu quotas are available in that region
enable_gpu = true
gpu_pools = [
  {
    name               = "gpu-pool"
    machine_type       = "g2-standard-4"
    accelerator_type   = "nvidia-l4"
    accelerator_count  = 1
    autoscaling        = true
    min_count          = 1
    max_count          = 3
    disk_size_gb       = 100
    disk_type          = "pd-balanced"
    enable_gcfs        = true
    logging_variant    = "DEFAULT"
    gpu_driver_version = "DEFAULT"
}]