#!/bin/bash
#
# This script is intendent to install both Consul and Nomad servers
# on Ubuntu 16.04 Xenial managed by SystemD
# including DnsMasq for *.service.consul DNS resolving

set -i
export TERM=xterm-256color
export DEBIAN_FRONTEND=noninteractive
export DATACENTER_NAME="example"

echo "Determining local IP address"
LOCAL_IPV4=$(hostname --ip-address)
echo "Using ${LOCAL_IPV4} as IP address for configuration and anouncement"

apt-get update
apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    software-properties-common \
    jq \
    unzip \
    dnsmasq

cat << EODMCF >/etc/dnsmasq.d/10-consul
# Enable forward lookup of the 'consul' domain:
server=/consul/127.0.0.1#8600
EODMCF

systemctl restart dnsmasq

echo "Checking latest Consul and Nomad versions..."
CHECKPOINT_URL="https://checkpoint-api.hashicorp.com/v1/check"
CONSUL_VERSION=$(curl -s "${CHECKPOINT_URL}"/consul | jq .current_version | tr -d '"')
NOMAD_VERSION=$(curl -s "${CHECKPOINT_URL}"/nomad | jq .current_version | tr -d '"')

cd /tmp/

echo "Fetching Consul version ${CONSUL_VERSION} ..."
curl -s https://releases.hashicorp.com/consul/${CONSUL_VERSION}/consul_${CONSUL_VERSION}_linux_amd64.zip -o consul.zip
echo "Installing Consul version ${CONSUL_VERSION} ..."
unzip consul.zip
chmod +x consul
mv consul /usr/local/bin/consul

echo "Fetching Nomad version ${NOMAD_VERSION} ..."
curl -s https://releases.hashicorp.com/nomad/${NOMAD_VERSION}/nomad_${NOMAD_VERSION}_linux_amd64.zip -o nomad.zip
echo "Installing Nomad version ${NOMAD_VERSION} ..."
unzip nomad.zip
chmod +x nomad
mv nomad /usr/local/bin/nomad

echo "Configuring Consul And Nomad"
mkdir -p /var/lib/consul /var/lib/nomad /etc/consul.d /etc/nomad.d

cat << EOCCF >/etc/consul.d/server.hcl
advertise_addr = "${LOCAL_IPV4}"
bootstrap_expect = 3
client_addr =  "0.0.0.0"
data_dir = "/var/lib/consul"
datacenter = "${DATACENTER_NAME}"
enable_syslog = true
log_level = "DEBUG"
recursors =  ["127.0.0.1"]
retry_join = ["provider=aws tag_key=Name tag_value=consul-server"]
server = true
ui = true
EOCCF

cat << EONCF >/etc/nomad.d/server.hcl
bind_addr = "0.0.0.0"

region             = "${DATACENTER_NAME}"
datacenter         = "${DATACENTER_NAME}"
data_dir           = "/var/lib/nomad/"
log_level          = "DEBUG"
leave_on_interrupt = true
leave_on_terminate = true

server {
  enabled = true
}

advertise {
  http = "${LOCAL_IPV4}:4646"
  rpc  = "${LOCAL_IPV4}:4647"
  serf = "${LOCAL_IPV4}:4648"
}
EONCF

cat << EOCSU >/etc/systemd/system/consul.service
[Unit]
Description=consul agent
Requires=network-online.target
After=network-online.target
[Service]
LimitNOFILE=65536
Restart=on-failure
ExecStart=/usr/local/bin/consul agent -config-dir /etc/consul.d
ExecReload=/bin/kill -HUP $MAINPID
KillSignal=SIGINT
Type=notify
[Install]
WantedBy=multi-user.target
EOCSU

cat << EONSU >/etc/systemd/system/nomad.service
[Unit]
Description=nomad agent
Requires=network-online.target
After=network-online.target

[Service]
LimitNOFILE=65536
Restart=on-failure
ExecStart=/usr/local/bin/nomad agent -config /etc/nomad.d
KillSignal=SIGINT
RestartSec=5s

[Install]
WantedBy=multi-user.target
EONSU

systemctl daemon-reload
systemctl start consul
systemctl start nomad
