$TTL    3d                                                          ; 3 day TTL cached records 

                                                                    ; **State of Authority** (SOA) = metadata for the zone 
@       IN      SOA     ns1.hughboi.cc. admin.hughboi.cc. (
                        2024091808  ; Serial (YYYYMMDDNN)           ; change every time I edit zone
                        1w          ; Refresh (1 week)              ; checks updates from secondary DNS server at this interval
                        1d          ; Retry (1 day)                 ; if refresh fails, retry daily
                        4w          ; Expire (4 weeks)              ; if no refresh succeeds for 4 weeks, discard data
                        1w )        ; Negative Cache TTL (1 week)   ; how long NXDOMAIN (nonexistent) responses are cached

                                                                    ; **Nameserver definition**
@       IN      NS      ns1.hughboi.cc.                             ; says the authoritative nameserver for hughboi.cc is **ns1.hughboi.cc**


                                                                    ; A records for the domain
@                   IN      A       10.10.10.10                     ; root domain hughboi.cc (Traefik)
ns1                 IN      A       10.10.10.9	                    ; local server IP
*                   IN      A       10.10.10.10                     ; Wildcard for subdomains of hughboi.cc -> NGINX

                                                                    ;production-servers
pve-srv-1           IN      A       10.10.10.1
pve-srv-2           IN      A       10.10.10.2
pve-srv-3           IN      A       10.10.10.3
pve-srv-4           IN      A       10.10.10.4
truenas             IN      A       10.10.10.5
pbs                 IN      A       10.10.10.6                      ; Port 8007 - Proxmox Backup Server
postgres            IN      A       10.10.10.7                      ; Port 5432
ansible             IN	    A	    10.10.10.8
bind9               IN      A       10.10.10.9
ubnt-prod           IN      A       10.10.10.10

                                                                    ; test dig/nslookup
testing             IN      A       10.99.99.99                     ; test
testing2	        IN 	    A 	    10.69.69.69                     ; testing2



; ------------------------------------------------------------------------------------------------

; CNAME Records (if you have subdomains or aliases)
www                 IN      CNAME   @                               ; www.hughboi.cc points to @ (main domain)

; MX Records (if you have mail servers)
@                   IN      MX      10 mail.hughboi.cc.             ; lower number = higher priotity if I have multiple MX

; PTR Records (optional, for reverse DNS lookups if needed)
;These should be in a reverse zone file!!!!!!
; 10.10.10.10       IN      PTR     www.hughboi.cc.
; 10.10.10.210      IN      PTR     mail.hughboi.cc.

; Any additional records
; Define TXT records if needed for verification or SPF
; @                 IN      TXT     "v=spf1 ip4:10.10.10.0/24 -all"

; Additional records (for mail, VPN, or other services)
mail                IN      A       10.10.10.25    ; Change IP to mail server IP

