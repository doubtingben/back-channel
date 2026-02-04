variable "project_id" {
  type        = string
  description = "GCP project id."
}

variable "region" {
  type        = string
  description = "GCP region."
  default     = "us-central1"
}

variable "domain" {
  type        = string
  description = "DNS name for the IRC service."
  default     = "chat.interestedparticipant.org"
}

variable "server_name" {
  type        = string
  description = "IRC server name shown to clients."
  default     = "chat.interestedparticipant.org"
}

variable "irc_port_internal" {
  type        = number
  description = "Backend IRC port used by the load balancer."
  default     = 6667
}

variable "irc_port_external" {
  type        = number
  description = "External port exposed by the SSL proxy. Google-managed certs require 443."
  default     = 443
}

variable "network" {
  type        = string
  description = "VPC network name."
  default     = "default"
}

variable "subnetwork" {
  type        = string
  description = "Optional subnetwork self link or name."
  default     = ""
}

variable "machine_type" {
  type        = string
  description = "Instance machine type."
  default     = "e2-micro"
}

variable "source_image" {
  type        = string
  description = "Boot image for the IRC VM."
  default     = "debian-cloud/debian-12"
}

variable "irc_server_password" {
  type        = string
  description = "Server password (PASS) required for clients. Leave empty to auto-generate."
  default     = ""
  sensitive   = true
}

variable "irc_oper_password" {
  type        = string
  description = "IRC operator password. Leave empty to auto-generate."
  default     = ""
  sensitive   = true
}

variable "ssh_username" {
  type        = string
  description = "SSH username to connect with Ansible."
  default     = "debian"
}

variable "ssh_public_key" {
  type        = string
  description = "SSH public key to add to instance metadata."
  default     = ""
}

variable "ssh_source_ranges" {
  type        = list(string)
  description = "CIDR ranges allowed to SSH to the instances."
  default     = ["0.0.0.0/0"]
}

variable "cloudflare_api_token" {
  type        = string
  description = "Cloudflare API token with DNS edit permissions."
  default     = ""
  sensitive   = true
}

variable "cloudflare_zone_id" {
  type        = string
  description = "Cloudflare zone ID for interestedparticipant.org."
  default     = ""
}

variable "cloudflare_manage_dns" {
  type        = bool
  description = "Whether Terraform should manage the Cloudflare DNS record."
  default     = true
}
