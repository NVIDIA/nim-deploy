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
  chart      = "../../../../../helm/nim-llm/"

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