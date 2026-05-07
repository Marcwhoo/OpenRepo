#!/bin/bash

# Kubernetes Cluster Health Check Script

set -e

# Farben für Output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging Funktion
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%d %H:%M:%S')] WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%d %H:%M:%S')] ERROR: $1${NC}"
    exit 1
}

# Setze KUBECONFIG für root
export KUBECONFIG=/etc/kubernetes/admin.conf

# Prüfe ob kubectl verfügbar ist
check_kubectl() {
    if ! command -v kubectl &> /dev/null; then
        error "kubectl ist nicht installiert oder nicht im PATH"
    fi
    log "kubectl ist verfügbar"
}

# Prüfe ob das Cluster läuft
check_cluster_info() {
    if ! kubectl cluster-info &> /dev/null; then
        error "Kubernetes Cluster ist nicht erreichbar"
    fi
    log "Kubernetes Cluster ist erreichbar"
}

# Prüfe Node-Status
check_nodes() {
    log "Prüfe Node-Status..."
    
    local nodes=$(kubectl get nodes -o wide)
    echo "$nodes"
    
    local ready_count=$(kubectl get nodes | grep -c " Ready " || true)
    local total_count=$(kubectl get nodes | tail -n +2 | wc -l)
    
    if [ "$total_count" -ne 3 ]; then
        error "Erwartete 3 Nodes, aber $total_count gefunden"
    fi
    
    if [ "$ready_count" -ne 3 ]; then
        warn "Nicht alle Nodes sind Ready ($ready_count/3). Warte 60 Sekunden und prüfe erneut..."
        sleep 60
        ready_count=$(kubectl get nodes | grep -c " Ready " || true)
        if [ "$ready_count" -ne 3 ]; then
            error "Nur $ready_count/3 Nodes sind Ready"
        fi
    fi
    
    log "Alle 3 Nodes sind Ready"
}

# Prüfe Pods in allen Namespaces (fokussiert auf System-Pods)
check_pods() {
    log "Prüfe Pod-Status (erwarte System-Pods wie Flannel und CoreDNS)..."
    
    local pods=$(kubectl get pods --all-namespaces -o wide)
    echo "$pods"
    
    local not_running=$(kubectl get pods --all-namespaces | grep -v "Running\|Completed\|STATUS" | wc -l)
    
    if [ "$not_running" -gt 0 ]; then
        warn "Es gibt $not_running Pods, die nicht Running oder Completed sind. Warte 120 Sekunden..."
        sleep 120
        not_running=$(kubectl get pods --all-namespaces | grep -v "Running\|Completed\|STATUS" | wc -l)
        if [ "$not_running" -gt 0 ]; then
            error "Es gibt immer noch $not_running fehlerhafte Pods"
        fi
    fi
    
    log "Alle System-Pods sind Running oder Completed"
}

# Prüfe spezifische System-Pods (z.B. Flannel, CoreDNS)
check_system_pods() {
    log "Prüfe System-Pods..."
    
    # Prüfe Flannel
    if ! kubectl get pods -n kube-flannel | grep -q "kube-flannel-ds"; then
        error "Flannel Pods nicht gefunden"
    fi
    
    local flannel_ready=$(kubectl get pods -n kube-flannel | grep "Running" | wc -l)
    if [ "$flannel_ready" -lt 3 ]; then  # Eins pro Node
        error "Nicht alle Flannel Pods sind Running ($flannel_ready/3)"
    fi
    
    # Prüfe CoreDNS
    if ! kubectl get pods -n kube-system | grep -q "coredns"; then
        error "CoreDNS Pods nicht gefunden"
    fi
    
    local coredns_ready=$(kubectl get pods -n kube-system -l k8s-app=kube-dns | grep "Running" | wc -l)
    if [ "$coredns_ready" -lt 2 ]; then  # Typischerweise 2 Replicas
        error "Nicht alle CoreDNS Pods sind Running ($coredns_ready/2)"
    fi
    
    log "System-Pods (Flannel, CoreDNS) sind healthy"
}

