terraform {
  required_version = "~> 1.9" # keep in step with CI (setup-terraform terraform_version)

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.94.0"
    }
  }
}

provider "proxmox" {
  endpoint  = var.proxmox_api_url
  api_token = var.proxmox_api_token
  insecure  = true # if proxmox is using Self Signed Certs
}
