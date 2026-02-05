terraform {
  backend "gcs" {
    bucket  = "analyze-this-2026-tfstate"
    prefix  = "terraform/state"
  }
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

resource "google_project_service" "logging" {
  service            = "logging.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "monitoring" {
  service            = "monitoring.googleapis.com"
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

resource "google_project_iam_member" "logging_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.irc.email}"
}

resource "google_project_iam_member" "monitoring_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
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

resource "google_compute_address" "irc_ip" {
  name   = "irc-ip"
  region = var.region
}

resource "google_compute_instance" "irc_server" {
  name         = "irc-server"
  machine_type = var.machine_type
  zone         = "${var.region}-a"
  tags         = ["irc-server"]

  boot_disk {
    initialize_params {
      image = var.source_image
    }
  }

  network_interface {
    network    = var.network
    subnetwork = var.subnetwork != "" ? var.subnetwork : null
    access_config {
      nat_ip = google_compute_address.irc_ip.address
    }
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
    google_project_service.logging,
    google_project_service.monitoring,
    google_project_iam_member.secret_accessor,
    google_project_iam_member.logging_writer,
    google_project_iam_member.monitoring_writer
  ]
}

resource "google_compute_firewall" "irc_public" {
  name    = "irc-public-allow"
  network = var.network

  allow {
    protocol = "tcp"
    ports    = ["6667", "6697", "80", "443"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["irc-server"]
}

resource "google_compute_firewall" "irc_ssh" {
  name    = "irc-ssh-allow"
  network = var.network

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = var.ssh_source_ranges
  target_tags   = ["irc-server"]
}

resource "cloudflare_dns_record" "irc" {
  count   = var.cloudflare_manage_dns ? 1 : 0
  zone_id = var.cloudflare_zone_id
  name    = var.domain
  type    = "A"
  content = google_compute_address.irc_ip.address
  proxied = false
  ttl     = 300
}
