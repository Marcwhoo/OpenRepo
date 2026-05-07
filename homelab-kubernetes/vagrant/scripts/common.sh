#!/bin/bash
export DEBIAN_FRONTEND=noninteractive

set -euxo pipefail

# Statische IP setzen (immer überschreiben, damit Netplan zuverlässig ist)
ADAPTER="enp0s8"
cat <<EOF | tee /etc/netplan/01-netcfg.yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    $ADAPTER:
      dhcp4: no
      addresses: [$NODE_IP/24]
      routes:
        - to: default
          via: <HOME-NETWORK-IP>
      nameservers:
        addresses: [8.8.8.8, 8.8.4.4]
    eth0:
      dhcp4: true
EOF
chmod 600 /etc/netplan/01-netcfg.yaml
netplan apply

# IPv6 deaktivieren (persistent, wenn nicht schon gesetzt)
sysctl -w net.ipv6.conf.all.disable_ipv6=1
sysctl -w net.ipv6.conf.default.disable_ipv6=1
if ! grep -q "net.ipv6.conf.all.disable_ipv6 = 1" /etc/sysctl.conf; then
    echo "net.ipv6.conf.all.disable_ipv6 = 1" >> /etc/sysctl.conf
    echo "net.ipv6.conf.default.disable_ipv6 = 1" >> /etc/sysctl.conf
fi
sysctl -p

# Mirror zu de. wechseln (idempotent)
sed -i 's/us.archive.ubuntu.com/de.archive.ubuntu.com/g' /etc/apt/sources.list

# System-Updates und Basics installieren
apt-get update && apt-get upgrade -y
apt-get install -y ca-certificates curl gnupg lsb-release

# NFS-Client installieren (für Storage-Zugriff)
apt-get install -y nfs-common

# Swap dauerhaft deaktivieren (immer, nicht nur idempotent)
swapoff -a
sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# Docker installieren (check ob schon installiert)
if ! dpkg -l | grep -q docker-ce; then
    # Docker GPG-Key non-interaktiv importieren
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor --batch --yes -o /usr/share/keyrings/docker-archive-keyring.gpg
    # Repository hinzufügen
    echo \ \
      "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io
fi

# Docker-Config (idempotent)
if [ ! -f /etc/docker/daemon.json ]; then
    cat <<EOF | tee /etc/docker/daemon.json
{
  "exec-opts": ["native.cgroupdriver=systemd"]
}
EOF
fi
systemctl daemon-reload
systemctl restart docker
systemctl enable docker

# Containerd fixen (idempotent)
if [ -f /etc/containerd/config.toml ]; then
    rm -f /etc/containerd/config.toml
fi
containerd config default | tee /etc/containerd/config.toml
sed -i 's/            SystemdCgroup = false/            SystemdCgroup = true/' /etc/containerd/config.toml
systemctl restart containerd

# crictl installieren (aktuelle Version, idempotent)
VERSION="v1.32.0"
if ! command -v crictl &> /dev/null; then
    wget https://github.com/kubernetes-sigs/cri-tools/releases/download/$VERSION/crictl-$VERSION-linux-amd64.tar.gz
    tar zxvf crictl-$VERSION-linux-amd64.tar.gz
    mv crictl /usr/local/bin/crictl
    rm crictl-$VERSION-linux-amd64.tar.gz
fi
crictl config --set runtime-endpoint=unix:///run/containerd/containerd.sock

# Kubernetes installieren (aktuelle stabile Version, idempotent)
K8S_VERSION="v1.32"
if ! dpkg -l | grep -q kubelet; then
    # Kubernetes GPG-Key non-interaktiv importieren
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.32/deb/Release.key | sudo gpg --dearmor --batch --yes -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    # Repository hinzufügen
    echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.32/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list > /dev/null
    sudo apt-get update
    sudo apt-get install -y kubelet kubeadm kubectl
fi

# Kernel-Module und sysctl für Kubernetes (idempotent)
if ! grep -q "br_netfilter" /etc/modules-load.d/br_netfilter.conf; then
    echo "br_netfilter" | tee /etc/modules-load.d/br_netfilter.conf
fi
modprobe br_netfilter

if [ ! -f /etc/sysctl.d/k8s.conf ]; then
    cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF
fi
sysctl --system

# (Warte-Loop auf API-Server wurde entfernt)