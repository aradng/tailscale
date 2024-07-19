#!/bin/bash
# install iptables-persistant
echo iptables-persistent iptables-persistent/autosave_v4 boolean false | sudo debconf-set-selections
echo iptables-persistent iptables-persistent/autosave_v6 boolean false | sudo debconf-set-selections
apt update && apt-get -y install iptables-persistent ipcalc

# Source the config.env file from the repo base directory
if [ -f "$(dirname "$0")/../.env" ]; then
  export $(grep -v '^#' "$(dirname "$0")/../.env" | xargs)
else
  echo "Error: .env file not foupnd."
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
            echo "Rule '${rule}' already exists."
        else
            # Amend the rule when it doesn't exist
            iptables -A ${rule}
            echo "Rule '${rule}' has been added."
        fi
    done
}

# Extract the SERVICES variable, removing the square brackets
SERVICES=$(echo $SERVICES | sed -E 's/\[|\]//g')

# masquerade egress for local subnet and allow public access to machine while using exit-node
iptables -t mangle -N allow-outgoing
rules_to_check=(
    "POSTROUTING -t nat -o tailscale0 -j MASQUERADE"
    "allow-outgoing -t mangle -p icmp -j MARK --set-xmark 0x80000"
)
# Iterate over each service in the SERVICES variable
IFS=',' # Set Internal Field Separator to comma
for service in $SERVICES; do
  # Split the service into protocol and port
  PROTOCOL=$(echo "$service" | cut -d':' -f1)
  PORT=$(echo "$service" | cut -d':' -f2)

  # Add the rule to allow packets out for secondary subnet/ ignore primary subnet (tailscale will handle it)
  rules_to_check+=("allow-outgoing -t mangle -p $PROTOCOL ! -s $PRIMARY_SUBNET --sport $PORT -j MARK --set-xmark 0x80000")
#   rules_to_check+=("allow-outgoing -t mangle -p $PROTOCOL -d $PRIMARY_SUBNET --sport $PORT -j MARK --set-xmark 0x80000")
done

check_and_amend_rules "${rules_to_check[@]}"

# iptables persistence
iptables-save > /etc/iptables/rules.v4
ip6tables-save > /etc/iptables/rules.v6

# enable packet forwarding
echo 'net.ipv4.ip_forward = 1' > /etc/sysctl.d/99-tailscale.conf
echo 'net.ipv6.conf.all.forwarding = 1' >> /etc/sysctl.d/99-tailscale.conf
sysctl -p /etc/sysctl.d/99-tailscale.conf

# custom netplan for tailscale compatibility
cp ./configs/tailscale_config.yaml .
sed -i "s|SECONDARY_CIDR|$SECONDARY_CIDR|g" tailscale_config.yaml
sed -i "s|SECONDARY_GATEWAY|$SECONDARY_GATEWAY|g" tailscale_config.yaml
sed -i "s|SECONDARY_IP|$(echo "$SECONDARY_CIDR" | sed 's#/.*##')|g" tailscale_config.yaml
sed -i "s|PRIMARY_CIDR|$PRIMARY_CIDR|g" tailscale_config.yaml
sed -i "s|PRIMARY_GATEWAY|$PRIMARY_GATEWAY|g" tailscale_config.yaml
mv tailscale_config.yaml /etc/netplan
netplan try

echo "tailscale up --login-server=https://headscale.com --advertise-route=$PRIMARY_SUBNET,$SECONDARY_SUBNET --exit-node-allow-lan-access --accept-routes"