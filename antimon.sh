#!/bin/bash

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_VERSION="1.0.0"

# Флаги
DRY_RUN=false
FORCE=false

# Парсинг аргументов
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --dry-run    Show what would be removed without actually doing it"
            echo "  --force      Skip confirmation prompts"
            echo "  --help       Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Функции вывода
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }

# Проверка root прав
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "This script requires root privileges"
        log_info "Please run: sudo $0"
        exit 1
    fi
}

# Остановка и удаление сервиса
remove_service() {
    local service_name="$1"
    local display_name="$2"
    
    if systemctl is-active --quiet "$service_name" 2>/dev/null; then
        log_info "Found active service: $display_name"
        
        if [ "$DRY_RUN" = true ]; then
            echo "  [DRY-RUN] Would stop and disable: $service_name"
            return
        fi
        
        systemctl stop "$service_name" 2>/dev/null || true
        systemctl disable "$service_name" 2>/dev/null || true
        systemctl mask "$service_name" 2>/dev/null || true
        log_success "Stopped and disabled: $display_name"
    fi
}

# Удаление пакета
remove_package() {
    local package_name="$1"
    local display_name="$2"
    
    # Проверка через dpkg (Debian/Ubuntu)
    if command -v dpkg &> /dev/null && dpkg -l | grep -q "^ii.*$package_name"; then
        log_info "Found package: $display_name"
        
        if [ "$DRY_RUN" = true ]; then
            echo "  [DRY-RUN] Would remove package: $package_name"
            return
        fi
        
        apt-get remove --purge -y "$package_name" 2>/dev/null || true
        log_success "Removed package: $display_name"
        return
    fi
    
    # Проверка через rpm (CentOS/RHEL/Fedora)
    if command -v rpm &> /dev/null && rpm -qa | grep -q "$package_name"; then
        log_info "Found package: $display_name"
        
        if [ "$DRY_RUN" = true ]; then
            echo "  [DRY-RUN] Would remove package: $package_name"
            return
        fi
        
        if command -v yum &> /dev/null; then
            yum remove -y "$package_name" 2>/dev/null || true
        elif command -v dnf &> /dev/null; then
            dnf remove -y "$package_name" 2>/dev/null || true
        fi
        log_success "Removed package: $display_name"
    fi
}

# Удаление процесса
kill_process() {
    local process_name="$1"
    local display_name="$2"
    
    if pgrep -x "$process_name" > /dev/null; then
        log_info "Found running process: $display_name"
        
        if [ "$DRY_RUN" = true ]; then
            echo "  [DRY-RUN] Would kill process: $process_name"
            return
        fi
        
        pkill -9 "$process_name" 2>/dev/null || true
        log_success "Killed process: $display_name"
    fi
}

# Удаление файлов и директорий
remove_files() {
    local path="$1"
    local display_name="$2"
    
    if [ -e "$path" ]; then
        log_info "Found: $display_name ($path)"
        
        if [ "$DRY_RUN" = true ]; then
            echo "  [DRY-RUN] Would remove: $path"
            return
        fi
        
        rm -rf "$path" 2>/dev/null || true
        log_success "Removed: $display_name"
    fi
}

# Удаление QEMU Guest Agent
remove_qemu_ga() {
    log_info "Removing QEMU Guest Agent..."
    remove_service "qemu-guest-agent" "QEMU Guest Agent"
    remove_package "qemu-guest-agent" "QEMU Guest Agent"
    kill_process "qemu-ga" "QEMU GA Process"
    remove_files "/var/run/qemu-ga.pid" "QEMU GA PID"
    remove_files "/usr/bin/qemu-ga" "QEMU GA Binary"
}

# Удаление Cloud-Init
remove_cloud_init() {
    log_info "Removing Cloud-Init..."
    remove_service "cloud-init" "Cloud-Init"
    remove_service "cloud-config" "Cloud-Config"
    remove_service "cloud-final" "Cloud-Final"
    remove_service "cloud-init-local" "Cloud-Init Local"
    remove_package "cloud-init" "Cloud-Init"
    remove_files "/etc/cloud" "Cloud-Init Config"
    remove_files "/var/lib/cloud" "Cloud-Init Data"
}

# Удаление VMware Tools
remove_vmware_tools() {
    log_info "Removing VMware Tools..."
    remove_service "vmtoolsd" "VMware Tools Daemon"
    remove_service "vmware-tools" "VMware Tools"
    kill_process "vmtoolsd" "VMware Tools Process"
    remove_files "/usr/bin/vmware-toolbox-cmd" "VMware Toolbox"
    remove_files "/etc/vmware-tools" "VMware Tools Config"
}

# Удаление VirtualBox Guest Additions
remove_vbox_additions() {
    log_info "Removing VirtualBox Guest Additions..."
    remove_service "vboxadd" "VirtualBox Additions"
    remove_service "vboxadd-service" "VirtualBox Service"
    
    if [ -f "/opt/VBoxGuestAdditions-*/uninstall.sh" ]; then
        if [ "$DRY_RUN" = false ]; then
            /opt/VBoxGuestAdditions-*/uninstall.sh 2>/dev/null || true
        fi
    fi
    
    remove_files "/opt/VBoxGuestAdditions-*" "VirtualBox Guest Additions"
}

