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

provider "google" {
  project = var.project_id
 
  default_labels = var.goog_labels
}

module "bootstrap" {
  source     = "./terraform/modules/bootstrap"
  project_id = var.project_id
  services   = var.services
}

data "google_project" "current" {
  project_id = var.project_id
}

data "google_client_config" "default" {}

resource "random_uuid" "unique_res_id" {}

locals {

  project_id = var.project_id
  ## GPU locations for all supported GPU types
  all_gpu_locations = {
    "nvidia-l4"             = var.gpu_locations_l4
    "nvidia-a100-80gb"      = var.gpu_locations_a100
    "nvidia-h100-80gb" = var.gpu_locations_h100_80gb
  }

  region_vm        = split(" ", var.region_based_vm)
  cluster_location = local.region_vm[length(local.region_vm) - 2]
  machine_type = {
    "machine_type" = local.region_vm[length(local.region_vm) - 1]
  }
  gpu_type = lookup(var.vm_gpu_spec_list, local.region_vm[length(local.region_vm) - 1])

  gpu_location = lookup(local.all_gpu_locations, local.gpu_type.accelerator_type, {})
  
  accelerator_type = {
    "accelerator_type" = local.gpu_type.accelerator_type
  }  

  accelerator_count = {
    "accelerator_count" = local.gpu_type.accelerator_count
  }

  local_ssd_ephemeral_storage_count = {
    "local_ssd_ephemeral_storage_count" = local.gpu_type.local_ssd_count
  }

  unique_res_id_short = substr(random_uuid.unique_res_id.result, 0, 8)
}

data "google_compute_network" "existing-network" {
  count = var.create_network ? 0 : 1
  
  name    = lower(replace("${var.cluster_name}-${var.network_name}-${local.unique_res_id_short}", "/[^a-zA-Z0-9-]/", "-"))
  project = local.project_id
}

data "google_compute_subnetwork" "subnetwork" {
  count = var.create_network ? 0 : 1
  
  name    = lower(replace("${var.cluster_name}-${var.subnetwork_name}-${local.unique_res_id_short}", "/[^a-zA-Z0-9-]/", "-"))
  region  = local.cluster_location_region
  project = local.project_id
}

module "custom-network" {
  source     = "./terraform/modules/gcp-network"
  count      = var.create_network ? 1 : 0
  project_id = local.project_id
  unique_res_id = local.unique_res_id_short
  
  network_name = lower(replace("${var.cluster_name}-${var.network_name}-${local.unique_res_id_short}", "/[^a-zA-Z0-9-]/", "-"))
  create_psa   = true

  subnets = [
    {
      
      subnet_name           = lower(replace("${var.cluster_name}-${var.subnetwork_name}", "/[^a-zA-Z0-9-]/", "-"))
      subnet_ip             = var.subnetwork_cidr
      subnet_region         = local.cluster_location_region
      subnet_private_access = var.subnetwork_private_access
      description           = var.subnetwork_description
    }
  ]
}

locals {
  
  network_name    = var.create_network ? module.custom-network[0].network_name : lower(replace("${var.cluster_name}-${var.network_name}-${local.unique_res_id_short}", "/[^a-zA-Z0-9-]/", "-"))
  subnetwork_name = var.create_network ? module.custom-network[0].subnets_names[0] : lower(replace("${var.cluster_name}-${var.subnetwork_name}", "/[^a-zA-Z0-9-]/", "-"))

  subnetwork_cidr = var.create_network ? module.custom-network[0].subnets_ips[0] : data.google_compute_subnetwork.subnetwork[0].ip_cidr_range

  region   = length(split("-", local.cluster_location)) == 2 ? local.cluster_location : ""
  regional = local.region != "" ? true : false

  cluster_location_region = (length(split("-", local.cluster_location)) == 2 ? local.cluster_location : join("-", slice(split("-", local.cluster_location), 0, 2)))

  zone = length(split("-", local.cluster_location)) > 2 ? split(",", local.cluster_location) : split(",", local.gpu_location[local.region])

  # Update gpu_pools with node_locations according to region and zone gpu availibility, if not provided
  gpu_pools = [for elm in var.gpu_pools : (local.regional && contains(keys(local.gpu_location), local.region) && elm["node_locations"] == "") ? merge(elm, { "node_locations" : local.gpu_location[local.region] }) : elm]

  gpu_pools_configured = [merge(local.gpu_pools[0], local.machine_type, local.accelerator_type, local.accelerator_count, local.local_ssd_ephemeral_storage_count)]
}

