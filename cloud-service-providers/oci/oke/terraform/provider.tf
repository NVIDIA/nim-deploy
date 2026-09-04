# Copyright (c) 2022, 2024 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

provider "oci" {
  alias  = "home"
  region = lookup(data.oci_identity_regions.home_region.regions[0], "name")
}

provider "oci" {
  region = var.region
}

terraform {
  required_version = ">= 1.3.0"

  required_providers {

    oci = {
      configuration_aliases = [oci.home]
      source                = "oracle/oci"
      version               = ">= 4.119.0"
    }
  }
}