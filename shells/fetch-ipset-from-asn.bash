#!/bin/bash

usage() {
    echo "Usage: $0 [ASN]"
}

if [ $# -ne 1 ]; then
    usage
    exit 1
fi

ASN="${1}"

tempfile=$(mktemp)

create_or_flush_ipset() {
    local ipset_type="$1"
    local set_name="$2"

    # Check if ipset list exists, if it does, flush it, otherwise create it
    if ! sudo ipset list "$set_name" -q &>/dev/null; then
        sudo ipset create "$set_name" "$ipset_type"
    else
        sudo ipset flush "$set_name"
    fi
}

# Fetch IP blocks for the given ASN
input=$(curl -s "https://asn.ipinfo.app/api/text/list/AS${ASN}")

create_or_flush_ipset "hash:net family inet" "asn_${ASN}_v4"
create_or_flush_ipset "hash:net family inet6" "asn_${ASN}_v6"
create_or_flush_ipset "list:set" "asn_${ASN}"

echo "${input}" | grep -Eo "([0-9\.]{7,15}/[0-9]{1,2})" | sed "s|^|add asn_${ASN}_v4 |" >> "${tempfile}"
echo "${input}" | grep -Eo "([0-9a-f]+:){1,7}:/[0-9]{1,3}" | sed "s|^|add asn_${ASN}_v6 |" >> "${tempfile}"

echo "add asn_${ASN} asn_${ASN}_v4" >> "${tempfile}"
echo "add asn_${ASN} asn_${ASN}_v6" >> "${tempfile}"

sudo ipset restore < "${tempfile}"

echo "$(cat $tempfile | wc -l) rules added"

# Clean up the temporary file
rm -f "${tempfile}"
