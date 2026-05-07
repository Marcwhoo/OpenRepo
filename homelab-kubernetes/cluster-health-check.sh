#!/bin/bash

# Kubernetes Cluster Health Check Script fÃ¼r Host-Maschine
# AusfÃ¼hrung: ./cluster-health-check.sh

export KUBECONFIG=vagrant/kubeconfig"

set -e

# Farben fÃ¼r Output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Logging Funktionen
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] âœ“ $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] âš  WARNING: $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] âœ— ERROR: $1${NC}"
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] â„¹ $1${NC}"
}

section() {
    echo -e "${PURPLE}â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•${NC}"
    echo -e "${PURPLE} $1${NC}"
    echo -e "${PURPLE}â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•${NC}"
}

# PrÃ¼fe ob kubectl verfÃ¼gbar ist
check_kubectl() {
    section "KUBECTL VERFÃœGBARKEIT"
    if ! command -v kubectl &> /dev/null; then
        error "kubectl ist nicht installiert oder nicht im PATH"
        info "Installation: https://kubernetes.io/docs/tasks/tools/install-kubectl/"
        return 1
    fi
    
    local version=$(kubectl version --client --short 2>/dev/null | cut -d' ' -f3)
    log "kubectl ist verfÃ¼gbar (Version: $version)"
    return 0
}

# PrÃ¼fe KUBECONFIG
check_kubeconfig() {
    section "KUBECONFIG KONFIGURATION"
    
    if [ ! -f "$KUBECONFIG" ]; then
        error "KUBECONFIG Datei existiert nicht: $KUBECONFIG"
        info "Bitte stelle sicher, dass die Datei vorhanden ist."
        return 1
    fi
    
    log "KUBECONFIG Datei ist verfÃ¼gbar: $KUBECONFIG"
    return 0
}

# PrÃ¼fe Cluster-Erreichbarkeit
check_cluster_connectivity() {
    section "CLUSTER ERREICHBARKEIT"
    
    if ! kubectl cluster-info &> /dev/null; then
        error "Kubernetes Cluster ist nicht erreichbar"
        info "MÃ¶gliche Ursachen:"
        info "  - Cluster ist nicht gestartet"
        info "  - Falsche KUBECONFIG"
        info "  - Netzwerkprobleme"
        return 1
    fi
    
    local cluster_info=$(kubectl cluster-info | head -1)
    log "Cluster ist erreichbar: $cluster_info"
    
    # PrÃ¼fe API-Server Version
    local api_version=$(kubectl version --short 2>/dev/null | grep "Server Version" | cut -d' ' -f3)
    log "API-Server Version: $api_version"
    
    return 0
}

# PrÃ¼fe Node-Status
check_nodes() {
    section "NODE STATUS"
    
    info "PrÃ¼fe alle Nodes..."
    kubectl get nodes -o wide
    
    local total_nodes=$(kubectl get nodes | tail -n +2 | wc -l)
    local ready_nodes=$(kubectl get nodes | grep -c " Ready " || true)
    local not_ready_nodes=$(kubectl get nodes | grep -v " Ready " | tail -n +2 | wc -l)
    
    log "Gesamt Nodes: $total_nodes"
    log "Ready Nodes: $ready_nodes"
    
    if [ "$not_ready_nodes" -gt 0 ]; then
        warn "Nicht-ready Nodes gefunden:"
        kubectl get nodes | grep -v " Ready "
    fi
    
    # PrÃ¼fe spezifische Node-Details
    echo
    info "Detaillierte Node-Informationen:"
    kubectl describe nodes | grep -A 5 -B 5 "Conditions:" || true
    
    if [ "$ready_nodes" -eq "$total_nodes" ] && [ "$total_nodes" -gt 0 ]; then
        log "Alle Nodes sind Ready âœ“"
        return 0
    else
        error "Nicht alle Nodes sind Ready ($ready_nodes/$total_nodes)"
        return 1
    fi
}

