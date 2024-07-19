#!/bin/bash
# Source the config.env file from the repo base directory
if [ -f "$(dirname "$0")/../.env" ]; then
  export $(grep -v '^#' "$(dirname "$0")/../.env" | xargs)
else
  echo "Error: .env file not found."
  exit 1
fi
# install ipcalc
apt update && apt-get -y install ipcalc

# create servie file
cp ./services/tailscale-subnet.service /etc/systemd/system

# create shell exec
SECONDARY_SUBNET=$(ipcalc -n $SECONDARY_CIDR | grep Network | awk '{print $2}')
cp ./shells/tailscale_subnet.sh .
sed -i "s|SECONDARY_SUBNET|$SECONDARY_SUBNET|g" tailscale_subnet.sh
sed -i "s|SECONDARY_GATEWAY|$SECONDARY_GATEWAY|g" tailscale_subnet.sh
mv tailscale_subnet.sh /etc/network

# enable and start service
systemctl enable tailscale-subnet.service && \
systemctl start tailscale-subnet.service