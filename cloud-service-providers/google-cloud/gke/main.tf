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


module "bootstrap" {
  source     = "./terraform/modules/bootstrap"
  project_id = var.project_id
  services   = var.services
}

#data "terraform_remote_state" "bootstrap" {
#  backend = "local"
#
#  config = {
#    path = "../1-bootstrap/terraform.tfstate"
#  }
#}

data "google_project" "current" {
  project_id = var.project_id
}

locals {
  project_id = var.project_id
}

locals {

  ## GPU locations for all supported GPU types
  all_gpu_locations = {
    "nvidia-l4"             = var.gpu_locations_l4
    "nvidia-a100-80gb"      = var.gpu_locations_a100
    "nvidia-h100-mega-80gb" = var.gpu_locations_h100_80gb
  }

  gpu_location = lookup(local.all_gpu_locations, var.gpu_pools[0].accelerator_type, {})
}

data "google_compute_network" "existing-network" {
  count   = var.create_network ? 0 : 1
  name    = var.network_name
  project = local.project_id
}

data "google_compute_subnetwork" "subnetwork" {
  count   = var.create_network ? 0 : 1
  name    = var.subnetwork_name
  region  = var.subnetwork_region
  project = local.project_id
}

module "custom-network" {
  source       = "./terraform/modules/gcp-network"
  count        = var.create_network ? 1 : 0
  project_id   = local.project_id
  network_name = var.network_name
  create_psa   = true

  subnets = [
    {
      subnet_name           = var.subnetwork_name
      subnet_ip             = var.subnetwork_cidr
      subnet_region         = var.subnetwork_region
      subnet_private_access = var.subnetwork_private_access
      description           = var.subnetwork_description
    }
  ]
}

locals {
  network_name    = var.create_network ? module.custom-network[0].network_name : var.network_name
  subnetwork_name = var.create_network ? module.custom-network[0].subnets_names[0] : var.subnetwork_name
  subnetwork_cidr = var.create_network ? module.custom-network[0].subnets_ips[0] : data.google_compute_subnetwork.subnetwork[0].ip_cidr_range
  region          = length(split("-", var.cluster_location)) == 2 ? var.cluster_location : ""
  regional        = local.region != "" ? true : false
  # zone needs to be set even for regional clusters, otherwise this module picks random zones that don't have GPU availability:
  # https://github.com/terraform-google-modules/terraform-google-kubernetes-engine/blob/af354afdf13b336014cefbfe8f848e52c17d4415/main.tf#L46 
  # zone = length(split("-", local.region)) > 2 ? split(",", local.region) : split(",", local.gpu_location[local.region])
  zone = length(split("-", var.cluster_location)) > 2 ? split(",", var.cluster_location) : split(",", local.gpu_location[local.region])
  # Update gpu_pools with node_locations according to region and zone gpu availibility, if not provided
  gpu_pools = [for elm in var.gpu_pools : (local.regional && contains(keys(local.gpu_location), local.region) && elm["node_locations"] == "") ? merge(elm, { "node_locations" : local.gpu_location[local.region] }) : elm]
}

module "gke-cluster" {
  count      = var.create_cluster && !var.autopilot_cluster ? 1 : 0
  source     = "./terraform/modules/gke-cluster"
  project_id = local.project_id

  ## network values
  network_name    = local.network_name
  subnetwork_name = local.subnetwork_name

  ## gke variables
  cluster_regional                     = local.regional
  cluster_region                       = local.region
  cluster_zones                        = local.zone
  cluster_name                         = var.cluster_name
  cluster_labels                       = var.cluster_labels
  kubernetes_version                   = var.kubernetes_version
  release_channel                      = var.release_channel
  ip_range_pods                        = var.ip_range_pods
  ip_range_services                    = var.ip_range_services
  monitoring_enable_managed_prometheus = var.monitoring_enable_managed_prometheus
  gcs_fuse_csi_driver                  = var.gcs_fuse_csi_driver
  master_authorized_networks           = var.master_authorized_networks
  deletion_protection                  = var.deletion_protection