# Удаление Hyper-V Integration Services
remove_hyperv() {
    log_info "Removing Hyper-V Integration Services..."
    remove_service "hv-kvp-daemon" "Hyper-V KVP"
    remove_service "hv-vss-daemon" "Hyper-V VSS"
    remove_service "hv-fcopy-daemon" "Hyper-V File Copy"
    remove_package "hyperv-daemons" "Hyper-V Daemons"
}

# Удаление Amazon EC2 агентов
remove_aws_agents() {
    log_info "Removing AWS EC2 agents..."
    remove_service "awslogs" "AWS CloudWatch Logs"
    remove_package "amazon-cloudwatch-agent" "CloudWatch Agent"
    remove_package "amazon-ssm-agent" "SSM Agent"
    remove_files "/opt/aws" "AWS Tools"
    remove_files "/var/log/amazon" "AWS Logs"
}

# Удаление Google Cloud агентов
remove_gcp_agents() {
    log_info "Removing Google Cloud agents..."
    remove_service "google-guest-agent" "Google Guest Agent"
    remove_service "google-osconfig-agent" "Google OS Config"
    remove_package "google-guest-agent" "Google Guest Agent"
    remove_package "google-osconfig-agent" "Google OS Config"
    remove_files "/etc/default/instance_configs.cfg" "GCP Config"
}

# Удаление Azure агентов
remove_azure_agents() {
    log_info "Removing Azure agents..."
    remove_service "walinuxagent" "Azure Linux Agent"
    remove_package "walinuxagent" "Azure Linux Agent"
    remove_package "waagent" "Azure Agent"
    remove_files "/var/lib/waagent" "Azure Agent Data"
}

# Удаление DigitalOcean агентов
remove_digitalocean_agents() {
    log_info "Removing DigitalOcean agents..."
    remove_service "digitalocean-agent" "DigitalOcean Agent"
    remove_package "digitalocean-agent" "DigitalOcean Agent"
    remove_files "/opt/digitalocean" "DigitalOcean Tools"
}

# Удаление Vultr агентов
remove_vultr_agents() {
    log_info "Removing Vultr agents..."
    remove_service "vultr-guest-agent" "Vultr Guest Agent"
    remove_files "/opt/vultr" "Vultr Tools"
}

# Удаление Hetzner Cloud агентов
remove_hetzner_agents() {
    log_info "Removing Hetzner Cloud agents..."
    remove_service "hcloud-init" "Hetzner Cloud Init"
    remove_files "/etc/hcloud" "Hetzner Config"
}

# Удаление Linode агентов
remove_linode_agents() {
    log_info "Removing Linode agents..."
    remove_service "linode-agent" "Linode Agent"
    remove_files "/opt/linode" "Linode Tools"
}

# Удаление телеметрии и мониторинга
remove_telemetry() {
    log_info "Removing telemetry and monitoring..."
    remove_package "landscape-client" "Landscape Client"
    remove_package "landscape-common" "Landscape Common"
    remove_package "ubuntu-advantage-tools" "Ubuntu Advantage"
    remove_service "apport" "Apport Crash Reporter"
    remove_files "/var/crash" "Crash Reports"
}

# Блокировка переустановки через apt
block_reinstall() {
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] Would block package reinstallation"
        return
    fi
    
    log_info "Blocking automatic reinstallation..."
    
    local packages=(
        "qemu-guest-agent"
        "cloud-init"
        "amazon-cloudwatch-agent"
        "amazon-ssm-agent"
        "google-guest-agent"
        "walinuxagent"
        "digitalocean-agent"
        "vultr-guest-agent"
    )
    
    for pkg in "${packages[@]}"; do
        if command -v apt-mark &> /dev/null; then
            apt-mark hold "$pkg" 2>/dev/null || true
        fi
    done
    
    log_success "Blocked automatic reinstallation"
}

# Главная функция
main() {
    echo "=========================================="
    echo "  Anti-Monitoring Tool v${SCRIPT_VERSION}"
    echo "=========================================="
    echo ""
    
    if [ "$DRY_RUN" = true ]; then
        log_warn "DRY-RUN MODE: No changes will be made"
        echo ""
    fi
    
    check_root
    
    if [ "$FORCE" = false ] && [ "$DRY_RUN" = false ]; then
        echo "⚠️  WARNING: This will remove hosting provider monitoring agents!"
        echo "This may:"
        echo "  - Disable console access from hosting panel"
        echo "  - Break automated backups"
        echo "  - Disable monitoring and alerts"
        echo "  - Make password reset impossible"
        echo ""
        read -p "Are you sure you want to continue? (yes/no): " -r
        echo ""
        
        if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
            log_info "Aborted by user"
            exit 0
        fi
    fi
    
    echo "Starting removal process..."
    echo ""
    
    remove_qemu_ga
    remove_cloud_init
    remove_vmware_tools
    remove_vbox_additions
    remove_hyperv
    remove_aws_agents
    remove_gcp_agents
    remove_azure_agents
    remove_digitalocean_agents
    remove_vultr_agents
    remove_hetzner_agents
    remove_linode_agents
    remove_telemetry
    
    if [ "$DRY_RUN" = false ]; then
        block_reinstall
    fi
    
    echo ""
    echo "=========================================="
    if [ "$DRY_RUN" = true ]; then
        log_info "DRY-RUN completed"
    else
        log_success "Anti-monitoring cleanup completed!"
        echo ""
        log_warn "Consider rebooting the server for changes to take full effect"
    fi
    echo "=========================================="
}

main
