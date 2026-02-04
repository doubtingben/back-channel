output "irc_ip" {
  value       = google_compute_address.irc_ip.address
  description = "Static IP for the IRC server."
}

output "irc_domain" {
  value       = var.domain
  description = "IRC DNS name."
}

output "irc_external_port" {
  value       = var.irc_port_external
  description = "External port for IRC over TLS."
}

output "irc_server_password_secret" {
  value       = google_secret_manager_secret.irc_server_password.secret_id
  description = "Secret Manager secret id for IRC server password."
}

output "irc_oper_password_secret" {
  value       = google_secret_manager_secret.irc_oper_password.secret_id
  description = "Secret Manager secret id for IRC operator password."
}


