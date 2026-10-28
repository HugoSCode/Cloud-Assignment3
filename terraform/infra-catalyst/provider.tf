terraform {
  required_version = ">= 1.3.0"
  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 2.1"
    }
  }
}

# Credentials come from the environment. Download the OpenStack RC file from
# the Catalyst Cloud dashboard (API Access -> Download OpenStack RC File) and
# source it before running Terraform:
#
#   source ~/openrc.sh
#
# That sets OS_AUTH_URL, OS_PROJECT_NAME, OS_USERNAME, OS_PASSWORD and friends.
# Never put these in a .tf file or a committed .tfvars.
provider "openstack" {
  region = var.region
}
