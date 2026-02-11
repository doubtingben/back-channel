# IRC Account Management

This playbook is now superseded by the Go tool in `infra/tools/irc-accounts`. Use the new binary for account management. The default action is now `list`.

## Prerequisites

- Ergo IRC server must be running
- You must have operator credentials stored in GCP Secret Manager
- User passwords must be stored in GCP secrets with the pattern `<username>-irc-passwd`

## Usage (Go Tool)

### Register All IRC Accounts

This registers all users whose passwords are stored in GCP secrets:

```bash
cd infra/tools/irc-accounts
go build -o irc-accounts
./irc-accounts -action register
```

### Register a Specific User

To register just one user:

```bash
./irc-accounts -action register -specific-user irccat
```

### Unregister a User

To remove a user account:

```bash
./irc-accounts -action unregister -specific-user irccat
```

### Reset All Accounts (Nuclear Option)

This will:
1. Stop Ergo and related services
2. Backup and delete the Ergo database
3. Reinitialize a fresh database
4. Register all users from GCP secrets
5. Restart services

```bash
./irc-accounts -action reset_all
```

**⚠️ Warning**: This will delete all existing accounts, channels, and history!

## GCP Secret Format

User passwords should be stored in GCP Secret Manager with names matching the pattern:
- `<username>-irc-passwd` - Contains the password for the user

Example:
- Secret name: `irccat-irc-passwd`
- Secret value: `your_password_here`
- Resulting account: `irccat` with the password from the secret

## Flags

- `-action`: What operation to perform
  - `register` - Register users (default)
  - `unregister` - Remove users
  - `reset_all` - Nuclear reset of all accounts
- `-specific-user`: Username to target (optional, for register/unregister)
- `-project-id`: GCP project ID (default: `analyze-this-2026`)
- `-secret-oper-password`: Name of the operator password secret (default: `irc-oper-password`)

## Examples

### Fix irccat authentication issue

```bash
# Unregister the old account
./irc-accounts -action unregister -specific-user irccat

# Register it fresh
./irc-accounts -action register -specific-user irccat
```

### Add a new bot account

```bash
# 1. First, create the secret in GCP:
gcloud secrets create mybot-irc-passwd --data-file=- <<< "strong_password_here" --project=analyze-this-2026

# 2. Register the account
./irc-accounts -action register -specific-user mybot
```

## Troubleshooting

### "Command restricted" error

If you see this error, the operator account may not have the required capabilities. Add the `unregister` capability to the `server-admin` oper class in `templates/ergo.yaml.j2` and redeploy.

### Account already exists

Use the `unregister` action first, then `register` again.

### Fresh start needed

Use `action=reset_all` to completely reset all accounts and start fresh.
