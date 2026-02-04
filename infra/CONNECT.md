# Connecting to the IRC Server

The IRC server handles connections directly via the VM on the following ports:

- **6667**: Plaintext IRC
- **6697**: TLS/SSL IRC

To connect securely, you must use port **6697** with TLS enabled.

## Prerequisite: Certificate Generation

The server infrastructure uses Let's Encrypt for TLS. The certificate generation happens via the Ansible playbook, but it requires the DNS record (`chat.interestedparticipant.org`) to point to the server's IP address.

If you have just applied Terraform, the DNS change might take a few minutes to propagate.
If the Ansible playbook ran before DNS propagation, the certificate generation might have failed. You can re-run the Ansible playbook or SSH into the server and run:

```bash
sudo certbot certonly --standalone -d chat.interestedparticipant.org
sudo systemctl restart ngircd
```

## Configuring Halloy

Update your `config.toml` to use port `6697` and enable TLS.

Example configuration for `chat.interestedparticipant.org`:

```toml
[servers.interestedparticipant]
nickname = "ben"
server = "chat.interestedparticipant.org"
port = 6697
use_tls = true
password = "<YOUR_SERVER_PASSWORD>" 
channels = ["#public"]
```

## Troubleshooting

- If connection fails, check if the `irc-server` firewall rule allows port 6697.
- Verify DNS resolution: `host chat.interestedparticipant.org` should match the Terraform output IP.
- Check server logs: `sudo journalctl -u ngircd`
