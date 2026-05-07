#!/bin/bash

set -euxo pipefail

# Cluster init (idempotent: nur wenn nicht schon initialisiert)
if [ ! -f /etc/kubernetes/admin.conf ]; then
    kubeadm init --pod-network-cidr=10.244.0.0/16 --ignore-preflight-errors=NumCPU --ignore-preflight-errors=Mem
fi

# Kubeconfig für vagrant-User (idempotent)
if [ ! -f /home/vagrant/.kube/config ]; then
    mkdir -p /home/vagrant/.kube
    cp -i /etc/kubernetes/admin.conf /home/vagrant/.kube/config
    chown vagrant:vagrant /home/vagrant/.kube/config
fi

# Fix für root
export KUBECONFIG=/etc/kubernetes/admin.conf

# Flannel CNI (idempotent: apply nur wenn Namespace nicht existiert)
if ! kubectl get namespace kube-flannel &> /dev/null; then
    # Warte, bis der API-Server wirklich bereit ist
    for i in {1..30}; do
      if kubectl get nodes &> /dev/null; then
        echo "API-Server ist bereit für Flannel-Apply."
        break
      fi
      echo "Warte auf API-Server für Flannel-Apply..."
      sleep 2
    done
    kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
fi

# Join-Command speichern (idempotent: erzeugen nur wenn File nicht existiert)
# join-command.sh nur neu erzeugen, wenn sie fehlt oder das Token abgelaufen ist
if [ ! -f /vagrant/join-command.sh ] || ! kubeadm token list | grep -q "$(awk '{print $5}' /vagrant/join-command.sh 2>/dev/null | head -1)"; then
    rm -f /vagrant/join-command.sh
    kubeadm token create --print-join-command > /vagrant/join-command.sh
fi

# Kubeconfig kopieren und anpassen (idempotent)
rm -f /vagrant/kubeconfig
if [ ! -f /vagrant/kubeconfig ]; then
    cp /etc/kubernetes/admin.conf /vagrant/kubeconfig
    # Ersetze alle möglichen Varianten der API-Server-Adresse durch die gewünschte IP
    sed -i 's#https://127.0.0.1:6443#https://<HOME-NETWORK-IP>:6443#g' /vagrant/kubeconfig
    sed -i 's#https://localhost:6443#https://<HOME-NETWORK-IP>:6443#g' /vagrant/kubeconfig
    sed -i 's#https://10.0.2.15:6443#https://<HOME-NETWORK-IP>:6443#g' /vagrant/kubeconfig
fi

# Warte, bis der API-Server erreichbar ist
for i in {1..30}; do
  if curl -k https://127.0.0.1:6443/healthz 2>/dev/null | grep -q ok; then
    echo "API-Server ist bereit."
    break
  fi
  echo "Warte auf API-Server..."
  sleep 5
done