import os
import re
import csv
import socket
import struct
import ipaddress
from io import BytesIO
import requests
import zipfile
import logging

# user settings
code = "IR"
ipset_net = "bypass"
# ip2location urls & filenames
url = "https://download.ip2location.com/lite/IP2LOCATION-LITE-DB1.CSV.ZIP"
file_name = "IP2LOCATION-LITE-DB1.CSV"

logging.getLogger("urllib3").setLevel(logging.WARNING)

logger = logging.getLogger(__name__)
logger.setLevel(logging.DEBUG)
formatter = logging.Formatter(
    fmt="%(asctime)s %(name)s %(levelname)s %(message)s",
    datefmt="%H:%M:%S",
)
logging.basicConfig(
    # filename="ig_crawl.log",
    # filemode="a",
    format="%(asctime)s,%(msecs)d %(name)s %(levelname)s %(message)s",
    datefmt="%H:%M:%S",
    level=logging.DEBUG,
)


def download_file(url) -> str:
    return requests.get(url, allow_redirects=True).content


def unzip(content, fn):
    zf = zipfile.ZipFile(BytesIO(content))
    with zf.open(fn) as f:
        return f.read().decode().splitlines()


def filter_location(cidrs, code):
    filtered = [i for i in cidrs if code in i]
    return [i.split('"')[1] for i in filtered]


def no2ip(iplong):
    if int(iplong) > 4294967295:
        return ipaddress.ip_address(int(iplong)).__str__()
    else:
        return socket.inet_ntoa(struct.pack("!I", int(iplong)))


def create_rules(cidrs, net):
    return [f"ipset add {net} {i}" for i in cidrs]


def exec_rules(rules):
    for rule in rules:
        os.system(rule)


def iprange_to_cidr(startip, endip, total_row, row, cidrs, ipaddress):
    ar = []
    ar1 = []
    for ipaddr in ipaddress.summarize_address_range(startip, endip):
        ar.append(ipaddr)
    for i in range(len(ar)):
        ar1.append(str(ar[i]))
    # print (ar1)
    remaining_columns = ""
    for i in range(2, total_row):
        if i == (total_row - 1):
            remaining_columns += row[i] + '"'
        else:
            remaining_columns += row[i] + '","'
    if remaining_columns == "":
        new_row = '"' + ar1[0] + '"'
    else:
        new_row = '"' + ar1[0] + '","' + remaining_columns
    cidrs.append(new_row)


def csv_to_cidr(f):
    cidrs = []
    mycsv = csv.reader(f)
    for row in mycsv:
        if re.search(r"^[0-9]+$", row[0]) is None:
            continue
        from_ip = no2ip(row[0])
        to_ip = no2ip(row[1])
        # print (from_ip, to_ip)
        total_row = len(row)
        startip = ipaddress.ip_address(from_ip)
        endip = ipaddress.ip_address(to_ip)
        try:
            iprange_to_cidr(startip, endip, total_row, row, cidrs, ipaddress)
        except Exception as e:
            logger.warn("Skipped invalid (range) data record")
            logger.debug(f"Error: {e}")
    return cidrs


if __name__ == "__main__":
    logger.info("Renewing ip2location dataset")
    dl = download_file(url)
    logger.info(f"download from {url} success")
    zf = unzip(dl, fn=file_name)
    logger.info(f"unzipped and extracted {file_name}")
    cidrs = csv_to_cidr(zf)
    logger.info("cidrs parsed")
    filtered_cidrs = filter_location(cidrs, code="IR")
    logger.info(f"filtered for code {code}")
    execs = create_rules(filtered_cidrs, ipset_net)
    logger.info(f"created setup for ipset {ipset_net}")
    os.system(f"ipset create {ipset_net} nethash")
    logger.info(f"check/create ipset network {ipset_net}")
    os.system(f"ipset flush {ipset_net}")
    logger.info(f"flushed {ipset_net} ipset network")
    exec_rules(execs)
    logger.info(f"added all location rules for {ipset_net} ipset network")
