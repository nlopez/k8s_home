data "digitalocean_kubernetes_versions" "this" {
  version_prefix = var.kubernetes_minor
}

resource "digitalocean_vpc" "this" {
  name     = "${var.cluster_name}-${var.region}"
  region   = var.region
  ip_range = var.vpc_cidr
}

resource "digitalocean_kubernetes_cluster" "this" {
  name     = var.cluster_name
  region   = var.region
  version  = data.digitalocean_kubernetes_versions.this.latest_version
  vpc_uuid = digitalocean_vpc.this.id

  # Pod/service CIDRs can only be set at creation time.
  cluster_subnet = var.pod_cidr
  service_subnet = var.service_cidr

  # Free control plane. Flip to true (~$40/mo) only if you need the API SLA.
  ha            = false
  auto_upgrade  = true
  surge_upgrade = true

  maintenance_policy {
    day        = "sunday"
    start_time = "07:00"
  }

  node_pool {
    name       = "default"
    size       = var.node_size
    auto_scale = true
    min_nodes  = var.min_nodes
    max_nodes  = var.max_nodes
    labels = {
      role = "bootstrap"
    }
  }

  lifecycle {
    # auto_upgrade moves the patch version; don't fight it.
    ignore_changes = [version]
  }
}
