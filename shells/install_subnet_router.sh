#!/bin/bash
# colors
NC='\033[0m'       # Text Reset
Green='\033[1;32m'       # Green
Red='\033[1;31m'         # Red
Blue='\033[0;34m'         # Blue

# install iptables-persistant
echo iptables-persistent iptables-persistent/autosave_v4 boolean false | sudo debconf-set-selections
echo iptables-persistent iptables-persistent/autosave_v6 boolean false | sudo debconf-set-selections
apt update && apt-get -y install iptables-persistent ipcalc ipset

# Source the config.env file from the repo base directory
if [ -f "$(dirname "$0")/../.env" ]; then
  export $(grep -v '^#' "$(dirname "$0")/../.env" | xargs)
else
  echo -e "${RED}Error: .env file not foupnd.${NC}"
  exit 1
fi

# calculate subnets from CIDR
PRIMARY_SUBNET=$(ipcalc -n $PRIMARY_CIDR | grep Network | awk '{print $2}')
SECONDARY_SUBNET=$(ipcalc -n $SECONDARY_CIDR | grep Network | awk '{print $2}')

check_and_amend_rules() {
    local rules=("$@")
    for rule in "${rules[@]}"; do
        # Check if the rule exists
        if iptables -C ${rule} >/dev/null 2>&1; then
            echo -e "${Blue}Rule ${rule} already exists.${NC}"
        else
            # Amend the rule when it doesn't exist
            iptables -A ${rule}
            echo -e "${Green}Rule ${rule} has been added.${NC}"
        fi
    done
}

# Extract the SERVICES variable, removing the square brackets
SERVICES=$(echo $SERVICES | sed -E 's/\[|\]//g')

# Iterate over each service in the SERVICES variable
IFS=',' # Set Internal Field Separator to comma
for service in $SERVICES; do
  # Split the service into protocol and port
  PROTOCOL=$(echo "$service" | cut -d':' -f1)
  PORT=$(echo "$service" | cut -d':' -f2)

  # Add the rule to allow packets out for secondary subnet/ ignore primary subnet (tailscale will handle it)
  rules_to_check+=("allow-outgoing -t mangle -p $PROTOCOL --sport $PORT -j MARK --set-xmark 0x80000")
done
IFS=$' \t\n'

# masquerade egress for local subnet and allow public access to machine while using exit-node
ipset create bypass nethash
iptables -t mangle -N allow-outgoing
rules_to_check=(
    "OUTPUT -t mangle -j allow-outgoing"
    "POSTROUTING -t nat -o tailscale0 -j MASQUERADE"
    "allow-outgoing -t mangle -p icmp ! -s $PRIMARY_SUBNET -j MARK --set-xmark 0x80000"
    "allow-outgoing -t mangle -d 100.64.0.0/10 -j RETURN"
    "allow-outgoing -t mangle -s 100.64.0.0/10 -j RETURN"
    "allow-outgoing -t mangle -p icmp -j MARK --set-xmark 0x80000"
    "PREROUTING -t mangle -m set --match-set bypass dst -j MARK --set-mark 100"
    # set mss to 1200 for tailscale0 mtu cap of 1280
    "FORWARD -t mangle -o tailscale0 -p tcp -m tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1200"
)

check_and_amend_rules "${rules_to_check[@]}"
echo -e "${Green} iptables rules have been added.${NC}"

# iptables/ipset persistence
cp services/ipset-persistent.service /etc/systemd/system
cp services/ipset-fetch.service /etc/systemd/system
iptables-save > /etc/iptables/rules.v4
ip6tables-save > /etc/iptables/rules.v6
ipset save > /etc/iptables/ipset
systemctl enable ipset-persistent.service
# systemctl enable ipset-fetch.service
echo -e "${Green} iptables/ipset persistence has been enabled.${NC}"

# enable packet forwarding
echo 'net.ipv4.ip_forward = 1' > /etc/sysctl.d/99-tailscale.conf
echo 'net.ipv6.conf.all.forwarding = 1' >> /etc/sysctl.d/99-tailscale.conf
sysctl -p /etc/sysctl.d/99-tailscale.conf
echo -e "${Green} Packet forwarding has been enabled.${NC}"

# custom netplan for tailscale compatibility
cp ./configs/tailscale_config.yaml .
sed -i "s|SECONDARY_IFACE|$SECONDARY_IFACE|g" tailscale_config.yaml
sed -i "s|SECONDARY_CIDR|$SECONDARY_CIDR|g" tailscale_config.yaml
sed -i "s|SECONDARY_GATEWAY|$SECONDARY_GATEWAY|g" tailscale_config.yaml
sed -i "s|SECONDARY_IP|$(echo "$SECONDARY_CIDR" | sed 's#/.*##')|g" tailscale_config.yaml
sed -i "s|PRIMARY_IFACE|$PRIMARY_IFACE|g" tailscale_config.yaml
sed -i "s|PRIMARY_CIDR|$PRIMARY_CIDR|g" tailscale_config.yaml
sed -i "s|PRIMARY_GATEWAY|$PRIMARY_GATEWAY|g" tailscale_config.yaml
mv tailscale_config.yaml /etc/netplan
chmod 600 /etc/netplan/tailscale_config.yaml
echo -e "${Green} Custom netplan configuration has been added.${NC}"
netplan try

echo -e "${Blue}tailscale up --login-server=https://headscale.com --advertise-route=$PRIMARY_SUBNET,$SECONDARY_SUBNET --exit-node-allow-lan-access --accept-routes${NC}"