# PrÃ¼fe System-Pods
check_system_pods() {
    section "SYSTEM PODS"
    
    info "PrÃ¼fe System-Pods in allen Namespaces..."
    
    # Zeige alle Pods mit Status
    kubectl get pods --all-namespaces -o wide
    
    # ZÃ¤hle Pod-Status
    local total_pods=$(kubectl get pods --all-namespaces | tail -n +2 | wc -l)
    local running_pods=$(kubectl get pods --all-namespaces | grep -c " Running " || true)
    local pending_pods=$(kubectl get pods --all-namespaces | grep -c " Pending " || true)
    local failed_pods=$(kubectl get pods --all-namespaces | grep -c " Failed\|CrashLoopBackOff\|Error " || true)
    
    log "Gesamt Pods: $total_pods"
    log "Running: $running_pods"
    log "Pending: $pending_pods"
    log "Failed: $failed_pods"
    
    # PrÃ¼fe spezifische System-Pods
    echo
    info "PrÃ¼fe kritische System-Pods..."
    
    # CoreDNS
    if kubectl get pods -n kube-system -l k8s-app=kube-dns &> /dev/null; then
        local coredns_ready=$(kubectl get pods -n kube-system -l k8s-app=kube-dns | grep "Running" | wc -l)
        if [ "$coredns_ready" -ge 1 ]; then
            log "CoreDNS: $coredns_ready Pod(s) Running âœ“"
        else
            warn "CoreDNS: Keine Pods Running"
        fi
    else
        warn "CoreDNS nicht gefunden"
    fi
    
    # Flannel/CNI
    if kubectl get pods -n kube-flannel &> /dev/null; then
        local flannel_ready=$(kubectl get pods -n kube-flannel | grep "Running" | wc -l)
        if [ "$flannel_ready" -ge 1 ]; then
            log "Flannel: $flannel_ready Pod(s) Running âœ“"
        else
            warn "Flannel: Keine Pods Running"
        fi
    else
        warn "Flannel Namespace nicht gefunden"
    fi
    
    # Kube-Proxy
    local kube_proxy_ready=$(kubectl get pods -n kube-system -l k8s-app=kube-proxy | grep "Running" | wc -l)
    if [ "$kube_proxy_ready" -ge 1 ]; then
        log "Kube-Proxy: $kube_proxy_ready Pod(s) Running âœ“"
    else
        warn "Kube-Proxy: Keine Pods Running"
    fi
    
    if [ "$failed_pods" -gt 0 ]; then
        warn "Fehlerhafte Pods gefunden:"
        kubectl get pods --all-namespaces | grep -E "Failed|CrashLoopBackOff|Error"
        return 1
    fi
    
    return 0
}

# PrÃ¼fe Services
check_services() {
    section "SERVICES"
    
    info "PrÃ¼fe Services in allen Namespaces..."
    kubectl get services --all-namespaces
    
    # PrÃ¼fe spezifische Services
    echo
    info "PrÃ¼fe kritische Services..."
    
    # Kubernetes API Service
    if kubectl get service kubernetes -n default &> /dev/null; then
        log "Kubernetes API Service: VerfÃ¼gbar âœ“"
    else
        warn "Kubernetes API Service: Nicht gefunden"
    fi
    
    # Dashboard Service (falls installiert)
    if kubectl get service -n kubernetes-dashboard &> /dev/null; then
        log "Dashboard Service: VerfÃ¼gbar âœ“"
        kubectl get service -n kubernetes-dashboard
    else
        info "Dashboard Service: Nicht installiert"
    fi
    
    # Ingress Service (falls installiert)
    if kubectl get service -n ingress-nginx &> /dev/null; then
        log "Ingress Service: VerfÃ¼gbar âœ“"
        kubectl get service -n ingress-nginx
    else
        info "Ingress Service: Nicht installiert"
    fi
    
    return 0
}

# PrÃ¼fe Deployments
check_deployments() {
    section "DEPLOYMENTS"
    
    info "PrÃ¼fe Deployments in allen Namespaces..."
    kubectl get deployments --all-namespaces
    
    # PrÃ¼fe Deployment-Status
    local total_deployments=$(kubectl get deployments --all-namespaces | tail -n +2 | wc -l)
    local available_deployments=$(kubectl get deployments --all-namespaces | awk 'NR>1 && $3==$4 && $4==$5 {count++} END {print count+0}')
    
    log "Gesamt Deployments: $total_deployments"
    log "VerfÃ¼gbare Deployments: $available_deployments"
    
    if [ "$available_deployments" -lt "$total_deployments" ]; then
        warn "Nicht alle Deployments sind verfÃ¼gbar"
        kubectl get deployments --all-namespaces | awk 'NR>1 && ($3!=$4 || $4!=$5) {print $0}'
        return 1
    fi
    
    return 0
}

