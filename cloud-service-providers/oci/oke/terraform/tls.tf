# Copyright (c) 2022, 2024 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

locals {
  user_public_ssh_key     = chomp(var.ssh_public_key)
  bundled_ssh_public_keys = "${local.user_public_ssh_key}\n${chomp(tls_private_key.stack_key.public_key_openssh)}"
}

resource "tls_private_key" "stack_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}