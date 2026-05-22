```sh
[global]
keyboard = "en-us"
country = "us"
timezone = "America/Denver"
root_password = "$6$HOZEESUiEsvs4sXb$dslqNOnvB92DbDFn/EfXvobrJ3NYHK42F5SEOrG1OLCmdMRlVDLKQaPy/xSQajstSVEEt5UKCGA0NKxUn/TFn/" #openssl passwd -6 "PasswordHere"
ssh_public_keys = [
  "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQD0pDplHGM1doYihQDolxx9uZQRHILnknTR8+pzDaUcx0B0YxyOpRbcM2XWaD67hHoTLvtt7khsqEiZ0CmPvNZV7d5biafxoi7s1L8khwRj0ahjTuclzDuAyoGKTS/JFUa0mT2Buoq4wbJlYdUcQ0PFWMlVnmkpnigtLQ9E0IaXGti2HCV/65zwS7xoQXdSTd2YEdksrkNRDjcMZSqV0U8x3AYFDQBWttvlBT6jgDSSOdyFhlkQAffQBy5AEeUEmfjuLCo352jRMqaTPK9HPL25bjFPwbAphyuYSuNr7qXNOq+rHCrakMApUw5t/hxJrZzpcWTRUSqMJpxkmeq9jXEb/B27EDxHJQUioO8SlxS/OrbQ0nbub5BD4E/kQ7lvMJliJB8JMDvRpozC7hvpJahgXbZlaTcpQy5pgMKrr53Tyc93HPH+82WFKYtaDOCbUu4xP8pijtF2PLtALUFnU5ZHaE49gNUEn/9WgVoxNQWXn8k2LkpOHQRVIherdUgHoxU+QO7CAGrLLb82T5Wb9KBXzt3ueyvooRrC3ZzOAPHpjetQy8z/fh5u7kPwoil+0BZ47vqHCRWQPLwzEsf+BII2e5VuEME/+oFldG12KC+MWRP87CXCPsQnu4uV8Im+tlaNY//R0kKFRb1vdKPmTg6Ocp16FcYvJ4rJ9ONWSM3bJw== seanhughes@MacBook-Pro.localdomain",
  "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIN7q284pL5oPwrp1NOwtNnkNiwX3R3z5F+qqYMmhTZYM ansible"
]

[network]
source = "from-answer"
hostname = "pve-srv-1"
fqdn = "pve-srv-1.hughboi.cc"
address = "10.10.10.1/24"
gateway = "10.10.10.254"
dns_list = ["9.9.9.9"]

[disk-setup]
filesystem = "ext4"
filter.ID_TYPE = "disk"
disk_list = []
```