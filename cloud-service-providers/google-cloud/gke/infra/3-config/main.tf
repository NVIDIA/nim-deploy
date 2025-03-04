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


data "terraform_remote_state" "gke-cluster" {
  backend = "local"

  config = {
    path = "../2-setup/terraform.tfstate"
  }
}

data "google_project" "current" {
  project_id = data.terraform_remote_state.gke-cluster.outputs.project_id
}

locals {
  cluster_name     = data.terraform_remote_state.gke-cluster.outputs.cluster_name
  cluster_location = data.terraform_remote_state.gke-cluster.outputs.cluster_location
  use_bundle_url   = var.ngc_bundle_gcs_bucket != "" && var.ngc_bundle_filename != ""
}

provider "kubernetes" {
  config_path = "~/.kube/config"
}

provider "helm" {
  kubernetes {
    config_path = "~/.kube/config"
  }
}

resource "null_resource" "get-credentials" {

  provisioner "local-exec" {
    command = "gcloud container clusters get-credentials ${local.cluster_name} --region ${local.cluster_location}"
  }

}

data "local_file" "ngc-eula" {
  filename = "${path.module}/NIM_GKE_GCS_SIGNED_URL_EULA"
}

resource "null_resource" "get-signed-ngc-bundle-url" {
  count = local.use_bundle_url ? 1 : 0
  triggers = {
    shell_hash = "${sha256(file("${path.module}/fetch-ngc-url.sh"))}"
  }
  provisioner "local-exec" {
    command = "./fetch-ngc-url.sh > ${path.module}/ngc_signed_url.txt"
    environment = {
      NGC_EULA_TEXT  = "${data.local_file.ngc-eula.content}"
      NIM_GCS_BUCKET = "${var.ngc_bundle_gcs_bucket}"
      GCS_FILENAME   = "${var.ngc_bundle_filename}"
      SERVICE_FQDN   = "nim-gke-gcs-signed-url-722708171432.us-central1.run.app"
    }
  }
}

data "local_file" "ngc-bundle-url" {
  count = local.use_bundle_url ? 1 : 0
  filename = "${path.module}/ngc_signed_url.txt"
  depends_on = [null_resource.get-signed-ngc-bundle-url]
}

resource "kubernetes_namespace" "nim" {
  metadata {
    name = "nim"
  }
}

resource "kubernetes_secret" "ngc_registry_secret" {
  metadata {
    name      = "registry-secret"
    namespace = "nim"
  }

  type = "kubernetes.io/dockerconfigjson"

  data = {
    ".dockerconfigjson" = jsonencode({
      "auths" = {
        "${var.ngc_registry_server}" = {
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

resource "kubernetes_secret" "ngc_bundle_url" {
  count = local.use_bundle_url ? 1 : 0
  metadata {
    name      = "ngc-bundle-url"
    namespace = "nim"
  }

  type = "Opaque" # Generic secret type

  data = {
    "NGC_BUNDLE_URL" = "${data.local_file.ngc-bundle-url[0].content}"
  }

  depends_on = [kubernetes_namespace.nim]
}

resource "kubernetes_service_account" "ngc_gcs_ksa" {
  metadata {
    name = "nim-on-gke-sa"
    namespace = "nim"
  }
  depends_on = [kubernetes_namespace.nim]
}

resource "random_uuid" "gcs_cache_uuid" {
}

resource "google_storage_bucket" "ngc_gcs_cache" {
  project       = data.google_project.current.name
  name          = "ngc-gcs-cache-${random_uuid.gcs_cache_uuid.result}"
  location      = "US"
  force_destroy = true

  uniform_bucket_level_access = true
}

resource "google_storage_bucket_iam_binding" "ngc_gcs_ksa_binding" {
  bucket = google_storage_bucket.ngc_gcs_cache.name
  role = "roles/storage.objectUser"
  members = [
    "principal://iam.googleapis.com/projects/${data.google_project.current.number}/locations/global/workloadIdentityPools/${data.google_project.current.project_id}.svc.id.goog/subject/ns/${kubernetes_service_account.ngc_gcs_ksa.metadata[0].namespace}/sa/${kubernetes_service_account.ngc_gcs_ksa.metadata[0].name}",
  ]
  depends_on = [kubernetes_service_account.ngc_gcs_ksa]
}

resource "helm_release" "ngc_to_gcs_transfer" {
  name       = "ngc-to-gcs-transfer"
  namespace  = "nim"
  repository = "nim-llm"
  chart      = "./helm/ngc-cache"
  wait_for_jobs = true

  values = [
    file("./helm/custom-values.yaml"),
    file("./helm/ngc-cache-values.yaml")
  ]

  set {
    name = "extraVolumes.cache-volume.csi.volumeAttributes.bucketName"
    value = google_storage_bucket.ngc_gcs_cache.name
  }

  set {
    name = "persistence.csi.volumeHandle"
    value = google_storage_bucket.ngc_gcs_cache.name
  }

  set {
    name  = "image.repository"
    value = var.ngc_transfer_repository
  }

  set {
    name  = "image.tag"
    value = var.ngc_transfer_tag
  }

  set {
    name = "serviceAccount.name"
    value = kubernetes_service_account.ngc_gcs_ksa.metadata[0].name
  }

  set {
    name  = "model.name"
    value = var.model_name
  }

  set {
    name  = "resources.limits.nvidia\\.com/gpu"
    value = var.gpu_limits
  }

  depends_on = [kubernetes_secret.ngc_api, kubernetes_secret.ngc_bundle_url, google_storage_bucket_iam_binding.ngc_gcs_ksa_binding]

  timeout = 3600
  wait    = true
}

resource "helm_release" "my_nim" {
  name       = "my-nim"
  namespace  = "nim"
  repository = "https://helm.ngc.nvidia.com/nim"
  chart      = "nim-llm"
  version    = "1.3.0"

  repository_username = "$oauthtoken"
  repository_password = var.ngc_api_key

  values = [
    file("./helm/custom-values.yaml")
  ]

  set {
    name = "csi.volumeAttributes.bucketName"
    value = "ngc-gcs-cache-5f0f6937-fad0-1df7-025e-a912ebf61647"
  }

  set {
    name  = "image.repository"
    value = var.ngc_nim_repository
  }

  set {
    name  = "image.tag"
    value = var.ngc_nim_tag
  }

  set {
    name = "serviceAccount.name"
    value = kubernetes_service_account.ngc_gcs_ksa.metadata[0].name
  }

  set {
    name  = "model.name"
    value = var.model_name
  }

  set {
    name  = "resources.limits.nvidia\\.com/gpu"
    value = var.gpu_limits
  }

  depends_on = [helm_release.ngc_to_gcs_transfer]

  timeout = 900
  wait    = true
}

# resource "kubernetes_service" "my_nim_service" {
#   metadata {
#     name      = "my-nim"
#     namespace = "nim"
#   }

#   spec {
#     type = "LoadBalancer"

#     selector = {
#       "app.kubernetes.io/instance" = "my-nim"
#       "app.kubernetes.io/name"     = "nim-llm"
#     }

#     port {
#       name        = "http"
#       port        = 8000
#       target_port = 8000
#     }
#   }

# 	depends_on = [ helm_release.my_nim ]
# }