output "cluster_name" {
  value = "${var.cluster_name}-${local.unique_res_id_short}"
}

output "cluster_location" {
  value = local.cluster_location
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
  cluster_name                         = "${var.cluster_name}-${local.unique_res_id_short}"
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
  gpu_pools = local.gpu_pools_configured
  all_node_pools_oauth_scopes = var.all_node_pools_oauth_scopes
  all_node_pools_labels       = var.all_node_pools_labels
  all_node_pools_metadata     = var.all_node_pools_metadata
  all_node_pools_tags         = var.all_node_pools_tags
  depends_on                  = [module.custom-network]
}

data "google_container_cluster" "default" {
  count = var.create_cluster ? 0 : 1
  name  = "${var.cluster_name}-${local.unique_res_id_short}"
  location   = local.cluster_location
  depends_on = [module.gke-cluster]
}

locals {
  endpoint       = module.gke-cluster[0].endpoint
  ca_certificate = module.gke-cluster[0].ca_certificate
  token          = data.google_client_config.default.access_token
  use_bundle_url = var.ngc_api_key == ""
}

provider "kubernetes" {
  host  = "https://${local.endpoint}"
  token = local.token

  cluster_ca_certificate = local.ca_certificate
}

resource "kubernetes_namespace" "nim" {
  metadata {
    name = "nim"
  }
}

resource "kubernetes_secret" "registry_secret" {
  metadata {
    name      = "registry-secret"
    namespace = var.kubernetes_namespace
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
    namespace = var.kubernetes_namespace
  }

  type = "Opaque" # Generic secret type

  data = {
    "NGC_API_KEY" = var.ngc_api_key
  }

  depends_on = [kubernetes_namespace.nim]
}

resource "kubernetes_secret" "ngc_bundle_url" {
  metadata {
    name      = "ngc-bundle-url"
    namespace = var.kubernetes_namespace
  }

  type = "Opaque" # Generic secret type

  data = {
    "NGC_BUNDLE_URL" = local.use_bundle_url ? "${data.local_file.ngc-bundle-url[0].content}" : ""
  }

  depends_on = [kubernetes_namespace.nim]
}

resource "kubernetes_service_account" "ngc_gcs_ksa" {
  metadata {
    name      = "nim-on-gke-sa"
    namespace = var.kubernetes_namespace
  }
  depends_on = [kubernetes_namespace.nim]
}

resource "random_uuid" "gcs_cache_uuid" {
}

resource "google_storage_bucket" "ngc_gcs_cache" {
  project       = data.google_project.current.project_id
  name          = "ngc-gcs-cache-${random_uuid.gcs_cache_uuid.result}"
  location      = "US"
  force_destroy = true

  uniform_bucket_level_access = true
}

resource "google_storage_bucket_iam_binding" "ngc_gcs_ksa_binding" {
  bucket = google_storage_bucket.ngc_gcs_cache.name
  role   = "roles/storage.objectUser"
  members = [
    "principal://iam.googleapis.com/projects/${data.google_project.current.number}/locations/global/workloadIdentityPools/${data.google_project.current.project_id}.svc.id.goog/subject/ns/${kubernetes_service_account.ngc_gcs_ksa.metadata[0].namespace}/sa/${kubernetes_service_account.ngc_gcs_ksa.metadata[0].name}",
  ]
  depends_on = [kubernetes_service_account.ngc_gcs_ksa]
}

provider "helm" {
  alias = "helm_install"
  kubernetes {
    host                   = local.endpoint
    cluster_ca_certificate = local.ca_certificate
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      args        = ["./k8s-exec-token.sh"]
      command     = "/bin/sh"
    }
  }
}

