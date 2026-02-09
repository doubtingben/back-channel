


resource "random_password" "user_pwd" {
  for_each = var.user_passwords
  length   = 24
  special  = false
}

resource "google_secret_manager_secret" "user_pwd" {
  for_each  = var.user_passwords
  secret_id = "${each.key}-irc-passwd"

  replication {
    auto {}
  }
  depends_on = [google_project_service.secretmanager]
}

resource "google_secret_manager_secret_version" "user_pwd" {
  for_each    = var.user_passwords
  secret      = google_secret_manager_secret.user_pwd[each.key].id
  secret_data = each.value != "" ? each.value : random_password.user_pwd[each.key].result
}
