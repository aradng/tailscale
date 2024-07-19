# Tailscale Subnet Router and LXC Compatibility Layer

This repository contains scripts to set up a Tailscale router and install a compatibility layer for LXC containers using the first machine as a gateway. 

## Installation

**Before running the scripts, make sure to create .env with the correct values:**

```dotenv
PRIMARY_CIDR=10.0.0.2/24
PRIMARY_GATEWAY=10.0.0.1
SECONDARY_CIDR=30.0.0.2/24
SECONDARY_GATEWAY=30.0.0.1
SERVICES=[tcp:22,tcp:80,tcp:443]
```

Here's a breakdown of what each entry represents:

- `PRIMARY_CIDR`: Defines the CIDR notation for the Tailscale subnet router.
- `PRIMARY_GATEWAY`: Specifies the gateway IP for the Tailscale subnet router.
- `SECONDARY_CIDR`: Defines the CIDR notation for the public-facing subnet.
- `SECONDARY_GATEWAY`: Specifies the gateway IP for the public-facing subnet.
- `SERVICES`: Lists the services and their respective ports that you want to allow. In this example, `tcp:22` (SSH), `tcp:80` (HTTP), and `tcp:443` (HTTPS) are specified.

The Tailscale subnet router in the internal network has an IP address of `10.0.0.2`, which routes traffic through the gateway via `10.0.0.1`. The public-facing IP address of this router is `30.0.0.2`, which routes traffic through the gateway via `30.0.0.1`. Client-side rules are derived from these addresses.

Make sure to adjust the values according to your specific network configuration needs.
##### keep in mind that `SERVICES` variable represents a list of protocols and port the client exposes on it's secondary subnet (public ip). but in tailnet all services are accessible from both subnets when advertised in accordance to tailnet ACL.
### 1. Tailscale Router Setup

To set up a Tailscale router, use the `install_subnet_route.sh` script. This script configures the necessary routes and settings on your primary router, enabling other devices that use this router as a gateway to access the Tailscale network (if `--accept-routes=true`). It also allows these devices to use the router's default route (exit-node) to access the broader internet, which is particularly useful when you're behind restrictive networks or ISPs.

To execute the setup script, run:
```bash
./install_subnet_route.sh
```
##### Try to run this on a server with default iptable rules to ensure that there are no undesirable rules retained through reboots after script modifications.
#### Service Exposition

By default the script only allows ICMP requests

### 2. LXC Compatibility Layer

To install the compatibility layer for LXC containers and Docker containers that will route through the Tailscale network using the first machine as a gateway, use the `install_client.sh` script. This script configures LXC and Docker networking to route traffic properly through the Tailscale network. After running the script, each container can recieve from multiple network interfaces: one pointing to the Tailscale subnet router as its main gateway and another exposing services to the public internet.

To execute the setup script, run:
```bash
./install_client.sh
```

### References

- [Tailscale Subnet Router Setup](https://tailscale.com/kb/1019/subnets)
- [Tailscale Subnet Router Public IP Service Exposition](https://github.com/tailscale/tailscale/issues/10940#issuecomment-1909182044)
- [LXC Network K8s Compatibility](https://chris.heald.me/2018/docker-default-routes/)
- [LXC Network Docker Compatibility (inspiration)](https://serverfault.com/a/743314)