# PrÃ¼fe Storage
check_storage() {
    section "STORAGE"
    
    info "PrÃ¼fe Storage Classes..."
    kubectl get storageclass
    
    info "PrÃ¼fe Persistent Volumes..."
    kubectl get pv
    
    info "PrÃ¼fe Persistent Volume Claims..."
    kubectl get pvc --all-namespaces
    
    # PrÃ¼fe Local Path Provisioner (falls installiert)
    if kubectl get pods -n local-path-storage &> /dev/null; then
        local local_path_ready=$(kubectl get pods -n local-path-storage | grep "Running" | wc -l)
        if [ "$local_path_ready" -ge 1 ]; then
            log "Local Path Provisioner: $local_path_ready Pod(s) Running âœ“"
        else
            warn "Local Path Provisioner: Keine Pods Running"
        fi
    else
        info "Local Path Provisioner: Nicht installiert"
    fi
    
    return 0
}

# PrÃ¼fe Netzwerk
check_network() {
    section "NETZWERK"
    
    info "PrÃ¼fe Netzwerk-Policies..."
    kubectl get networkpolicies --all-namespaces
    
    info "PrÃ¼fe Endpoints..."
    kubectl get endpoints --all-namespaces
    
    # Einfacher Netzwerk-Test
    echo
    info "FÃ¼hre Netzwerk-Test durch..."
    
    # Erstelle Test-Namespace
    kubectl create namespace cluster-health-test --dry-run=client -o yaml | kubectl apply -f - 2>/dev/null || true
    
    # Test-Pod erstellen
    cat <<EOF | kubectl apply -f - 2>/dev/null || true
apiVersion: v1
kind: Pod
metadata:
  name: network-test-pod
  namespace: cluster-health-test
spec:
  containers:
  - name: busybox
    image: busybox:1.28
    command: ['sleep', '300']
EOF
    
    # Warte auf Pod-Bereitschaft
    if kubectl wait --for=condition=ready pod/network-test-pod -n cluster-health-test --timeout=60s 2>/dev/null; then
        log "Test-Pod ist bereit âœ“"
        
        # DNS-Test
        if kubectl exec -n cluster-health-test network-test-pod -- nslookup kubernetes.default.svc.cluster.local >/dev/null 2>&1; then
            log "DNS-AuflÃ¶sung funktioniert âœ“"
        else
            warn "DNS-AuflÃ¶sung fehlgeschlagen"
        fi
        
        # Ping-Test
        if kubectl exec -n cluster-health-test network-test-pod -- ping -c 1 8.8.8.8 >/dev/null 2>&1; then
            log "Externe Netzwerkverbindung funktioniert âœ“"
        else
            warn "Externe Netzwerkverbindung fehlgeschlagen"
        fi
    else
        warn "Test-Pod konnte nicht erstellt werden"
    fi
    
    # AufrÃ¤umen
    kubectl delete namespace cluster-health-test --force --grace-period=0 2>/dev/null || true
    
    return 0
}

# PrÃ¼fe Events
check_events() {
    section "EVENTS"
    
    info "PrÃ¼fe aktuelle Events..."
    
    # Zeige Events der letzten Stunde
    kubectl get events --all-namespaces --sort-by='.lastTimestamp' | tail -20
    
    # ZÃ¤hle verschiedene Event-Typen
    local error_events=$(kubectl get events --all-namespaces | grep -c "Error\|Failed" || true)
    local warning_events=$(kubectl get events --all-namespaces | grep -c "Warning" || true)
    
    if [ "$error_events" -gt 0 ]; then
        warn "Error Events gefunden: $error_events"
    fi
    
    if [ "$warning_events" -gt 0 ]; then
        warn "Warning Events gefunden: $warning_events"
    fi
    
    if [ "$error_events" -eq 0 ] && [ "$warning_events" -eq 0 ]; then
        log "Keine kritischen Events gefunden âœ“"
    fi
    
    return 0
}

