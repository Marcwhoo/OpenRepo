#!/bin/bash

set -euxo pipefail

# Name des Pods dynamisch ermitteln
echo "Suche aktuellen Pi-hole-Pod..."
POD=$(kubectl get pods -n pihole -l app=pihole -o jsonpath='{.items[0].metadata.name}')
echo "Gefundener Pod: $POD"

# Admin-Passwort setzen
echo "Setze Admin-Passwort..."
kubectl exec -n pihole "$POD" -- pihole setpassword '<PIHOLE-ADMIN-PASSWORD>'
echo "Passwort gesetzt."

# Probes im Deployment patchen
echo "Patche Liveness/Readiness-Probe auf /admin/ ..."
kubectl patch deployment pihole -n pihole --type=json -p='[{"op": "replace", "path": "/spec/template/spec/containers/0/livenessProbe/httpGet/path", "value": "/admin/"},{"op": "replace", "path": "/spec/template/spec/containers/0/readinessProbe/httpGet/path", "value": "/admin/"}]'
echo "Probes gepatcht."

echo "Fertig!" 