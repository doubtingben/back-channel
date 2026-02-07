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

resource "google_project_service" "artifactregistry" {
  service            = "artifactregistry.googleapis.com"
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
  special = false
}

resource "random_password" "oper_password" {
  length  = 28
  special = false
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

resource "google_project_service" "run" {
  service            = "run.googleapis.com"
  disable_on_destroy = false
}

resource "google_artifact_registry_repository" "irccat" {
  location      = var.region
  repository_id = "irccat"
  description   = "Docker images for irccat"
  format        = "DOCKER"

  depends_on = [google_project_service.artifactregistry]
}

resource "google_service_account" "irccat" {
  account_id   = "irccat"
  display_name = "IRCCat service account"
}

resource "google_project_iam_member" "irccat_secret_accessor" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.irccat.email}"
}

resource "google_cloud_run_service" "irccat" {
  name     = "irccat"
  location = var.region

  template {
    spec {
      service_account_name = google_service_account.irccat.email
      containers {
        image = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.irccat.repository_id}/irccat:latest"
        
        env {
          name  = "IRC_SERVER"
          value = "${var.domain}:6697"
        }
        
        env {
          name  = "IRC_CHANNELS"
          value = "[\"#analyze-this\"]"
        }

        env {
            name = "IRC_NICK"
            value = "irccat"
        }

        env {
          name = "IRC_PASSWORD"
          value_from {
            secret_key_ref {
              name = google_secret_manager_secret.irc_server_password.secret_id
              key  = "latest"
            }
          }
        }
      }
    }
  }

  traffic {
    percent         = 100
    latest_revision = true
  }

  depends_on = [
    google_project_service.run,
    google_project_iam_member.irccat_secret_accessor
  ]
}

resource "google_cloud_run_domain_mapping" "irccat" {
  location = var.region
  name     = "chat-relay.interestedparticipants.org"

  metadata {
    namespace = var.project_id
  }

  spec {
    route_name = google_cloud_run_service.irccat.name
  }
}

resource "google_cloud_run_service_iam_member" "public" {
  service  = google_cloud_run_service.irccat.name
  location = google_cloud_run_service.irccat.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}

resource "cloudflare_dns_record" "irccat" {
  count   = var.cloudflare_manage_dns ? 1 : 0
  zone_id = var.cloudflare_zone_id
  name    = "chat-relay"
  type    = "CNAME"
  content = "ghs.googlehosted.com"
  proxied = false
  ttl     = 300
}

resource "google_project_iam_member" "cicd_artifact_registry_writer" {
  project = var.project_id
  role    = "roles/artifactregistry.admin"
  member  = "serviceAccount:irc-cicd@${var.project_id}.iam.gserviceaccount.com"
}

resource "google_project_iam_member" "cicd_gcr_writer" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:irc-cicd@${var.project_id}.iam.gserviceaccount.com"
}

resource "google_project_iam_member" "cicd_run_admin" {
  project = var.project_id
  role    = "roles/run.admin"
  member  = "serviceAccount:irc-cicd@${var.project_id}.iam.gserviceaccount.com"
}

resource "google_service_account_iam_member" "cicd_impersonate_irccat_runner" {
  service_account_id = google_service_account.irc.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:irc-cicd@${var.project_id}.iam.gserviceaccount.com"
}
