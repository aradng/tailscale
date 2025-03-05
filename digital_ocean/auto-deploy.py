from concurrent.futures import ThreadPoolExecutor
import digitalocean
import os
import logging
import subprocess
import time
import re
import ipaddress
import threading
import tenacity

logging.basicConfig(
    level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s"
)


class DigitalOceanProvider:
    manager: digitalocean.Manager
    droplets: list[digitalocean.Droplet]
    regions: list[digitalocean.Region]
    sizes: list[digitalocean.Size]
    ssh_keys: list[digitalocean.SSHKey]
    images: list[digitalocean.Image]

    image: digitalocean.Image
    region: digitalocean.Region
    size: digitalocean.Size

    lock: threading.Lock

    def __init__(
        self,
        token: str,
        image_name: str = "ubuntu-22-04",
        region_slug: str = "fra1",
        name_prefix: str = "do-exit",
    ):
        self.manager = digitalocean.Manager(token=token)
        self.droplets = self.manager.get_all_droplets()
        self.regions = self.manager.get_all_regions()
        self.sizes = self.manager.get_all_sizes()
        self.ssh_keys = self.manager.get_all_sshkeys()
        self.images = self.manager.get_global_images()
        self.image_name = image_name
        self.name_prefix = name_prefix
        self.lock = threading.Lock()

        # Report system state
        logging.info(
            "----------------------------------------------"
            " Current System State "
            "----------------------------------------------"
        )
        logging.info("Droplets: %s", self.droplets)
        logging.info("SSH-Keys: %s", self.ssh_keys)
        logging.info(
            "----------------------------------------------"
            "----------------------"
            "----------------------------------------------"
        )

        if not any([region.slug == region_slug for region in self.regions]):
            raise ValueError(f"Region {region_slug} not found in regions")
        self.region = [r for r in self.regions if r.slug == region_slug][0]

        if not any([image_name in image.slug for image in self.images]):
            raise ValueError(f"Image {self.image_name} not found")
        self.image = [i.id for i in self.images if self.image_name in i.slug][
            0
        ]
        filterd_sizes = {
            size.price_monthly: size
            for size in self.sizes
            if self.region.slug in size.regions and size.memory >= 1e3
        }
        try:
            self.size = filterd_sizes[min(filterd_sizes.keys())]
        except ValueError:
            raise ValueError(f"No size found for region {self.region.slug}")

    @property
    def droplet_name(self) -> str:
        return f"{self.name_prefix}-{self.region.slug}"

    @property
    def selected_image(self) -> digitalocean.Image:
        try:
            return [i.id for i in self.images if self.image_name in i.slug][0]
        except IndexError:
            raise ValueError(f"Image {self.image_name} not found")

    def create_droplet(self) -> digitalocean.Droplet:
        """create new droplet"""
        droplet = digitalocean.Droplet(
            token=self.manager.token,
            name=self.droplet_name,
            region=self.region.slug,
            image=self.selected_image,
            size_slug=self.size.slug,
            ssh_keys=self.ssh_keys,
        )
        droplet.create()
        droplet_create_action = self.manager.get_action(droplet.action_ids[-1])
        logging.info(
            f"Creating Droplet {droplet.name} with ID {droplet.id} in region "
            f"{self.region.name} [ Action ID {droplet_create_action.id} ]"
        )
        # wait for droplet to finish
        logging.info(
            "waiting for droplet to finish (this might take a while) ..."
        )
        droplet_create_action.wait(update_every_seconds=5, repeat=180)
        logging.info(
            f"Droplet {self.image_name} created "
            f"[Action ID {droplet_create_action.id}]"
        )
        logging.info(
            f"Droplet {self.image_name} has ip "
            f"{self.manager.get_droplet(droplet.id).ip_address}"
        )
        droplet = self.manager.get_droplet(droplet.id)
        with self.lock:  # Prevents race conditions when modifying shared list
            self.droplets.append(droplet)
        return droplet

    def delete_droplet(self, droplet: digitalocean.Droplet):
        """delete droplet"""
        droplet.destroy()
        logging.info(
            "waiting for droplet to finish (this might take a while) ..."
        )
        with self.lock:
            self.droplets.remove(droplet)

    @tenacity.retry(
        reraise=True,
        retry=tenacity.retry_if_exception_type(),
        wait=tenacity.wait_fixed(60),
        stop=tenacity.stop_after_attempt(5),
    )
    def setup_droplet(self, droplet: digitalocean.Droplet):
        # wait for droplet to boot
        cmd = (
            "scp -o StrictHostKeyChecking=no ../exit-node/docker-compose.yaml"
            f" .env install.bash root@{droplet.ip_address}:~"
        )

        logging.info(f"shipping files to {droplet.ip_address}")
        subprocess.run(cmd, shell=True, check=True, capture_output=True)
        cmd = (
            f"ssh -o StrictHostKeyChecking=no root@{droplet.ip_address} -t "
            "'env $(cat .env | xargs) bash install.bash && exit 0'"
        )
        logging.info(f"deploying on {droplet.ip_address}")
        subprocess.run(cmd, shell=True, check=True, capture_output=True)

    def get_tailscale_ip(
        self,
        droplet: digitalocean.Droplet,
    ) -> ipaddress.IPv4Address | ipaddress.IPv6Address:
        cmd = (
            f"ssh -o StrictHostKeyChecking=no root@{droplet.ip_address} -t "
            "tailscale ip --4"
        )
        return ipaddress.ip_address(
            subprocess.check_output(cmd, shell=True, text=True).strip()
        )

    @tenacity.retry(
        reraise=True,
        retry=tenacity.retry_if_exception_type(),
        wait=tenacity.wait_fixed(10),
        stop=tenacity.stop_after_attempt(2),
    )
    def check_droplet(
        self,
        droplet: digitalocean.Droplet,
    ) -> bool:
        tailscale_ip = self.get_tailscale_ip(droplet)
        logging.info(f"Checking exit node {droplet.ip_address}:{tailscale_ip}")
        cmd = f"tailscale ping {tailscale_ip}"
               
        pattern = r"(\d+\.\d+\.\d+\.\d+):(\d+)"
        b = subprocess.check_output(cmd, shell=True, text=True).strip()
        logging.debug(b)
        match = re.search(pattern, b)
        if match:
            logging.info(
                f"Direct connection to {droplet.ip_address}:{match.group(1)} "
                "established"
            )
            return True
        logging.error(
            f"Failed to get direct connection for {droplet.ip_address}"
        )
        raise Exception("Failed to ping exit node directly")

    def provision_exit_node(self) -> digitalocean.Droplet:
        droplet = self.create_droplet()
        try:
            self.setup_droplet(droplet)
            if not self.check_droplet(droplet):
                raise Exception("Failed to ping exit node directly")
            logging.info("Droplet is up and running")
            return droplet
        except Exception as e:
            logging.error(f"Droplet rejected due to {type(e).__name__}")
            self.delete_droplet(droplet)
            raise e


def main():
    MAX_DROPLETS = 3
    digi = DigitalOceanProvider(os.getenv("DO_TOKEN"))
    with ThreadPoolExecutor(max_workers=MAX_DROPLETS) as executor:
        futures = []
        if MAX_DROPLETS - len(digi.droplets) <= 0:
            logging.error("droplet limit reached")
            return
        while True:
            if len(futures) < MAX_DROPLETS - len(digi.droplets):
                future = executor.submit(digi.provision_exit_node)
                futures.append(future)
                print("Checking for exit nodes", futures, digi.droplets)
            time.sleep(2)

            if any(f.done() and f.exception() is None for f in futures):
                droplet = [
                    f.result()
                    for f in futures
                    if f.done() and f.exception() is None
                ][0]
                print(f"found {droplet.ip_address} with id {droplet.id}")
                logging.info(
                    "At least one exit node is working. Stopping provisions."
                )

                for f in futures:
                    f.cancel()

                return

            for f in futures:
                if f.done() and f.exception() is not None:
                    futures.remove(f)


if __name__ == "__main__":
    main()
