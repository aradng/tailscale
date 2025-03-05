# Tailscale Subnet Router

This repository contains scripts to set up a Tailscale router.

## Installation

**Before running the scripts, make sure to create .env with the correct values:**

```dotenv
PRIVATE_CIDR=10.0.0.2/24
PUBLIC_CIDR=30.0.0.2/24
PUBLIC_GATEWAY=30.0.0.1
SERVICES=[tcp:22,tcp:80,tcp:443]
```

Here's a breakdown of what each entry represents:

- `PRIVATE_CIDR`: Defines the CIDR notation for the Tailscale subnet router.
- `PUBLIC_CIDR`: Defines the CIDR notation for the public-facing subnet.
- `PUBLIC_GATEWAY`: Specifies the gateway IP for the public-facing subnet.
- `SERVICES`: Lists the services and their respective ports that you want to allow. In this example, `tcp:22` (SSH), `tcp:80` (HTTP), and `tcp:443` (HTTPS) are specified.

The Tailscale subnet router in the internal network has an IP address of `10.0.0.2`, which routes traffic through its respective gateway. The public-facing IP address of this router is `30.0.0.2`, which routes traffic through `30.0.0.1`.

Make sure to adjust the values according to your specific network configuration needs.

##### Keep in mind that the `SERVICES` variable represents a list of protocols and ports that the client exposes on its public subnet (IP). In Tailnet, all services are accessible from both subnets when advertised in accordance with Tailnet ACL.

### Tailscale Router Setup

To set up a Tailscale router, use the install.bash script. This script configures the necessary routes and settings on your primary router, enabling other devices using this router as a gateway to access the Tailscale network, provided --accept-routes=true is set. Additionally, it allows these devices to use the router's default route (exit-node) to access the broader internet, which is particularly useful when you're behind restrictive networks or ISPs.

There are two ipset lists named bypass and bypass_ports that bypass Tailscale routing and use the main routing table instead. You can add IPs and Ports to these ipsets to ensure they are routed externally using the main routing table, exempting them from Tailnet and the exit-node.

A script is available that adds region-specific CIDRs to the ipset for localized routing, potentially providing better performance. This script needs to be adjusted for code, ipset_name, url, and filename, which can be obtained from ip2location.com.

Additionally, there is an ipset-fetch.service that can be installed for periodic fetching and updating of these rules, as region-specific ASNs may change over time.

To execute the setup script, run:

```bash
bash ./shells/instal.bash
```

##### Try to run this on a server with default iptable rules to ensure that there are no undesirable rules retained through reboots after script modifications.

#### Service Exposition

By default the script only allows ICMP requests

# Troubleshooting
## Common issues
- always check `tailscale status` for healthcheck issues
- check `journalctl -fu tailscaled` or `debug daemon-logs --verbose 5`
- if stuck trying tailscale fallback dns resolvers | stuck on DoLogin can stop in each stage if resolved:
    - `tailscale set --exit-node=`
    - `tailscale set --accept-dns=false`
    - `cat /etc/resolv.conf` check change has propagated
    - `tailscale debug restun`
    - `tailscale debug rebind`
    - `systemctl restart tailscaled`
    - if there are iptables/nftable conflicts (specially ipv6) in healthcheck reboot the machine
    - if issue is still unresolved check for node to controlplane connectivity
- if advertised-routes/exit-node create/update is not registering in headscale or propagating:
    - `systemctl restart tailscaled` on advertiser & clients
    - `tailscale up --force-reauth` if issue still persists
- during exit-node usage:
    - if you have problem accessing your local subnet/loopback iface:
        - `tailscale set --exit-node-allow-lan-access`
    - if tailscale magic-dns/split-horizen dns is not working or advertised routes are not visible:
        - check `tailscale debug resolve <ip>`
        - check `tailscale dns query <ip>` ensure its correct pathing conforming to controlplane setup
        - on exit-node machine:
            - `tailscale set --accept-dns`
            - `tailscale set --accept-routes`
    - if connection stuck on relayed:
        - `tailscale ping <exit-node-tailnet-ip>` force tailscale to look for direct connection
        - `tailscale netcheck` check for hairpinning or udp support issues
        - `tailscale netcheck` check on exit-node 
        - ensure no firewalls are configured on each client/upstream nat (port `41641`) if `randomize_port` is false or enable `upnp/nat-pmp`
        - provision another exit-node (might be censored)
- if unsure about client state:
    - `taiscale debug perfs` for client state
    - `tailscale debug netmap` for controlplane posture/acl encforcements
- if hairloss:
    - `tailscale debug capture`    

## Bad Dobby (Donts)
- `tailscale debug capture`
- do not install tailscale clients on subnet-router clients
    - if its neccesary:
        - DO NOT accept routes
        - DO NOT set client exit-node on corresponding subnet router or vice verse (switching loop)
        - DO NOT advertise-routes on HA setup
        - DO NOT advertise-exit-node unless you are well-versed in iptables `:)`
- do not setup exit-nodes on an advertised-subnet by another primary
    - if its neccesary:
        - advertise subnet on exit-node aswell
        - do not allow advertised-route from exit-node in headscale
## DOs
- check tailscale/headscale changelog. number of features this repo implements have been cut in third and are present in the client/controlplane due to these updates.
- update headscale regularly w/ db backups
- accumulate client metrics for better network observability
- dont go cheap on controlplane's machine

### References
- [Tailscale Subnet Router Setup](https://tailscale.com/kb/1019/subnets)
- [Tailscale Subnet Router Public IP Service Exposition](https://github.com/tailscale/tailscale/issues/10940#issuecomment-1909182044)
- [LXC Network K8s Compatibility](https://chris.heald.me/2018/docker-default-routes/)
- [LXC Network Docker Compatibility (inspiration)](https://serverfault.com/a/743314)
