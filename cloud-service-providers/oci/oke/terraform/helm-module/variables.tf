# Copyright (c) 2022, 2024 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

variable "deploy_from_local" {
  type        = bool
  default     = true
  description = "Wether to attempt deployment of the helm charts using local-exec."
}

variable "deploy_from_operator" {
  type        = bool
  default     = false
  description = "Wether to attempt deployment of the helm charts using remote-exec."
}

variable "deployment_name" {
  type        = string
  default     = false
  description = "The name of the helm deployment."
}

variable "namespace" {
  type        = string
  default     = "default"
  description = "The kubernetes namespace to target for the helm deployment."
}

variable "helm_chart_name" {
  type        = string
  default     = ""
  description = "The name of the helm chart. Used together with `helm_repository_url` when helm_chart_path=''."
}

variable "helm_chart_path" {
  type        = string
  default     = ""
  description = "The path of the helm chart. If not empty will override the `helm_repository_url` and `helm_chart_name` values."
}

variable "helm_repository_url" {
  type        = string
  default     = ""
  description = "The helm chart repository url."
}

variable "operator_helm_values_path" {
  type        = string
  default     = ""
  description = "The directory on the operator host where to push the values-override for the helm chart."
}

variable "operator_helm_charts_path" {
  type        = string
  default     = ""
  description = "The directory on the operator host where to push the helm-charts when `helm_chart_path` is not empty."
}

variable "helm_template_values_override" {
  type        = string
  description = "The values-override file content populated using terraform templates."
}

variable "helm_user_values_override" {
  type        = string
  description = "The values-override file provided by the user as variable."
}
variable "pre_deployment_commands" {
  type        = list(string)
  default     = []
  description = "List of commands to be executed before attempting the helm deployment."
}
variable "post_deployment_commands" {
  type        = list(string)
  default     = []
  description = "List of commands to be executed after the helm deployment."
}

variable "deployment_extra_args" {
  type        = list(string)
  default     = []
  description = "List of arguments to be appended to the helm upgrade --install command."
}

variable "kube_config" {
  type        = string
  default     = ""
  description = "The Kubeconfig file content to use for helm deployments using local-exec."
}

variable "bastion_host" {
  type        = string
  default     = null
  description = "The IP address of the bastion host."
}

variable "bastion_user" {
  type        = string
  default     = "opc"
  description = "The user to be used for SSH connection to the bastion host."
}

variable "ssh_private_key" {
  type        = string
  default     = null
  description = "The SSH private key to be used for connection to operator/bastion hosts."
}

variable "operator_host" {
  type        = string
  default     = null
  description = "The IP address of the operator host."
}

variable "operator_user" {
  type        = string
  default     = "opc"
  description = "The user to be used for SSH connection to the operator host."
}