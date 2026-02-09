# IRC on GCP (Cloud Run constraint note)

Cloud Run only supports HTTP(S)/gRPC traffic; it does not accept raw TCP connections required by IRC. This deployment uses a Compute Engine backend with a global SSL proxy load balancer so IRC clients can connect securely.

## What this creates
- Global external IP + SSL proxy load balancer (TCP 443 by default).
- Managed SSL certificate for `chat.interestedparticipant.org`.
- Regional managed instance group running `ngircd`.
- Secret Manager secrets for IRC server/oper passwords.

## Manual steps required
1) **Cloudflare DNS**: Set `CLOUDFLARE_API_TOKEN` environment variable and provide `cloudflare_zone_id` so Terraform can create the A record. If you want to do DNS manually, set `cloudflare_manage_dns=false` and create the A record for `chat.interestedparticipant.org` pointing to the `irc_ip` output.
2) **Wait for cert**: Google-managed certs only become `ACTIVE` after DNS propagates. This can take minutes to hours.
3) **Run Ansible**: After Terraform finishes, run the playbook to install/configure ngircd.
4) **Client connection**: Use TLS on port `443` (default). Example: `ircs://chat.interestedparticipant.org:443` and supply the server password (PASS).
5) **Optional**: If you want the standard IRC TLS port `6697`, switch `irc_port_external` to `6697` and use a self-managed certificate instead of Google-managed.

## Deploy
```bash
cd infra/terraform
terraform init
terraform apply \
  -var="project_id=YOUR_PROJECT_ID" \

  -var="cloudflare_zone_id=YOUR_CF_ZONE_ID" \
  -var="ssh_public_key=$(cat ~/.ssh/id_rsa.pub)" \
  -var="ssh_source_ranges=[\"YOUR_IP_CIDR/32\"]"
```

## Secrets
- If you do not supply `irc_server_password` or `irc_oper_password`, Terraform generates them and stores in Secret Manager.
- To set your own:
```bash
terraform apply \
  -var="project_id=YOUR_PROJECT_ID" \
  -var="irc_server_password=YOUR_SERVER_PASS" \
  -var="irc_oper_password=YOUR_OPER_PASS"
```

## Ansible setup
Terraform generates `infra/terraform/ansible/inventory.ini` based on the live instance IPs.

Run the playbook:
```bash
cd infra/terraform/ansible
ansible-playbook playbook.yml \
  -e project_id=YOUR_PROJECT_ID \
  -e server_name=chat.interestedparticipant.org \
  -e irc_port_internal=6667
```

The playbook installs the Google Cloud Ops Agent to ship system logs to Cloud Logging.

## Outputs
- `irc_ip`: the global external IP to use in DNS.
- `irc_external_port`: the TLS port exposed by the load balancer.
- `ansible_inventory_path`: where Terraform wrote the inventory file.
