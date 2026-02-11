# IRC Account Tool

This binary replaces the Ansible `irc_accounts.yml` playbook. It manages Ergo IRC user accounts by reading `*-irc-passwd` secrets from GCP Secret Manager and registering/unregistering users via NickServ.

## Prerequisites

- Run on the Ergo host (needs access to `localhost:6697`).
- GCP credentials with access to Secret Manager.
- Systemd access to stop/start `ergo`, `irccat`, and `thelounge`.
- Operator password stored in Secret Manager (default secret: `irc-oper-password`).

## Build

```bash
cd infra/tools/irc-accounts

go build -o irc-accounts
```

## Usage

List all accounts from secrets (default):

```bash
./irc-accounts
```

Register all accounts from secrets:

```bash
./irc-accounts -action register
```

Register a single account:

```bash
./irc-accounts -action register -specific-user irccat
```

Unregister a single account:

```bash
./irc-accounts -action unregister -specific-user irccat
```

Reset all accounts (drops and re-inits the Ergo DB):

```bash
./irc-accounts -action reset_all
```

Dry run (no changes):

```bash
./irc-accounts -action register -dry-run
```

## Flags

- `-action` (default: `list`) — `list`, `register`, `unregister`, `reset_all`
- `-specific-user` — optional username to target for register/unregister
- `-project-id` (default: `analyze-this-2026`)
- `-secret-oper-password` (default: `irc-oper-password`)
- `-irc-host` (default: `localhost`)
- `-irc-port` (default: `6697`)
- `-tls-insecure` (default: `true`)
- `-timeout` (default: `15s`)
- `-ergo-conf` (default: `/etc/ergo/ircd.yaml`)
- `-ergo-db` (default: `/var/lib/ergo/ircd.db`)
- `-ergo-bin` (default: `/usr/local/bin/ergo`)
- `-dry-run`
- `-skip-restart`
