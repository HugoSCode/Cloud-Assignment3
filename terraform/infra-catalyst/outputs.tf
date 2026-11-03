
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