  ## pools config variables
  cpu_pools                   = var.cpu_pools
  enable_gpu                  = var.enable_gpu
  gpu_pools                   = local.gpu_pools
  all_node_pools_oauth_scopes = var.all_node_pools_oauth_scopes
  all_node_pools_labels       = var.all_node_pools_labels
  all_node_pools_metadata     = var.all_node_pools_metadata
  all_node_pools_tags         = var.all_node_pools_tags
  depends_on                  = [module.custom-network]
}

/*
resource "null_resource" "kubectl_config" {
  provisioner "local-exec" {
    command = <<EOT
    gcloud container clusters get-credentials ${var.cluster_name} \
        --region ${var.cluster_location}
    EOT
  }
  depends_on = [module.gke-cluster]
}

#provider "kubernetes" {
#  config_path = "~/.kube/config"
#}

provider "kubernetes" {
  host                   = "https://${module.gke-cluster[0].endpoint}"
  #cluster_ca_certificate = base64decode(module.gke-cluster[0].master_auth.0.cluster_ca_certificate) 

  # No need for config_path or config_context when using google provider for authentication
  config_path    = ""
  config_context = ""

  # Authentication via Google Cloud SDK
  token                  = data.google_client_config.current.access_token
}

data "google_client_config" "current" {}

*/

/*
locals {
  cluster_name     = var.cluster_name
  cluster_location = var.cluster_location
}


provider "helm" {
  kubernetes {
    host                   = "https://${module.gke-cluster[0].endpoint}"
    #cluster_ca_certificate = base64decode(module.gke-cluster.master_auth[0].cluster_ca_certificate)
    config_path    = ""
    config_context = ""

    # Authentication via Google Cloud SDK
    token                  = data.google_client_config.current.access_token
  }
}

#provider "helm" {
#  kubernetes {
#    config_path = "~/.kube/config"
#  }

#  kubernetes {
#      host                   = "https://${module.gke-cluster[0].endpoint}"
#      token                  = data.google_client_config.current.access_token
#      #cluster_ca_certificate = base64decode(module.gke-cluster[0].cluster_ca_certificate)
#      cluster_ca_certificate = module.gke-cluster.master_auth[0].cluster_ca_certificate
#    }
#}

resource "null_resource" "get-credentials" {
  provisioner "local-exec" {
    command = "gcloud container clusters get-credentials ${local.cluster_name} --region ${local.cluster_location}"
  }
}

resource "kubernetes_namespace" "nim" {
  metadata {
    name = "nim"
  }
}

resource "kubernetes_secret" "registry_secret" {
  metadata {
    name      = "registry-secret"
    namespace = "nim"
  }

  type = "kubernetes.io/dockerconfigjson"

  data = {
    ".dockerconfigjson" = jsonencode({
      "auths" = {
        "${var.registry_server}" = {
          "username" = var.ngc_username
          "password" = var.ngc_api_key
          "auth"     = base64encode("${var.ngc_username}:${var.ngc_api_key}")
        }
      }
    })
  }

  depends_on = [kubernetes_namespace.nim]
}

resource "kubernetes_secret" "ngc_api" {
  metadata {
    name      = "ngc-api"
    namespace = "nim"
  }

  type = "Opaque" # Generic secret type

  data = {
    "NGC_API_KEY" = var.ngc_api_key
  }

  depends_on = [kubernetes_namespace.nim]
}

resource "helm_release" "my_nim" {
  name       = "my-nim"
  namespace  = "nim"
  repository = "nim-llm"
  #chart      = "../../../../../helm/nim-llm/"
  chart      = "../../../helm/nim-llm/"

  values = [
    file("./helm/custom-values.yaml")
  ]

  set {
    name  = "image.repository"
    value = var.repository
  }

  set {
    name  = "image.tag"
    value = var.tag
  }

  set {
    name  = "model.name"
    value = var.model_name
  }

  set {
    name  = "resources.limits.nvidia\\.com/gpu"
    value = var.gpu_limits
  }

  depends_on = [kubernetes_namespace.nim]

  timeout = 900
  wait    = true
}
*/