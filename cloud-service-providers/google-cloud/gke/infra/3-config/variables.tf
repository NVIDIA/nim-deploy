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


variable "registry_server" {
  type        = string
  default     = "nvcr.io"
  description = "Registry that hosts the NIM images"
}

variable "ngc_username" {
  type        = string
  default     = "$oauthtoken"
  description = "Username to access NGC registry"
  sensitive   = true
}

variable "ngc_api_key" {
  type        = string
  default     = "$NGC_API_KEY"
  description = "NGC CLI API key to access NGC registry"
  sensitive   = true
}

variable "repository" {
  type        = string
  description = "Docker image of NIM container"
}

variable "tag" {
  type        = string
  description = "Docker repository tag of NIM container"
}

variable "model_name" {
  type        = string
  description = "Name of the NIM model"
}

variable "gpu_limits" {
  type        = number
  description = "GPU limits"
}
