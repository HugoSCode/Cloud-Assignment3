###############################################################################
# TO WRITE -- Task 1, Criterion 1.   Stage 1 on Catalyst Cloud (OpenStack).
#
# Write this file ONLY if you chose Catalyst. Delete the two directories for
# the clouds you did not choose before you submit.
#
# provider.tf, variables.tf and outputs.tf are supplied. The variables are the
# inputs your stack must accept; the outputs are the contract it must satisfy.
#
# READ FIRST: docs/CLOUD-CONTRACT.md.
#
# Before anything else:
#   source ~/openrc.sh        # from the dashboard: API Access -> OpenStack RC
#   openstack quota show      # OpenStack quotas are per-project and tight
###############################################################################

# ---------------------------------------------------------------------------
# WHAT THIS FILE MUST BUILD
#
# The contract, restated. Each line is worth marks in Criterion 1, and each is
# a question in the code defense.
#
#   1. A VM running Ubuntu 22.04 with 2 vCPU and 8 GiB. Smaller will not do:
#      kube-prometheus-stack alone wants 2-3 GiB before your application
#      starts, and a 4 GiB node presents the shortfall as random Evicted and
#      CrashLoopBackOff Pods that look exactly like application bugs.
#
#   2. A stable public address. On OpenStack that is a floating IP allocated
#      from the external network pool and associated with your instance.
#      Your hostname goes into a TLS certificate in Task 5.
#
#   3. A resolvable public hostname. Catalyst gives you no free DNS name, so
#      derive one -- see THE HOSTNAME below.
#
#   4. A firewall allowing 22, 80 and 443, and nothing else. Port 22 from your
#      own address only. Note what is NOT on that list: the Kubernetes API on
#      16443, Prometheus on 9090 and Grafana on 3000 are all closed, and you
#      reach them over an SSH tunnel. Be ready to explain why.
#
#      OpenStack security groups deny ingress by default and allow egress by
#      default, so there is no deny rule to write. Say so in your report.
#
#   5. A dedicated block storage volume, attached to the instance and separate
#      from the root disk.
#
#   6. SSH key authentication via a keypair resource built from your public
#      key file.
#
#   7. A purpose-built network.
#
# OpenStack is the most explicit of the three APIs, which means the most
# objects: a tenant network and subnet do not reach the internet by
# themselves. Something has to connect them to the external network, and that
# something is a resource you must create and then attach to your subnet.
# Miss the attachment and the VM boots, gets an address, and can neither reach
# the package mirrors nor be reached -- with no error anywhere.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# LOOK THINGS UP BY NAME, NOT BY UUID
#
# Catalyst's own Terraform examples hardcode image and flavour UUIDs. Do not
# copy that. UUIDs differ between regions and change whenever an image is
# rebuilt, so a stack built on them stops working for reasons that are
# invisible in the code.
#
# Use data sources to resolve var.image_name and var.flavour_name at plan
# time instead. Confirm the names exist first:
#
#   openstack image list --public | grep -i ubuntu
#   openstack flavor list
#   openstack network list --external
#
# This is a reproducibility argument, and it is exactly the kind of judgement
# Criterion 1 separates Merit from Pass on. Make it explicitly in your report.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# THE HOSTNAME
#
# Catalyst has no free per-address DNS name. Use sslip.io, which resolves
# <anything>.<dashed-ip>.sslip.io straight back to that address with nothing
# to register:
#
#   202.49.240.17  ->  shop.202-49-240-17.sslip.io
#
# Build that string in a `locals` block from your floating IP, as a value
# named shop_host -- outputs.tf expects it. Terraform's replace() does the
# dashes. Deriving it rather than typing it is the point.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# THE BOOTSTRAP -- do not write your own
#
# terraform/shared/cloud-init.yaml is supplied and is identical on all three
# clouds. Pass it as user_data via templatefile() with exactly two variables;
# CLOUD-CONTRACT.md gives the call. OpenStack presents an attached volume as
# a virtio device, which is a sensible disk_hint, and the script falls back if
# it is wrong.
#
# Consider booting from a volume rather than from ephemeral instance storage,
# so the root disk can be sized and survives a rebuild. If you do not, explain
# the choice.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# WHY THIS IS THE MOST TRANSFERABLE OF THE THREE
#
# You are writing against plain OpenStack, not a Catalyst-specific API. The
# same provider and very nearly the same configuration works against any
# OpenStack cloud -- and there are many in research, government and European
# hosting. Make that point in your portability discussion in Task 8; it is a
# stronger answer than "Terraform is cloud-agnostic", which is not true.
#
# Data sovereignty is the other real argument: Catalyst is a New Zealand
# provider, so the data stays onshore. If that matters for the scenario, say
# why it matters rather than only that it is true.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# BEFORE YOU APPLY
#
#   source ~/openrc.sh
#   ssh-keygen -t rsa -b 4096 -f k8s-key -N ''
#   terraform init && terraform fmt -check && terraform validate
#   terraform plan -var="username=<you>" \
#                  -var="ssh_source_cidr=$(curl -s ifconfig.me)/32"
#
# Read the plan. Check your quota first -- OpenStack refuses at apply time
# with a message about the resource it could not create, not about the quota.
# Commit as you go.
# ---------------------------------------------------------------------------
## --- Lookups by name, not UUID ---


