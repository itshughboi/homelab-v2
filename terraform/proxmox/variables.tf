variable "proxmox_api_token" {
  type      = string
  sensitive = true
}

variable "ssh_public_key" {
  type      = string
}

variable "proxmox_api_url" {
  type      = string
}

variable "proxmox_all" {
  type      = list(string)
  description = "All proxmox nodes"
}

variable "proxmox_master" {
  type      = string
  description = "pve-srv-1"
}

variable "proxmox_nodes_k3s" { 
  type      = list(string)  # needs to be list(string) if defining multiple nodes
  description = "pve-srv-2, pve-srv-3, pve-srv-4"
}
