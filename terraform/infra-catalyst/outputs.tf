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
  description = "The floating IP, surviving an instance stop/start."
  value       = "TODO-public_ip"
}

output "shop_host" {
  description = "Resolvable hostname. Feed this to scripts/render.sh and scripts/deploy.sh."
  value       = "TODO-shop_host"
}

output "ssh_command" {
  description = "A ready-to-paste ssh command. Build it from var.admin_username and the address."
  value       = "TODO-ssh_command"
}

output "admin_user" {
  description = "Login account on the VM. The same value you pass to the cloud-init template."
  value       = "TODO-admin_user"
}

# --- Optional extras, not part of the contract -----------------------------
#
# You may add outputs of your own. They are not marked, but they are useful
# while you work and they show you understand what is worth surfacing.
# Sensible ones here: the application URL, the volume id, the image id the data source resolved.