locals {

  image_tag = lookup(var.nim_list, var.model_name, var.tag)
  image     = "${var.registry_server}/${var.repository}/${var.model_name}"
  ngc_transfer_image = var.ngc_transfer_image == "" ? local.image : var.ngc_transfer_image
  ngc_transfer_tag = var.ngc_transfer_tag == "" ? local.image_tag : var.ngc_transfer_tag
  ngc_bundle_gcs_bucket = lookup(var.ngc_bundle_gcs_bucket_list, var.model_name)
  ngc_bundle_filename_config = lookup(var.ngc_bundle_filename_config_list, var.model_name)
  ngc_bundle_filename_prefix = local.ngc_bundle_filename_config.prefix
  ngc_bundle_filename_suffix = local.ngc_bundle_filename_config.has_gpu_suffix ? "-${local.gpu_type.gpu_family}" : ""
  ngc_bundle_filename = "${local.ngc_bundle_filename_prefix}${local.ngc_bundle_filename_suffix}.${local.ngc_bundle_filename_config.extension}"
  ngc_bundle_size = lookup(var.ngc_bundle_size_list, var.model_name, "500Gi")
}

data "local_file" "ngc-eula" {
  count = local.use_bundle_url ? 1 : 0
  filename = "${path.module}/NIM_GKE_GCS_SIGNED_URL_EULA"
}

resource "null_resource" "get-signed-ngc-bundle-url" {
  count = local.use_bundle_url ? 1 : 0
  triggers = {
    shell_hash = "${sha256(file("${path.module}/fetch-ngc-url.sh"))}"
  }
  provisioner "local-exec" {
    command = "/bin/sh ./fetch-ngc-url.sh > ${path.module}/ngc_signed_url.txt"
    environment = {
      NGC_EULA_TEXT  = "${data.local_file.ngc-eula[0].content}"
      NIM_GCS_BUCKET = "${local.ngc_bundle_gcs_bucket}"
      GCS_FILENAME   = "${local.ngc_bundle_filename}"
      SERVICE_FQDN   = "${var.ngc_bundle_service_fqdn}"
    }
  }
}

resource "null_resource" "touch-ngc-signed-url" {
  triggers = {
    shell_hash = "${timestamp()}"
  }
  provisioner "local-exec" {
    command = "/bin/sh -c \"[ -f ${path.module}/ngc_signed_url.txt ] || echo '' > ${path.module}/ngc_signed_url.txt\""
  }
}

data "local_file" "ngc-bundle-url" {
  count = local.use_bundle_url ? 1 : 0
  filename = "${path.module}/ngc_signed_url.txt"
  depends_on = [null_resource.touch-ngc-signed-url, null_resource.get-signed-ngc-bundle-url]
}

resource "helm_release" "ngc_to_gcs_transfer" {
  name          = "ngc-to-gcs-transfer"
  namespace     = var.kubernetes_namespace
  repository    = "nim-llm"
  chart         = "./helm/ngc-cache"
  wait_for_jobs = true

  provider = helm.helm_install

  values = [
    file("./helm/custom-values.yaml"),
    file("./helm/ngc-cache-values.yaml")
  ]

  set {
    name  = "extraVolumes.cache-volume.csi.volumeAttributes.bucketName"
    value = google_storage_bucket.ngc_gcs_cache.name
  }

  set {
    name  = "persistence.csi.volumeHandle"
    value = google_storage_bucket.ngc_gcs_cache.name
  }

  set {
    name  = "image.repository"
    value = local.ngc_transfer_image
  }

  set {
    name  = "image.tag"
    value = local.ngc_transfer_tag
  }

  set {
    name  = "persistence.size"
    value = local.ngc_bundle_size
  }

  set {
    name  = "serviceAccount.name"
    value = kubernetes_service_account.ngc_gcs_ksa.metadata[0].name
  }

  set {
    name  = "model.name"
    value = var.model_name
  }

  set {
    name  = "resources.limits.nvidia\\.com/gpu"
    value = local.accelerator_count.accelerator_count
  }

  depends_on = [kubernetes_secret.ngc_api,
    kubernetes_secret.ngc_bundle_url,
    google_storage_bucket_iam_binding.ngc_gcs_ksa_binding]

  timeout = 7200
  wait    = true
}

module "helm_nim" {
  source = "./terraform/modules/helm/nim-install"

  providers = {
    helm = helm.helm_install
  }

  host                   = local.endpoint
  token                  = local.token
  cluster_ca_certificate = local.ca_certificate

  namespace = var.kubernetes_namespace
  #chart     = "./../../../helm/nim-llm/"
  chart = "./helm/nim-llm"

  repository = local.image
  model_name = var.model_name
  tag        = local.image_tag
  gpu_limits = local.accelerator_count.accelerator_count
  ksa_name   = kubernetes_service_account.ngc_gcs_ksa.metadata[0].name

  depends_on = [helm_release.ngc_to_gcs_transfer]
}
