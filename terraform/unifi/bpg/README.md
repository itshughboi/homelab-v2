If using MetalLB, I do not need to deploy bgp at all. 

“How do IPs for Kubernetes Services become reachable from my network?”

There are two fundamentally different ways to solve that:

🟦 Option 1: MetalLB (L2 mode) — ARP-based

**What it does**

- Picks a Service IP
- One node answers ARP: “that IP is me”
- Traffic flows at Layer 2

**Characteristics**

- No routing changes
- No BGP
- UniFi stays dumb (which is good)
- Very homelab-friendly

**Pros**

- Simple
- Works everywhere
- Easy to debug (`arp -a`)
- UniFi fully supports this model

**Cons**

- L2 hacks
- Doesn’t scale well across subnets
- Failover relies on ARP timing

🟩 Option 2: BGP (Cilium or MetalLB BGP) — Routing-based

**What it does**

- Kubernetes advertises:
  - Service IPs
  - Pod CIDRs
- Router learns routes dynamically
- Traffic flows at Layer 3

**Characteristics**

- Real routing
- No ARP tricks
- Requires a BGP-capable router (your UniFi barely qualifies)

**Pros**

- Clean
- Scales well
- Fast failover
- Industry-standard

**Cons**

- Complexity
- Harder to troubleshoot
- UniFi support is… thin
- Easy to break prod traffic

❌ **Why you generally should NOT use both**

If you try to use MetalLB and BGP for the same Service IPs:

- ARP says: “IP is on node A”
- BGP says: “Route goes to node B”
- Network says: “lol good luck”

That leads to:

- Blackholes
- Flapping routes
- Intermittent connectivity
- The worst kind of bug (works sometimes)

✅ **Valid combinations (rare, but real)**

- ✔ MetalLB L2 only  
  Most homelabs. Most sane people. Probably you right now.
- ✔ BGP only  
  If:
  - You want routed LoadBalancers
  - You want to learn Cilium deeply
  - You’re okay debugging routing
- ⚠️ Both exist, but for different things  
  Example:
  - MetalLB L2 → legacy services
  - Cilium BGP → pod CIDRs only  

Even here:

- IP ranges must never overlap
- Clear ownership is mandatory
- Advanced networking knowledge required
- Not worth it for now.
