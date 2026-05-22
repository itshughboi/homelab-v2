# resource "dns_a_record_set" "pve-srv-1" {
#     zone = "hughboi.cc."
#     name = "pve-srv-1"
#     addresses = "10.10.10.1"
# }


resource "dns_a_record_set" "proxmox" {
    zone = "hughboi.cc."
    name = "proxmox"
    addresses = [       # Round Robin DNS
        "10.10.10.1",
        "10.10.10.2",
        "10.10.10.3",
        "10.10.10.4"
    ]
}


