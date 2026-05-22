### Adguard Installation
1. Remove stub listener on linux host
```sh
sudo nano /etc/systemd/resolved.conf
```
```sh
#LLMNR=no
#Cache=no-negative
#CacheFromLocalhost=no
DNSStubListener=no
#DNSStubListenerExtra=3
#ReadEtcHosts=yes
```
^^ Uncomment DNSStubListener=yes & set the value to 'no'
```
sudo systemctl restart systemd-resolved
```

!! Copy over the following to ${DATA_ROOT}/adguard/unbound (pick between 2 and 3. Not both):
1. unbound/unbound.conf to ${DATA_ROOT}/adguard/unbound
2. forward-records.con to ${DATA_ROOT}/adguard/unbound << IF USING DoT instead of Root-hints (what I always do). **REFERENCE ONLY. NOT USED!**
3. unbound/root.hints to ${DATA_ROOT}/adguard/unbound << **MY GO TO. LOVE THIS OPTION!!!! PICK ME!**


## Unbound
- Recursive & Caching DNS Server (better performance over using just Adguard -> Quad9)
1. Inside Adguard UI -> DNS Forwarder
- Set this to be the docker IP we created for unbound. In my example, I will use **192.168.100.10**
2. Test resolution again


### DoT (Optional)
> [!NOTE] Include forward-records.conf and comment out root-hints on unbound.conf
> DoT isn't possible with root server, so need to disable it (commentroot-hints: "/opt/unbound/etc/unbound/root.hints") and uncomment (
    #include: /opt/unbound/etc/unbound/forward-records.conf)

- I have to pick between using DoT with forwarders to something like Quad9 or Cloudflare over port 853, or having Unbound query root servers directly, but that's all unencrypted plaintext (port 53).

If I want to do DoT, essentially I need to add a 'forward-records.conf' file where unbound has a volume mounted. Then in the unbound.conf comment the root hints, and uncomment the **include: "/opt/unbound/etc/unbound/forward-records.conf"**

*forward-records.conf*
```
forward-zone:
    # Forward all queries (except those in cache and local zone) to
    # upstream recursive servers
    name: "."
    # Queries to this forward zone use TLS
    forward-tls-upstream: yes

    # https://dnsprivacy.org/wiki/display/DP/DNS+Privacy+Test+Servers

    ## Cloudflare
    #forward-addr: 1.1.1.1@853#cloudflare-dns.com
    #forward-addr: 1.0.0.1@853#cloudflare-dns.com
    #forward-addr: 2606:4700:4700::1111@853#cloudflare-dns.com
    #forward-addr: 2606:4700:4700::1001@853#cloudflare-dns.com

    ## Cloudflare Malware
    # forward-addr: 1.1.1.2@853#security.cloudflare-dns.com
    # forward-addr: 1.0.0.2@853#security.cloudflare-dns.com
    # forward-addr: 2606:4700:4700::1112@853#security.cloudflare-dns.com
    # forward-addr: 2606:4700:4700::1002@853#security.cloudflare-dns.com

    ## Quad9
    forward-addr: 9.9.9.9@853#dns.quad9.net
    forward-addr: 149.112.112.112@853#dns.quad9.net
    forward-addr: 2620:fe::fe@853#dns.quad9.net
    forward-addr: 2620:fe::9@853#dns.quad9.net

```

TL;DR
- only using root.hints and unbound.conf with no forwarding to anything in forward-records.conf and no DoT because I'm querying root servers directly



#### Update Root.Hints
- Update every few months << figure out how to get n8n to automate this



### TO document
1. how to getdnssec working with the key files << how to generate
2. figure out if i should move or set more permissive things on the unbound.log that is getting snatched by promtail
3. play around with adguard log levels for loki
4. automate root.hints update with n8n or ansible
5. how to have these ci/cd oriented and then apply to container so i can push changes, commit, apply, rebuild.
6. lock down key files for bind9 to least access
7. update my records
8. Automate root hints file every few months or so