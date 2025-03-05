#!/bin/bash
usage() {
    echo "Usage: $0 [ZONE]"
}

if [ $# -ne 1 ]; then
    usage
    exit 1
fi

ZONE="${1}"

if sudo ipset list $ZONE -q > /dev/null 2>&1; then
    echo "$ZONE ipset exists. Flushing old entries..."
    sudo ipset flush $ZONE
else
    echo "$ZONE ipset does not exist. Creating new ipset..."
    sudo ipset create $ZONE hash:net
fi

wget -q -O - https://www.ipdeny.com/ipblocks/data/countries/$ZONE.zone | sed "s/^/add $ZONE /" | sudo ipset restore -! 

ip_count=$(sudo ipset list $ZONE -t | grep "Number of entries" | awk '{print $4}')
echo "$ip_count blocks added to $ZONE ipset"