#---------REAL  FILE-------------------
data "openstack_images_image_v2" "ubuntu" {
  name_regex  = "^${var.image_name}" # matches dated suffixes too
  most_recent = true
}

data "openstack_compute_flavor_v2" "vm" {
  name = var.flavour_name
}

data "openstack_networking_network_v2" "external" {
  name     = var.external_network_name
  external = true
}

# --- SSH key ---
resource "openstack_compute_keypair_v2" "key" {
  name       = "${var.username}-key"
  public_key = file(var.public_key_path)
}

# --- Purpose-built network, plus the router that connects it outwards ---
resource "openstack_networking_network_v2" "net" {
  name = "${var.username}-net"
}

resource "openstack_networking_subnet_v2" "subnet" {
  name            = "${var.username}-subnet"
  network_id      = openstack_networking_network_v2.net.id
  cidr            = var.subnet_cidr
  ip_version      = 4
  dns_nameservers = var.dns_nameservers
}

resource "openstack_networking_router_v2" "router" {
  name                = "${var.username}-router"
  external_network_id = data.openstack_networking_network_v2.external.id
}

resource "openstack_networking_router_interface_v2" "router_if" {
  router_id = openstack_networking_router_v2.router.id
  subnet_id = openstack_networking_subnet_v2.subnet.id
}

# --- Firewall: 22 from you only, 80 and 443 public ---
resource "openstack_networking_secgroup_v2" "sg" {
  name        = "${var.username}-sg"
  description = "SSH from admin IP, HTTP and HTTPS public"
}

resource "openstack_networking_secgroup_rule_v2" "ssh" {
  security_group_id = openstack_networking_secgroup_v2.sg.id
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = var.ssh_source_cidr
}

resource "openstack_networking_secgroup_rule_v2" "http" {
  security_group_id = openstack_networking_secgroup_v2.sg.id
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 80
  port_range_max    = 80
  remote_ip_prefix  = "0.0.0.0/0"
}

resource "openstack_networking_secgroup_rule_v2" "https" {
  security_group_id = openstack_networking_secgroup_v2.sg.id
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 443
  port_range_max    = 443
  remote_ip_prefix  = "0.0.0.0/0"
}

# --- Port (carries the security group) and the stable public IP ---
resource "openstack_networking_port_v2" "port" {
  name               = "${var.username}-port"
  network_id         = openstack_networking_network_v2.net.id
  security_group_ids = [openstack_networking_secgroup_v2.sg.id]

  fixed_ip {
    subnet_id = openstack_networking_subnet_v2.subnet.id
  }
}

resource "openstack_networking_floatingip_v2" "fip" {
  pool = var.external_network_name
}

resource "openstack_networking_floatingip_associate_v2" "fip_assoc" {
  floating_ip = openstack_networking_floatingip_v2.fip.address
  port_id     = openstack_networking_port_v2.port.id
  depends_on  = [openstack_networking_router_interface_v2.router_if]
}

# --- Storage: boot volume plus the dedicated data volume ---
resource "openstack_blockstorage_volume_v3" "root" {
  name     = "${var.username}-root"
  size     = var.root_disk_size_gb
  image_id = data.openstack_images_image_v2.ubuntu.id
}

resource "openstack_blockstorage_volume_v3" "data" {
  name = "${var.username}-data"
  size = var.data_disk_size_gb
}

# --- Hostname derived from the floating IP ---
locals {
  shop_host = "shop.${replace(openstack_networking_floatingip_v2.fip.address, ".", "-")}.sslip.io"
}

# --- The VM ---
resource "openstack_compute_instance_v2" "vm" {
  name      = "${var.username}-vm"
  flavor_id = data.openstack_compute_flavor_v2.vm.id
  key_pair  = openstack_compute_keypair_v2.key.name

  user_data = templatefile("${path.module}/../shared/cloud-init.yaml", {
    disk_hint  = "/dev/vdb"
    admin_user = var.admin_username
  })

  block_device {
    uuid                  = openstack_blockstorage_volume_v3.root.id
    source_type           = "volume"
    destination_type      = "volume"
    boot_index            = 0
    delete_on_termination = false
  }

  # Attached at creation (boot_index -1), so it exists when cloud-init runs
  block_device {
    uuid                  = openstack_blockstorage_volume_v3.data.id
    source_type           = "volume"
    destination_type      = "volume"
    boot_index            = -1
    delete_on_termination = false
  }

  network {
    port = openstack_networking_port_v2.port.id
  }

  depends_on = [openstack_networking_router_interface_v2.router_if]
}
