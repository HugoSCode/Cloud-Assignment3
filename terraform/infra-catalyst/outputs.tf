###############################################################################
# THE CONTRACT -- partly supplied.
#
# These four output NAMES are fixed. They are identical in infra-aws,
# infra-azure and infra-catalyst, and that is what lets everything above
# stage 1 -- the platform Terraform, the manifests, the scripts -- work
# without knowing which cloud it is running on. See docs/CLOUD-CONTRACT.md.
#
# The names and descriptions are given. The VALUES are yours: each one has to
# reference a resource or local you create in main.tf. Replace every
# "TODO-..." placeholder.
#
# These files parse and plan as they stand, so nothing will stop you
# submitting them unfinished. scripts/check-progress.sh will tell you, and so
# will `terraform output` -- if it prints the word TODO, stage 1 is not done.
###############################################################################

output "public_ip" {
  value = openstack_networking_floatingip_v2.fip.address
}

output "shop_host" {
  value = local.shop_host
}

output "ssh_command" {
  value = "ssh -i k8s-key ${var.admin_username}@${openstack_networking_floatingip_v2.fip.address}"
}

output "admin_user" {
  value = var.admin_username
}

# --- Optional extras, not part of the contract -----------------------------
#
# You may add outputs of your own. They are not marked, but they are useful
# while you work and they show you understand what is worth surfacing.
# Sensible ones here: the application URL, the volume id, the image id the data source resolved.
