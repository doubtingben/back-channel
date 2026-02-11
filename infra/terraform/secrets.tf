


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

# MySQL password for Ergo persistent history
resource "random_password" "mysql_pwd" {
  length  = 32
  special = true
}

resource "google_secret_manager_secret" "mysql_pwd" {
  secret_id = "ergo-mysql-password"

  replication {
    auto {}
  }
  depends_on = [google_project_service.secretmanager]
}

resource "google_secret_manager_secret_version" "mysql_pwd" {
  secret      = google_secret_manager_secret.mysql_pwd.id
  secret_data = random_password.mysql_pwd.result
}
