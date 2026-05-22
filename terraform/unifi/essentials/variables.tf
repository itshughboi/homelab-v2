variable "api_url" {
  type      = string
}

variable "api_key" {
  type      = string
  sensitive = true
}

variable "unifi_username" {
  type      = string
}

variable "unifi_password" {
  type      = string
  sensitive = true
}

variable "allow_insecure" {
  type      = bool
}

variable "unifi_site" {
  type      = string
}