# PrÃ¼fe Ressourcen-Nutzung
check_resources() {
    section "RESSOURCEN NUTZUNG"
    
    info "PrÃ¼fe Node-Ressourcen..."
    kubectl top nodes 2>/dev/null || warn "Metrics-Server nicht verfÃ¼gbar"
    
    info "PrÃ¼fe Pod-Ressourcen..."
    kubectl top pods --all-namespaces 2>/dev/null || warn "Metrics-Server nicht verfÃ¼gbar"
    
    # PrÃ¼fe Node-KapazitÃ¤t
    echo
    info "Node-KapazitÃ¤t:"
    kubectl describe nodes | grep -A 5 "Capacity:" || true
    
    return 0
}

# PrÃ¼fe Sicherheit
check_security() {
    section "SICHERHEIT"
    
    info "PrÃ¼fe RBAC..."
    kubectl get clusterroles --no-headers | wc -l | xargs -I {} log "ClusterRoles: {}"
    kubectl get clusterrolebindings --no-headers | wc -l | xargs -I {} log "ClusterRoleBindings: {}"
    
    info "PrÃ¼fe Service Accounts..."
    kubectl get serviceaccounts --all-namespaces | wc -l | xargs -I {} log "Service Accounts: {}"
    
    # PrÃ¼fe Pod Security Standards (falls verfÃ¼gbar)
    if kubectl get pods --all-namespaces -o jsonpath='{.items[*].metadata.annotations.pod-security\.kubernetes\.io/enforce}' 2>/dev/null | grep -q .; then
        log "Pod Security Standards sind konfiguriert âœ“"
    else
        info "Pod Security Standards nicht konfiguriert"
    fi
    
    return 0
}

# PrÃ¼fe Add-ons
check_addons() {
    section "ADD-ONS"
    
    # Dashboard
    if kubectl get namespace kubernetes-dashboard &> /dev/null; then
        local dashboard_pods=$(kubectl get pods -n kubernetes-dashboard | grep "Running" | wc -l)
        if [ "$dashboard_pods" -ge 1 ]; then
            log "Dashboard: VerfÃ¼gbar ($dashboard_pods Pod(s) Running) âœ“"
        else
            warn "Dashboard: Pods nicht Running"
        fi
    else
        info "Dashboard: Nicht installiert"
    fi
    
    # Ingress Controller
    if kubectl get namespace ingress-nginx &> /dev/null; then
        local ingress_pods=$(kubectl get pods -n ingress-nginx | grep "Running" | wc -l)
        if [ "$ingress_pods" -ge 1 ]; then
            log "Ingress Controller: VerfÃ¼gbar ($ingress_pods Pod(s) Running) âœ“"
        else
            warn "Ingress Controller: Pods nicht Running"
        fi
    else
        info "Ingress Controller: Nicht installiert"
    fi
    
    # Helm (falls verfÃ¼gbar)
    if command -v helm &> /dev/null; then
        log "Helm: VerfÃ¼gbar âœ“"
        helm version --short
    else
        info "Helm: Nicht installiert"
    fi
    
    return 0
}

# Zusammenfassung
print_summary() {
    section "ZUSAMMENFASSUNG"
    
    local total_nodes=$(kubectl get nodes | tail -n +2 | wc -l)
    local ready_nodes=$(kubectl get nodes | grep -c " Ready " || true)
    local total_pods=$(kubectl get pods --all-namespaces | tail -n +2 | wc -l)
    local running_pods=$(kubectl get pods --all-namespaces | grep -c " Running " || true)
    
    echo -e "${CYAN}Cluster Status:${NC}"
    echo -e "  Nodes: $ready_nodes/$total_nodes Ready"
    echo -e "  Pods: $running_pods/$total_pods Running"
    
    if [ "$ready_nodes" -eq "$total_nodes" ] && [ "$running_pods" -eq "$total_pods" ]; then
        echo -e "${GREEN}âœ“ Cluster ist gesund!${NC}"
        return 0
    else
        echo -e "${YELLOW}âš  Cluster hat Probleme${NC}"
        return 1
    fi
}

# Logfile im Skriptverzeichnis
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOGFILE="$SCRIPT_DIR/cluster-health-extended.log"

