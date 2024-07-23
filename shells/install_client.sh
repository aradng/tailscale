#!/bin/bash
# colors
NC='\033[0m'       # Text Reset
Green='\033[1;32m'       # Green
Red='\033[1;31m'         # Red
Blue='\033[0;34m'         # Blue
# Source the config.env file from the repo base directory
if [ -f "$(dirname "$0")/../.env" ]; then
  export $(grep -v '^#' "$(dirname "$0")/../.env" | xargs)
else
  echo -e "${Red}Error: .env file not found.${NC}"
  exit 1
fi
# install ipcalc
apt update && apt-get -y install ipcalc

# create servie file
cp ./services/tailscale-subnet.service /etc/systemd/system
echo -e "${Green}Service file created.${NC}"

# create shell exec
SECONDARY_SUBNET=$(ipcalc -n $SECONDARY_CIDR | grep Network | awk '{print $2}')
cp ./shells/tailscale_subnet.sh .
sed -i "s|SECONDARY_SUBNET|$SECONDARY_SUBNET|g" tailscale_subnet.sh
sed -i "s|SECONDARY_GATEWAY|$SECONDARY_GATEWAY|g" tailscale_subnet.sh
mv tailscale_subnet.sh /etc/network
echo -e "${Green}Shell exec created.${NC}"

# enable and start service
systemctl enable tailscale-subnet.service && \
systemctl start tailscale-subnet.service
echo -e "${Green}Service enabled and started.${NC}"