terraform {
  required_version = "~> 1.9" # keep in step with CI (setup-terraform terraform_version)

  required_providers {
    dns = {
      source  = "hashicorp/dns"
      version = "3.4.3"
    }
  }
}

provider "dns" {
  update {
    server        = var.dns_server_ip
    key_name      = "tsig-key."
    key_algorithm = "hmac-sha256"
    key_secret    = var.tsig_key
  }
}
