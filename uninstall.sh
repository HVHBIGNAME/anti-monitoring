#!/bin/bash

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_VERSION="1.0.0"
HIDDEN_DIR="$HOME/.cache/system"
SCRIPT_NAME=".antimon"
SCRIPT_PATH="$HIDDEN_DIR/$SCRIPT_NAME"

# Функция вывода сообщений
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }

# Проверка root прав
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_warn "Some operations may require root privileges"
        return 1
    fi
    return 0
}

# Главная функция
main() {
    echo "=========================================="
    echo "  Anti-Monitoring Uninstaller v${SCRIPT_VERSION}"
    echo "=========================================="
    echo ""
    
    check_root || log_warn "Running without root - some files may not be removable"
    
    log_info "Removing anti-monitoring script..."
    
    if [ -f "$SCRIPT_PATH" ]; then
        rm -f "$SCRIPT_PATH" 2>/dev/null || {
            log_error "Failed to remove: $SCRIPT_PATH"
            log_info "Please run with sudo: sudo $0"
            exit 1
        }
        log_success "Removed: $SCRIPT_PATH"
    else
        log_warn "Script not found: $SCRIPT_PATH"
    fi
    
    # Проверяем, пустая ли директория
    if [ -d "$HIDDEN_DIR" ]; then
        if [ -z "$(ls -A $HIDDEN_DIR 2>/dev/null)" ]; then
            rmdir "$HIDDEN_DIR" 2>/dev/null && log_success "Removed empty directory: $HIDDEN_DIR"
        else
            log_info "Directory not empty, keeping: $HIDDEN_DIR"
        fi
    fi
    
    echo ""
    log_success "Uninstallation complete!"
    echo ""
    log_info "Note: Previously removed monitoring agents will NOT be reinstalled"
    log_info "To restore them, use your hosting provider's control panel"
}

main
