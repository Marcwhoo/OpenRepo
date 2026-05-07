#!/bin/bash

set -euxo pipefail

# Nur joinen, wenn die Node noch nicht Teil des Clusters ist
if [ ! -f /etc/kubernetes/kubelet.conf ]; then
  sh /vagrant/join-command.sh
fi