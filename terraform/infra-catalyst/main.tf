
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
