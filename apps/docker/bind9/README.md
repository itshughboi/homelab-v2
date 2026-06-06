### Permissions

The `ubuntu/bind9` image entrypoint defaults to running `named -u bind` (UID 101) regardless of `user: root` in compose. This means named drops to the `bind` user before reading config, and can't write to directories owned by your host user.

**Two fixes required:**

**1. Set `BIND9_USER=root` in compose** so the entrypoint calls `named -u root`:
```yaml
environment:
  - BIND9_USER=root
```

**2. Own the directories as root** — the container's root maps to real UID 0 on the host, so `chown root:root` is sufficient:
```sh
sudo chown -R root:root ./config /home/hughboi/data/bind9/cache
sudo chmod 755 ./config /home/hughboi/data/bind9/cache
sudo chmod 644 ./config/*.conf ./config/*.bind ./config/*.txt
sudo chmod 755 ./config/zones
# Tighten key files — should not be world-readable
sudo chmod 600 ./config/named.conf.key ./config/rndc.conf
```

Verify it started cleanly:
```sh
sudo docker compose logs bind9 | tail -5
dig @10.10.10.8 google.com +short
```

***

### DNS Chain
1. All queries go to BIND9
2. If query is for domain/zone BIND9 manages, it will give back IP (authoritative)
3. Otherwise, forward to Adguard
4. Adguard checks its cache and if it doesn't know it, forward to Unbound
5. Unbound performs full recursion and queries root -> TLD -> authoritative server
6. IP handed back to Adguard, cached entry in Unbound, Adguard then also caches it, and finally BIND9 returns answer to client

- Caching in Adguard + caching in Unbound reduces load on Unbound recursion


### Authoritative (local)
- Bind9 is authoritative for **hughboi.cc**
    - Question: What is gitea.hughboi.cc?
    - Bind9 checks if it has that zone. Since it does, it replies with the A/AAAA//CNAME record


### Recursive (external)
- Bind9 sends all external queries to Adguard/**Unbound** or Quad9 if Adguard is unavailable
    - Question: What is google.com IP?
    - Bind9 sees it is not a zone it is authoritative for, so it asks the Root servers to query **.com** TLD
    - **.com** then asks the authoritative for google.com. 
    - Bind9 returns the answer it got from google.com authoritative server and then caches it
    - Subsequent queries will be answered immediately by the Bind9 cache rather than asking the root TLD servers



### Root Files
- I configured Unbound to reference a local copy of the root servers rather than asking Cloudflare for them. Run this command to get the most up to date root servers:
```sh
wget -O /home/hughboi/code/adguard/unbound/root.hints https://www.internic.net/domain/named.cache
```