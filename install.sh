#!/bin/bash

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_VERSION="1.0.0"
HIDDEN_DIR="$HOME/.cache/system"
SCRIPT_NAME=".antimon"
SCRIPT_PATH="$HIDDEN_DIR/$SCRIPT_NAME"
SCRIPT_URL="https://raw.githubusercontent.com/HVHBIGNAME/anti-monitoring/main/antimon.sh"

# Параметры по умолчанию
AUTO_INSTALL_DEPS=false
SILENT=false
FORCE=false

# Парсинг аргументов
while [[ $# -gt 0 ]]; do
    case $1 in
        --auto-deps)
            AUTO_INSTALL_DEPS=true
            shift
            ;;
        --silent)
            SILENT=true
            AUTO_INSTALL_DEPS=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --auto-deps    Automatically install missing dependencies"
            echo "  --silent       Silent installation (implies --auto-deps)"
            echo "  --force        Skip all confirmation prompts"
            echo "  --help         Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Функция вывода сообщений
log_info() { 
    if [ "$SILENT" = false ]; then
        echo -e "${GREEN}[INFO]${NC} $1"
    fi
}
log_warn() { 
    if [ "$SILENT" = false ]; then
        echo -e "${YELLOW}[WARN]${NC} $1"
    fi
}
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_success() { 
    if [ "$SILENT" = false ]; then
        echo -e "${GREEN}[✓]${NC} $1"
    fi
}

# Проверка root прав
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "Root privileges required"
        log_info "Please run: sudo $0"
        exit 1
    fi
}

# Проверка и установка зависимостей
install_dependencies() {
    local missing_deps=()
    
    if ! command -v curl &> /dev/null && ! command -v wget &> /dev/null; then
        missing_deps+=("curl")
    fi
    
    if [ ${#missing_deps[@]} -eq 0 ]; then
        log_info "All dependencies satisfied"
        return 0
    fi
    
    log_warn "Missing dependencies: ${missing_deps[*]}"
    
    # Автоматическая установка или запрос
    if [ "$AUTO_INSTALL_DEPS" = true ]; then
        log_info "Installing dependencies automatically..."
    else
        echo ""
        read -p "Install missing dependencies? (Y/n): " -n 1 -r
        echo
        
        if [[ ! $REPLY =~ ^[Yy]$ ]] && [[ ! -z $REPLY ]]; then
            log_error "Cannot continue without required dependencies"
            exit 1
        fi
    fi
    
    # Установка зависимостей
    if command -v apt-get &> /dev/null; then
        log_info "Installing via apt-get..."
        apt-get update -qq
        for dep in "${missing_deps[@]}"; do
            apt-get install -y "$dep" || {
                log_error "Failed to install $dep"
                exit 1
            }
        done
    elif command -v yum &> /dev/null; then
        log_info "Installing via yum..."
        for dep in "${missing_deps[@]}"; do
            yum install -y "$dep" || {
                log_error "Failed to install $dep"
                exit 1
            }
        done
    elif command -v dnf &> /dev/null; then
        log_info "Installing via dnf..."
        for dep in "${missing_deps[@]}"; do
            dnf install -y "$dep" || {
                log_error "Failed to install $dep"
                exit 1
            }
        done
    elif command -v pacman &> /dev/null; then
        log_info "Installing via pacman..."
        for dep in "${missing_deps[@]}"; do
            pacman -S --noconfirm "$dep" || {
                log_error "Failed to install $dep"
                exit 1
            }
        done
    else
        log_error "Unknown package manager. Please install manually: ${missing_deps[*]}"
        exit 1
    fi
    
    log_success "Dependencies installed successfully"
}

# Создание директории
create_directory() {
    if [ -d "$HIDDEN_DIR" ]; then
        log_info "Directory already exists: $HIDDEN_DIR"
    else
        mkdir -p "$HIDDEN_DIR" 2>/dev/null || {
            log_error "Failed to create directory: $HIDDEN_DIR"
            exit 1
        }
        log_info "Created directory: $HIDDEN_DIR"
    fi
}

# Скачивание скрипта
download_script() {
    log_info "Downloading anti-monitoring script..."
    
    if command -v curl &> /dev/null; then
        if curl -fsSL "$SCRIPT_URL" -o "$SCRIPT_PATH" 2>/dev/null; then
            log_info "Downloaded via curl"
            return 0
        else
            log_warn "curl failed, trying wget..."
        fi
    fi
    
    if command -v wget &> /dev/null; then
        if wget -qO "$SCRIPT_PATH" "$SCRIPT_URL" 2>/dev/null; then
            log_info "Downloaded via wget"
            return 0
        else
            log_error "wget failed"
        fi
    fi
    
    log_error "Failed to download script from $SCRIPT_URL"
    exit 1
}

# Установка прав
set_permissions() {
    chmod +x "$SCRIPT_PATH" 2>/dev/null || {
        log_error "Failed to set execute permission"
        exit 1
    }
    log_info "Set execute permissions"
}

# Проверка установки
verify_installation() {
    if [ ! -f "$SCRIPT_PATH" ]; then
        log_error "Script file not found after installation"
        return 1
    fi
    
    if [ ! -x "$SCRIPT_PATH" ]; then
        log_error "Script is not executable"
        return 1
    fi
    
    log_info "Installation verified"
    return 0
}

# Запуск скрипта сейчас
run_now() {
    if [ "$FORCE" = true ]; then
        log_info "Running anti-monitoring script with --force..."
        bash "$SCRIPT_PATH" --force 2>/dev/null || log_warn "Some agents could not be removed"
        log_success "Anti-monitoring script executed"
    elif [ "$SILENT" = false ]; then
        echo ""
        echo -e "${YELLOW}⚠️  WARNING${NC}"
        echo "This will remove hosting provider monitoring agents!"
        echo ""
        echo "After removal, the following will NOT work:"
        echo "  ❌ Console access from hosting panel"
        echo "  ❌ Password reset from panel"
        echo "  ❌ Automated backups via panel"
        echo "  ❌ Monitoring and alerts from provider"
        echo ""
        read -p "Run anti-monitoring script now? (yes/no): " -r
        echo ""
        
        if [[ $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
            log_info "Running anti-monitoring script..."
            bash "$SCRIPT_PATH"
            log_success "Done"
        else
            log_info "Skipped. You can run it later:"
            echo "  bash $SCRIPT_PATH"
        fi
    fi
}

# Главная функция
main() {
    if [ "$SILENT" = false ]; then
        echo "=========================================="
        echo "  Anti-Monitoring Installer v${SCRIPT_VERSION}"
        echo "=========================================="
        echo ""
    fi
    
    check_root
    
    log_info "Checking dependencies..."
    install_dependencies
    
    log_info "Setting up installation..."
    create_directory
    download_script
    set_permissions
    
    if verify_installation; then
        log_success "Installation successful!"
        
        if [ "$SILENT" = false ]; then
            echo ""
            echo -e "${BLUE}Location:${NC} $SCRIPT_PATH"
            echo -e "${BLUE}Manual run:${NC} bash $SCRIPT_PATH"
            echo ""
        fi
        
        run_now
        
        if [ "$SILENT" = false ]; then
            echo ""
            echo -e "${GREEN}✓ Installation complete!${NC}"
            echo ""
            log_info "To uninstall: curl -fsSL https://raw.githubusercontent.com/HVHBIGNAME/anti-monitoring/main/uninstall.sh | sudo bash"
        fi
    else
        log_error "Installation failed"
        exit 1
    fi
}

main
