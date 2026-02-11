# IRC Account Management

This playbook manages user accounts on the Ergo IRC server.

## Prerequisites

- Ergo IRC server must be running
- You must have operator credentials stored in GCP Secret Manager
- User passwords must be stored in GCP secrets with the pattern `<username>-irc-passwd`

## Usage

### Register All IRC Accounts

This registers all users whose passwords are stored in GCP secrets:

```bash
ansible-playbook -i inventory.ini irc_accounts.yml -e "action=register"
```

### Register a Specific User

To register just one user:

```bash
ansible-playbook -i inventory.ini irc_accounts.yml -e "action=register" -e "specific_user=irccat"
```

### Unregister a User

To remove a user account:

```bash
ansible-playbook -i inventory.ini irc_accounts.yml -e "action=unregister" -e "specific_user=irccat"
```

### Reset All Accounts (Nuclear Option)

This will:
1. Stop Ergo and related services
2. Backup and delete the Ergo database
3. Reinitialize a fresh database
4. Register all users from GCP secrets
5. Restart services

```bash
ansible-playbook -i inventory.ini irc_accounts.yml -e "action=reset_all"
```

**⚠️ Warning**: This will delete all existing accounts, channels, and history!

## GCP Secret Format

User passwords should be stored in GCP Secret Manager with names matching the pattern:
- `<username>-irc-passwd` - Contains the password for the user

Example:
- Secret name: `irccat-irc-passwd`
- Secret value: `your_password_here`
- Resulting account: `irccat` with the password from the secret

## Variables

You can override these variables with `-e`:

- `action`: What operation to perform
  - `register` - Register users (default)
  - `unregister` - Remove users
  - `reset_all` - Nuclear reset of all accounts
- `specific_user`: Username to target (optional, for register/unregister)
- `project_id`: GCP project ID (default: `analyze-this-2026`)
- `secret_oper_password`: Name of the operator password secret (default: `irc-oper-password`)

## Examples

### Fix irccat authentication issue

```bash
# Unregister the old account
ansible-playbook -i inventory.ini irc_accounts.yml -e "action=unregister" -e "specific_user=irccat"

# Register it fresh
ansible-playbook -i inventory.ini irc_accounts.yml -e "action=register" -e "specific_user=irccat"
```

### Add a new bot account

```bash
# 1. First, create the secret in GCP:
gcloud secrets create mybot-irc-passwd --data-file=- <<< "strong_password_here" --project=analyze-this-2026

# 2. Register the account
ansible-playbook -i inventory.ini irc_accounts.yml -e "action=register" -e "specific_user=mybot"
```

## Troubleshooting

### "Command restricted" error

If you see this error, the operator account may not have the required capabilities. Add the `unregister` capability to the `server-admin` oper class in `templates/ergo.yaml.j2` and redeploy.

### Account already exists

Use the `unregister` action first, then `register` again.

### Fresh start needed

Use `action=reset_all` to completely reset all accounts and start fresh.