run_or_vagrant() {
    local cmd="$1"
    local desc="$2"
    echo "--- $desc ---"
    if command -v ${cmd%% *} &>/dev/null; then
        # Fehler abfangen und ins Log schreiben
        eval "$cmd" 2>&1 || echo "(Fehler oder nicht unterstÃ¼tzt)"
        echo "(lokal ausgefÃ¼hrt)"
    else
        pushd "$SCRIPT_DIR/vagrant" >/dev/null 2>&1
        vagrant ssh master -c "$cmd" 2>&1 || echo "(Fehler oder nicht unterstÃ¼tzt)"
        echo "(aus master-VM via vagrant ssh)"
        popd >/dev/null 2>&1
    fi
    echo
}

log_system_and_network_info() {
    {
        echo "==== SYSTEM & NETZWERK INFO: $(date) ===="
        run_or_vagrant "df -h" "Festplattenplatz"
        run_or_vagrant "ip a" "Netzwerkschnittstellen"
        run_or_vagrant "ip route" "Routing-Tabelle"
        run_or_vagrant "ss -tulpen" "Offene Verbindungen (ss)"
        run_or_vagrant "ss -pant" "Verbindungen pro Prozess (ss -pant)"
        run_or_vagrant "ip neigh" "ARP-Tabelle"
        run_or_vagrant "nslookup google.de" "DNS-AuflÃ¶sungstest (google.de)"
        # Ping-Test: unter Windows 'ping -n 2', unter Linux 'ping -c 2'
        if [[ "$(uname -s)" =~ MINGW|MSYS|CYGWIN ]]; then
            run_or_vagrant "ping -n 2 8.8.8.8" "Ping-Test (8.8.8.8)"
        else
            run_or_vagrant "ping -c 2 8.8.8.8" "Ping-Test (8.8.8.8)"
        fi
        # Top-Prozesse IMMER in der VM abfragen
        pushd "$SCRIPT_DIR/vagrant" >/dev/null 2>&1
        vagrant ssh master -c "ps aux --sort=-%cpu | head -10" 2>&1
        echo "(Top Prozesse nach CPU aus master-VM via vagrant ssh)"
        vagrant ssh master -c "ps aux --sort=-%mem | head -10" 2>&1
        echo "(Top Prozesse nach RAM aus master-VM via vagrant ssh)"
        popd >/dev/null 2>&1
        echo "==== ENDE SYSTEM & NETZWERK INFO ===="
        echo
    } >> "$LOGFILE"
}

# ZusÃ¤tzliche Checks fÃ¼r Nodes und Grafana
check_nodes_and_grafana() {
    section "NODE & GRAFANA STATUS"
    echo "--- Kubernetes Nodes ---"
    kubectl get nodes -o wide
    echo
    echo "--- Grafana Pods (Namespace monitoring) ---"
    kubectl get pods -n monitoring -o wide | grep grafana || echo "Kein Grafana-Pod gefunden"
    echo
    echo "--- Grafana Events ---"
    kubectl get events -n monitoring --sort-by=.metadata.creationTimestamp | tail -n 20
    echo
}

# Hauptfunktion
main() {
    log_system_and_network_info
    check_nodes_and_grafana
    echo -e "${PURPLE}â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•${NC}"
    echo -e "${PURPLE}    KUBERNETES CLUSTER HEALTH CHECK${NC}"
    echo -e "${PURPLE}â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•${NC}"
    echo
    
    local exit_code=0
    
    # Grundlegende Checks
    check_kubectl || exit_code=1
    check_kubeconfig || exit_code=1
    check_cluster_connectivity || exit_code=1
    
    if [ $exit_code -eq 0 ]; then
        # Detaillierte Checks
        check_nodes || exit_code=1
        check_system_pods || exit_code=1
        check_services || exit_code=1
        check_deployments || exit_code=1
        check_storage || exit_code=1
        check_network || exit_code=1
        check_events || exit_code=1
        check_resources || exit_code=1
        check_security || exit_code=1
        check_addons || exit_code=1
        
        print_summary || exit_code=1
    fi
    
    echo
    echo -e "${PURPLE}â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•${NC}"
    if [ $exit_code -eq 0 ]; then
        echo -e "${GREEN}âœ“ Health Check abgeschlossen - Cluster ist gesund!${NC}"
    else
        echo -e "${RED}âœ— Health Check abgeschlossen - Probleme gefunden!${NC}"
    fi
    echo -e "${PURPLE}â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•${NC}"
    
    exit $exit_code
}

# Script ausfÃ¼hren
main "$@" 