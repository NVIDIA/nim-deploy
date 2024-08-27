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

variable "region" {
  type        = string
  description = "GCP project region or zone"
  default     = "us-central1"
}

## network variables
variable "create_network" {
  type = bool
}

variable "network_name" {
  type = string
}

variable "subnetwork_name" {
  type = string
}

variable "subnetwork_cidr" {
  type    = string
  default = "10.128.0.0/20"
}

variable "subnetwork_region" {
  type    = string
  default = "us-central1"
}

variable "subnetwork_private_access" {
  type    = string
  default = "true"
}

variable "subnetwork_description" {
  type    = string
  default = ""
}

variable "network_secondary_ranges" {
  type    = map(list(object({ range_name = string, ip_cidr_range = string })))
  default = {}
}

## GKE variables
variable "create_cluster" {
  type    = bool
  default = true
}

variable "autopilot_cluster" {
  type = bool
}

variable "cluster_regional" {
  type    = bool
  default = false
}

variable "cluster_name" {
  type = string
}

variable "cluster_labels" {
  type        = map(any)
  description = "GKE cluster labels"
  default = {
    "created-by" = "nim-on-gke"
  }
}

variable "kubernetes_version" {
  type    = string
  default = "1.28"
}

variable "release_channel" {
  type    = string
  default = "REGULAR"
}

variable "cluster_location" {
  type = string
}

variable "ip_range_pods" {
  type    = string
  default = ""
}
variable "ip_range_services" {
  type    = string
  default = ""
}
variable "monitoring_enable_managed_prometheus" {
  type    = bool
  default = false
}
variable "gcs_fuse_csi_driver" {
  type    = bool
  default = true
}
variable "filestore_csi_driver" {
  type    = bool
  default = true
}
variable "deletion_protection" {
  type    = bool
  default = false
}
variable "master_authorized_networks" {
  type = list(object({
    cidr_block   = string
    display_name = optional(string)
  }))
  default = []
}

variable "master_ipv4_cidr_block" {
  type    = string
  default = "172.16.0.0/28"
}

variable "all_node_pools_oauth_scopes" {
  type = list(string)
  default = [
    "https://www.googleapis.com/auth/cloud-platform",
    "https://www.googleapis.com/auth/logging.write",
    "https://www.googleapis.com/auth/monitoring",
    "https://www.googleapis.com/auth/devstorage.read_only",
    "https://www.googleapis.com/auth/trace.append",
    "https://www.googleapis.com/auth/service.management.readonly",
    "https://www.googleapis.com/auth/servicecontrol",
  ]
}
variable "all_node_pools_labels" {
  type = map(string)
  default = {
    "created-by" = "nim-on-gke"
  }
}
variable "all_node_pools_metadata" {
  type = map(string)
  default = {
    disable-legacy-endpoints = "true"
  }
}
variable "all_node_pools_tags" {
  type    = list(string)
  default = ["nim-gke-node", "nim-on-gke"]
}

variable "enable_gpu" {
  type        = bool
  description = "Set to true to create GPU node pool"
  default     = true
}

variable "cpu_pools" {
  type = list(object({
    name                   = string
    machine_type           = string
    node_locations         = optional(string, "")
    autoscaling            = optional(bool, false)
    min_count              = optional(number, 1)
    max_count              = optional(number, 3)
    local_ssd_count        = optional(number, 0)
    spot                   = optional(bool, false)
    disk_size_gb           = optional(number, 100)
    disk_type              = optional(string, "pd-standard")
    image_type             = optional(string, "COS_CONTAINERD")
    enable_gcfs            = optional(bool, false)
    enable_gvnic           = optional(bool, false)
    logging_variant        = optional(string, "DEFAULT")
    auto_repair            = optional(bool, true)
    auto_upgrade           = optional(bool, true)
    create_service_account = optional(bool, true)
    preemptible            = optional(bool, false)
    initial_node_count     = optional(number, 1)
    accelerator_count      = optional(number, 0)
  }))
  default = [{
    name         = "cpu-pool"
    machine_type = "e2-standard-2"
    autoscaling  = true
    min_count    = 1
    max_count    = 3
    disk_size_gb = 100
    disk_type    = "pd-standard"
  }]
}