# Prüfe Services (Docker, Containerd, Kubelet)
check_services() {
    log "Prüfe System-Services..."
    
    for service in docker containerd kubelet; do
        if ! systemctl is-active --quiet $service; then
            error "$service Service ist nicht aktiv"
        fi
        log "$service Service ist aktiv"
    done
}

# Optional: Prüfe Dashboard, falls installiert
check_dashboard() {
    if kubectl get namespace kubernetes-dashboard &> /dev/null; then
        log "Prüfe Dashboard-Status..."
        
        local dashboard_pod=$(kubectl get pods -n kubernetes-dashboard -l k8s-app=kubernetes-dashboard | grep "Running" | wc -l)
        if [ "$dashboard_pod" -ne 1 ]; then
            warn "Dashboard Pod ist nicht Running. Warte 60 Sekunden..."
            sleep 60
            dashboard_pod=$(kubectl get pods -n kubernetes-dashboard -l k8s-app=kubernetes-dashboard | grep "Running" | wc -l)
            if [ "$dashboard_pod" -ne 1 ]; then
                error "Dashboard Pod ist nicht Running"
            fi
        fi
        
        log "Dashboard ist running"
    else
        log "Dashboard Namespace nicht gefunden - Überspringe Dashboard-Check"
    fi
}

# Prüfe Ingress Controller
check_ingress() {
    if kubectl get namespace ingress-nginx &> /dev/null; then
        log "Prüfe Ingress Controller..."
        
        local ingress_pods=$(kubectl get pods -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx | grep "Running" | wc -l)
        if [ "$ingress_pods" -lt 1 ]; then
            warn "Ingress Controller Pods sind nicht Running. Warte 60 Sekunden..."
            sleep 60
            ingress_pods=$(kubectl get pods -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx | grep "Running" | wc -l)
            if [ "$ingress_pods" -lt 1 ]; then
                error "Ingress Controller Pods sind nicht Running"
            fi
        fi
        
        # Prüfe Ingress Service
        local ingress_svc=$(kubectl get svc -n ingress-nginx ingress-nginx-controller | grep "NodePort" | wc -l)
        if [ "$ingress_svc" -ne 1 ]; then
            warn "Ingress Controller Service ist nicht als NodePort konfiguriert"
        fi
        
        log "Ingress Controller ist running"
        kubectl get svc -n ingress-nginx ingress-nginx-controller
    else
        log "Ingress Controller Namespace nicht gefunden - Überspringe Ingress-Check"
    fi
}

# Einfacher Netzwerk-Test: Erstelle einen temporären Pod und teste DNS/Ping
network_test() {
    log "Führe Netzwerk-Test durch (erstelle temporären Pod)..."
    
    # Erstelle Test-Namespace
    kubectl create namespace test-ns --dry-run=client -o yaml | kubectl apply -f -
    
    # Deployment eines Test-Pods
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: test-pod
  namespace: test-ns
spec:
  containers:
  - name: busybox
    image: busybox:1.28
    command: ['sleep', '3600']
EOF
    
    # Warte bis Pod läuft
    kubectl wait --for=condition=ready pod/test-pod -n test-ns --timeout=120s || error "Test-Pod startet nicht"
    
    # Teste DNS-Auflösung (z.B. kubernetes.default)
    if ! kubectl exec -n test-ns test-pod -- nslookup kubernetes.default >/dev/null 2>&1; then
        error "DNS-Auflösung im Pod fehlgeschlagen"
    fi
    
    log "DNS-Test erfolgreich"
    
    # Aufräumen
    kubectl delete pod test-pod -n test-ns --force --grace-period=0
    kubectl delete namespace test-ns --force --grace-period=0
    log "Netzwerk-Test abgeschlossen und aufgeräumt"
}

# Hauptfunktion
main() {
    log "Starte Kubernetes Cluster Health Check..."
    
    check_kubectl
    check_cluster_info
    check_services
    check_nodes
    check_pods
    check_system_pods
    check_dashboard
    check_ingress
    network_test
    
    log "Alle Checks bestanden! Der Cluster funktioniert korrekt."
}

# Script ausführen
main "$@"