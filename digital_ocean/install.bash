curl -fsSL https://tailscale.com/install.sh | sh
# allow forwarding
echo 'net.ipv4.ip_forward = 1' | sudo tee -a /etc/sysctl.d/99-tailscale.conf
echo 'net.ipv6.conf.all.forwarding = 1' | sudo tee -a /etc/sysctl.d/99-tailscale.conf
sudo sysctl -p /etc/sysctl.d/99-tailscale.conf
# login tailscale
tailscale up --login-server=$LOGIN_SERVER --authkey $TS_AUTHKEY --webclient --auto-update --advertise-exit-node --accept-routes --accept-dns --advertise-tags=tag:exit-node 