variable "gpu_pools" {
  type = list(object({
    name                   = string
    machine_type           = string
    node_locations         = optional(string, "")
    autoscaling            = optional(bool, false)
    min_count              = optional(number, 1)
    max_count              = optional(number, 3)
    local_ssd_count        = optional(number, 0)
    spot                   = optional(bool, false)
    disk_size_gb           = optional(number, 100)
    disk_type              = optional(string, "pd-standard")
    image_type             = optional(string, "COS_CONTAINERD")
    enable_gcfs            = optional(bool, false)
    enable_gvnic           = optional(bool, false)
    logging_variant        = optional(string, "DEFAULT")
    auto_repair            = optional(bool, true)
    auto_upgrade           = optional(bool, true)
    create_service_account = optional(bool, true)
    preemptible            = optional(bool, false)
    initial_node_count     = optional(number, 1)
    accelerator_count      = optional(number, 0)
    accelerator_type       = optional(string, "nvidia-tesla-t4")
    gpu_driver_version     = optional(string, "DEFAULT")
  }))
  default = [{
    name               = "gpu-pool"
    machine_type       = "n1-standard-16"
    autoscaling        = true
    min_count          = 1
    max_count          = 3
    disk_size_gb       = 100
    disk_type          = "pd-standard"
    accelerator_count  = 2
    accelerator_type   = "nvidia-tesla-t4"
    gpu_driver_version = "DEFAULT"
  }]
}

variable "registry_server" {
  type        = string
  default     = "nvcr.io"
  description = "Registry that hosts the NIM images"
}

variable "gpu_locations_l4" {
  type = map(string)

  # gcloud compute accelerator-types list \
  # --filter="name:nvidia-l4 AND name!=nvidia-l4-vws" \
  # --format="value(zone)" \
  # | sort
  default = {
    "asia-east1"      = "asia-east1-a,asia-east1-b,asia-east1-c"
    "asia-northeast1" = "asia-northeast1-a,asia-northeast1-c"
    "asia-northeast3" = "asia-northeast3-a,asia-northeast3-b"
    "asia-south1"     = "asia-south1-a,asia-south1-b,asia-south1-c"
    "asia-southeast1" = "asia-southeast1-a,asia-southeast1-b,asia-southeast1-c"
    "europe-west1"    = "europe-west1-b,europe-west1-c"
    "europe-west2"    = "europe-west2-a,europe-west2-b"
    "europe-west3"    = "europe-west3-b"
    "europe-west4"    = "europe-west4-a,europe-west4-b,europe-west4-c"
    "europe-west6"    = "europe-west6-b"
    "us-central1"     = "us-central1-a,us-central1-b,us-central1-c"
    "us-east1"        = "us-east1-b,us-east1-c,us-east1-d"
    "us-east4"        = "us-east4-a,us-east4-c"
    "us-west1"        = "us-west1-a,us-west1-b,us-west1-c"
    "us-west4"        = "us-west4-a,us-west4-c"
  }
}

variable "gpu_locations_a100" {
  type = map(string)
  # gcloud compute accelerator-types list \
  # --filter="name:nvidia-a100-80gb" \
  # --format="value(zone)" \
  # | sort
  default = {
    "asia-southeast1" = "asia-southeast1-c"
    "europe-west4"    = "europe-west4-a"
    "us-central1"     = "us-central1-a,us-central1-c"
    "us-east4"        = "us-east4-c"
    "us-east5"        = "us-east5-b"
    "us-east7"        = "us-east7-a"
  }
}

variable "gpu_locations_h100_80gb" {
  type = map(string)

  # gcloud compute accelerator-types list \
  # --filter="name:nvidia-h100-mega-80gb" \
  # --format="value(zone)" \
  # | sort
  default = {
    "asia-northeast1"      = "asia-northeast1-b"
    "asia-southeast1"      = "asia-southeast1-b,asia-southeast1-c"
    "australia-southeast1" = "australia-southeast1-c"
    "europe-west1"         = "europe-west1-b"
    "europe-west2"         = "europe-west2-b"
    "europe-west4"         = "europe-west4-b,europe-west4-c"
    "us-central1"          = "us-central1-a,us-central1-b,us-central1-c"
    "us-east4"             = "us-east4-a,us-east4-b,us-east4-c"
    "us-east5"             = "us-east5-a"
    "us-east7"             = "us-east7-b"
    "us-west1"             = "us-west1-a,us-west1-b"
    "us-west4"             = "us-west4-a"
  }
}