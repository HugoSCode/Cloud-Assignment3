variable "username" {
  description = "Your student username. Prefixes every resource name so a shared project does not collide."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]{3,20}$", var.username))
    error_message = "Use 3-20 lowercase letters, digits or hyphens."
  }
}

variable "region" {
  description = "Catalyst Cloud region. Confirm with: openstack region list"
  type        = string
  default     = "nz-por-1"
}

variable "flavour_name" {
  description = "Instance flavour. Needs 2 vCPU and 8 GiB; a 4 GiB flavour will OOM once the observability stack starts. Confirm with: openstack flavor list"
  type        = string
  default     = "c1.c2r8"
}

variable "image_name" {
  description = "Ubuntu 22.04 image. Catalyst names these ubuntu-*; confirm with: openstack image list --public | grep -i ubuntu"
  type        = string
  default     = "ubuntu-22.04-x86_64"
}

variable "external_network_name" {
  description = "External network providing floating IPs."
  type        = string
  default     = "public-net"
}

variable "admin_username" {
  description = "Default login account baked into Catalyst's Ubuntu images."
  type        = string
  default     = "ubuntu"
}

variable "public_key_path" {
  description = "Path to the SSH public key to install on the instance."
  type        = string
  default     = "./k8s-key.pub"
}

variable "ssh_source_cidr" {
  description = "Source range permitted to reach SSH. Set this to <your-ip>/32; 0.0.0.0/0 is the lazy default and you will be asked to justify it."
  type        = string
  default     = "0.0.0.0/0"
}

variable "subnet_cidr" {
  description = "CIDR for the tenant subnet."
  type        = string
  default     = "10.72.1.0/24"
}

variable "dns_nameservers" {
  description = "Resolvers for instances on the subnet. These are Catalyst's."
  type        = list(string)
  default     = ["202.78.240.213", "202.78.240.214", "202.78.240.215"]
}

variable "root_disk_size_gb" {
  description = "Boot volume size in GiB."
  type        = number
  default     = 40
}

variable "data_disk_size_gb" {
  description = "Dedicated data volume in GiB, for container images and PersistentVolumes."
  type        = number
  default     = 32

  validation {
    condition     = var.data_disk_size_gb >= 8 && var.data_disk_size_gb <= 256
    error_message = "Use between 8 and 256 GiB."
  }
}
