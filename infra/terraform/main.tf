terraform {
  required_version = ">= 1.5.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.0.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = ">= 4.0.0"
    }
    local = {
      source  = "hashicorp/local"
      version = ">= 2.4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

resource "google_project_service" "compute" {
  service            = "compute.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "secretmanager" {
  service            = "secretmanager.googleapis.com"
  disable_on_destroy = false
}

resource "google_service_account" "irc" {
  account_id   = "irc-server"
  display_name = "IRC server service account"
}

resource "google_project_iam_member" "secret_accessor" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.irc.email}"
}

resource "random_password" "server_password" {
  length  = 28
  special = true
}

resource "random_password" "oper_password" {
  length  = 28
  special = true
}

resource "google_secret_manager_secret" "irc_server_password" {
  secret_id = "irc-server-password"
  replication {
    auto {}
  }
  depends_on = [google_project_service.secretmanager]
}

resource "google_secret_manager_secret_version" "irc_server_password" {
  secret      = google_secret_manager_secret.irc_server_password.id
  secret_data = var.irc_server_password != "" ? var.irc_server_password : random_password.server_password.result
}

resource "google_secret_manager_secret" "irc_oper_password" {
  secret_id = "irc-oper-password"
  replication {
    auto {}
  }
  depends_on = [google_project_service.secretmanager]
}

resource "google_secret_manager_secret_version" "irc_oper_password" {
  secret      = google_secret_manager_secret.irc_oper_password.id
  secret_data = var.irc_oper_password != "" ? var.irc_oper_password : random_password.oper_password.result
}

resource "google_compute_global_address" "irc" {
  name = "irc-ip"
}

resource "google_compute_health_check" "irc" {
  name                = "irc-health"
  check_interval_sec  = 5
  timeout_sec         = 5
  healthy_threshold   = 2
  unhealthy_threshold = 2

  tcp_health_check {
    port = var.irc_port_internal
  }
}

resource "google_compute_backend_service" "irc" {
  name                  = "irc-backend"
  protocol              = "TCP"
  load_balancing_scheme = "EXTERNAL"
  timeout_sec           = 10
  port_name             = "irc"
  health_checks         = [google_compute_health_check.irc.id]

  backend {
    group = google_compute_region_instance_group_manager.irc.instance_group
  }
}

resource "google_compute_managed_ssl_certificate" "irc" {
  name = "irc-managed-cert"
  managed {
    domains = [var.domain]
  }
}

resource "google_compute_target_ssl_proxy" "irc" {
  name             = "irc-ssl-proxy"
  backend_service  = google_compute_backend_service.irc.id
  ssl_certificates = [google_compute_managed_ssl_certificate.irc.id]
}

resource "google_compute_global_forwarding_rule" "irc" {
  name                  = "irc-forwarding"
  ip_address            = google_compute_global_address.irc.address
  port_range            = var.irc_port_external
  target                = google_compute_target_ssl_proxy.irc.id
  load_balancing_scheme = "EXTERNAL"
  ip_protocol           = "TCP"
}

resource "google_compute_firewall" "irc_backend" {
  name    = "irc-backend-allow-proxy"
  network = var.network

  allow {
    protocol = "tcp"
    ports    = [var.irc_port_internal]
  }

  source_ranges = [
    "35.191.0.0/16",
    "130.211.0.0/22"
  ]

  target_tags = ["irc-backend"]
}

resource "google_compute_region_instance_template" "irc" {
  name_prefix  = "irc-template-"
  region       = var.region
  machine_type = var.machine_type
  tags         = ["irc-backend"]

  disk {
    boot         = true
    auto_delete  = true
    source_image = var.source_image
  }

  network_interface {
    network    = var.network
    subnetwork = var.subnetwork != "" ? var.subnetwork : null
    access_config {}
  }

  service_account {
    email  = google_service_account.irc.email
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  metadata = var.ssh_public_key != "" ? {
    "ssh-keys" = "${var.ssh_username}:${var.ssh_public_key}"
  } : {}

  depends_on = [
    google_project_service.compute,
    google_project_iam_member.secret_accessor
  ]
}

resource "google_compute_region_instance_group_manager" "irc" {
  name               = "irc-mig"
  region             = var.region
  base_instance_name = "irc"
  target_size        = 1

  version {
    instance_template = google_compute_region_instance_template.irc.id
  }

  named_port {
    name = "irc"
    port = var.irc_port_internal
  }
}

resource "google_compute_firewall" "irc_ssh" {
  name    = "irc-ssh-allow"
  network = var.network

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = var.ssh_source_ranges
  target_tags   = ["irc-backend"]
}

data "google_compute_region_instance_group" "irc" {
  name   = google_compute_region_instance_group_manager.irc.name
  region = var.region
}

locals {
  instance_self_links = data.google_compute_region_instance_group.irc.instances
}

data "google_compute_instance" "irc" {
  for_each  = toset(local.instance_self_links)
  self_link = each.value
}

locals {
  instance_ips = [for inst in data.google_compute_instance.irc : inst.network_interface[0].access_config[0].nat_ip]
}

resource "local_file" "ansible_inventory" {
  filename = "${path.module}/ansible/inventory.ini"
  content = templatefile("${path.module}/inventory.tmpl", {
    hosts = local.instance_ips
    user  = var.ssh_username
  })
}

resource "cloudflare_dns_record" "irc" {
  count   = var.cloudflare_manage_dns ? 1 : 0
  zone_id = var.cloudflare_zone_id
  name    = var.domain
  type    = "A"
  content = google_compute_global_address.irc.address
  proxied = false
  ttl     = 300
}
