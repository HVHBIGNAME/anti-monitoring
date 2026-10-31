#!/bin/sh
# anti-monitoring: managed guest-agent inventory and service control.
# SPDX-License-Identifier: MIT

set -uf

VERSION=2.0.0
SYSTEM_ROOT=
SCRIPT_FILE=$0
PREFIX=
SOURCE=
REF=
RUN=0
QUIET=0
LEGACY=0
AUTOSTART=
BOOT_SERVICE=anti-monitoring
BOOT_FILE=
BOOT_LINK=
BOOT_BINARY=
COMMAND=
AGENTS=
ALL=0
DRY_RUN=0
YES=0
JSON=0
LANGUAGE=auto
STATE_DIR=/var/lib/anti-monitoring
SNAPSHOT_ID=
SNAPSHOT=
LOCK_HELD=0
PKG_MANAGER=none
RPM_BIN=
INIT_SYSTEM=none
SYSV_TOOL=
RUNIT_DIR=
DISTRO=Linux
INSTALLED=
SNAPS=
SERVICE_NAMES=
FINDINGS=
SCAN_ERRORS=0
CHANGED=0
FAILED=0

# Fields: id | name | native packages | services (without .service) | impact.
# Keep package names specific: never include kernel, networking or shared bundles.
catalog() {
    cat <<'CATALOG'
qemu|QEMU Guest Agent|qemu-guest-agent qemu-ga|qemu-guest-agent qemu-ga|Guest RPC, filesystem freeze, guest information
vmware|VMware Tools|open-vm-tools open-vm-tools-desktop|open-vm-tools vmtoolsd vmware-tools|Guest integration, time sync, graceful shutdown
virtualbox|VirtualBox Guest Additions|virtualbox-guest-utils virtualbox-guest-utils-nox virtualbox-guest-additions virtualbox-guest-tools|vboxservice vboxadd-service vboxadd virtualbox-guest-utils virtualbox-guest-additions|Desktop integration, shared folders, guest services
hyperv|Hyper-V daemons|hyperv-daemons hypervkvpd hypervvssd hypervfcopyd|hv-kvp-daemon hv-vss-daemon hv-fcopy-daemon hypervkvpd hypervvssd hypervfcopyd|Key-value exchange, file copy, backup coordination
cloud-init|Cloud-init|cloud-init|cloud-init-local cloud-init cloud-init-network cloud-config cloud-final cloud-init-hotplugd|Provisioning, network configuration, SSH keys on boot
aws-ssm|AWS Systems Manager|amazon-ssm-agent|amazon-ssm-agent snap.amazon-ssm-agent.amazon-ssm-agent|Session Manager, remote commands, patch management
aws-cloudwatch|AWS CloudWatch|amazon-cloudwatch-agent awslogs|amazon-cloudwatch-agent awslogsd awslogs|Guest metrics and log shipping
gcp-guest|Google Guest Agent|google-guest-agent google-guest-agent-manager|google-guest-agent google-guest-agent-manager|Metadata integration, accounts, guest configuration
gcp-osconfig|Google OS Config|google-osconfig-agent|google-osconfig-agent|OS inventory and patch management
gcp-ops|Google Ops Agent|google-cloud-ops-agent|google-cloud-ops-agent google-cloud-ops-agent-fluent-bit google-cloud-ops-agent-opentelemetry-collector|Guest metrics, logs and traces
azure|Azure Linux Agent|walinuxagent WALinuxAgent waagent|walinuxagent waagent|VM extensions, provisioning, password reset
do-metrics|DigitalOcean metrics|do-agent digitalocean-agent|do-agent digitalocean-agent|Guest metrics and alerts
do-droplet|DigitalOcean Droplet Agent|droplet-agent|droplet-agent|Droplet Console guest integration
vultr|Vultr Guest Agent|vultr-guest-agent|vultr-guest-agent|Provider guest integration
landscape|Landscape Client|landscape-client|landscape-client|Remote inventory and system management
apport|Apport|apport|apport|Crash reporting
CATALOG
}

say() {
    if [ "$LANGUAGE" = ru ]; then printf '%s\n' "$2"; else printf '%s\n' "$1"; fi
}

error() { printf '[!] %s\n' "$*" >&2; }

usage() {
    say 'Anti-Monitoring — manage Linux guest agents' 'Anti-Monitoring — управление гостевыми агентами Linux'
    if [ "$LANGUAGE" = ru ]; then
        cat <<'USAGE'

  sh antimon.sh [действие] [параметры]    После установки: antimon [флаги]

  --install       Установить команду antimon (без изменения агентов)
  --uninstall     Удалить команду и её правило автостарта; сохранить снимки
  --scan          Проверить установленные агенты (без root)
  --list          Показать ID агентов
  --disable       Отключить выбранные службы с записью снимка
  --remove        Отключить службы и удалить выбранные пакеты
  --restore       Восстановить состояния служб из снимка
  --menu          Открыть меню

  --agents IDS    ID через запятую, например qemu,aws-ssm
  --all           Выбрать весь каталог
  --dry-run       Только показать план, без изменений
  --yes           Подтвердить действие без вопросов (--force — синоним)
  --autostart     Отключать выбранные агенты при загрузке Linux
  --no-autostart  Убрать автостарт; агенты остаются в текущем состоянии
  --run           Открыть меню сразу после --install
  --prefix DIR    Каталог установки (root: /usr/local; пользователь: ~/.local)
  --source DIR    Установка из checkout с проверкой SHA-256
  --ref REF       Скачать конкретный Git ref при --install
  --snapshot ID   Снимок для --restore (по умолчанию последний disable)
  --state-dir DIR Каталог снимков (по умолчанию /var/lib/anti-monitoring)
  --json          JSON-вывод для --scan
  --lang ru|en    Язык интерфейса (по умолчанию определяется автоматически)
  --quiet         Короткий вывод установки (--silent — синоним)
  --legacy        Вместе с --uninstall удалить старый ~/.cache/system/.antimon
  --help, -h      Эта справка
  --version, -V   Версия

  antimon --disable --agents qemu --dry-run
  sudo antimon --autostart --agents qemu --yes
  sudo antimon --no-autostart

Автостарт выключен по умолчанию. --install --autostart можно объединить.
Автостарт выполняет --disable при загрузке, а не удаление пакетов.
Без флагов: меню в терминале, проверка при перенаправленном вводе.
USAGE
    else
        cat <<'USAGE'

  sh antimon.sh [action] [options]       After installation: antimon [flags]

  --install       Install antimon without changing guest agents
  --uninstall     Remove antimon and its boot entry; keep recovery snapshots
  --scan          Read-only inventory (no root required)
  --list          List agent IDs
  --disable       Stop selected services and save recovery state
  --remove        Disable services and remove selected packages
  --restore       Restore recorded service states
  --menu          Open the interactive menu

  --agents IDS    Comma-separated IDs, e.g. qemu,aws-ssm
  --all           Select the entire catalog
  --dry-run       Preview only; no writes
  --yes           Confirm without prompting (--force is an alias)
  --autostart     Disable selected agents at Linux boot (off by default)
  --no-autostart  Remove the boot entry; leave guest agents as they are
  --run           Open the menu immediately after --install
  --prefix DIR    Install prefix (root: /usr/local; user: ~/.local)
  --source DIR    Install from a checkout with SHA-256 verification
  --ref REF       Download a specific Git ref with --install
  --snapshot ID   Snapshot for --restore (latest disable by default)
  --state-dir DIR Recovery directory (/var/lib/anti-monitoring)
  --json          Machine-readable --scan output
  --lang en|ru    Interface language (auto-detected by default)
  --quiet         Less installer output (--silent is an alias)
  --legacy        With --uninstall, also remove ~/.cache/system/.antimon
  --help, -h      Show this help
  --version, -V   Show version

  antimon --disable --agents qemu --dry-run
  sudo antimon --autostart --agents qemu --yes
  sudo antimon --no-autostart

Combine --install --autostart to install and register boot execution.
Autostart runs --disable at boot; it never removes packages.
No flags: menu on a terminal; scan with redirected input.
USAGE
    fi
}

parse_args() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --scan|--list|--disable|--remove|--restore|--menu|--install|--uninstall|scan|status|list|plan|disable|remove|restore|menu)
                [ -z "$COMMAND" ] || { error 'Specify one command.'; return 2; }
                COMMAND=${1#--}
                ;;
            --agents|--state-dir|--snapshot|--lang|--prefix|--source|--ref)
                if [ "$#" -lt 2 ] || [ -z "$2" ]; then
                    error "Missing value: $1"
                    return 2
                fi
                case "$1" in
                    --agents) AGENTS=$2 ;;
                    --state-dir) STATE_DIR=$2 ;;
                    --snapshot) SNAPSHOT_ID=$2 ;;
                    --lang) LANGUAGE=$2 ;;
                    --prefix) PREFIX=$2 ;;
                    --source) SOURCE=$2 ;;
                    --ref) REF=$2 ;;
                esac
                shift
                ;;
            --all) ALL=1 ;;
            --dry-run) DRY_RUN=1 ;;
            --yes|--force) YES=1 ;;
            --json) JSON=1 ;;
            --autostart|--no-autostart)
                [ -z "$AUTOSTART" ] || { error 'Choose --autostart or --no-autostart once.'; return 2; }
                AUTOSTART=$1
                ;;
            --run) RUN=1 ;;
            --quiet|--silent) QUIET=1 ;;
            --legacy) LEGACY=1 ;;
            --no-color) ;;
            --help|-h) COMMAND=help ;;
            --version|-V) COMMAND=version ;;
            *) error "Unknown argument: $1"; return 2 ;;
        esac
        shift
    done
    case "$LANGUAGE" in
        auto) case "${LC_ALL:-${LC_MESSAGES:-${LANG:-en}}}" in ru*) LANGUAGE=ru ;; *) LANGUAGE=en ;; esac ;;
        en|ru) ;;
        *) error 'Language must be en, ru or auto.'; return 2 ;;
    esac
    LC_ALL=C
    export LC_ALL
    case "$COMMAND" in help|version) return 0 ;; esac
    [ "$ALL" -eq 0 ] || [ -z "$AGENTS" ] || { error '--all and --agents are mutually exclusive.'; return 2; }
    if [ -z "$COMMAND" ]; then
        if [ -n "$AUTOSTART" ]; then COMMAND=autostart
        elif [ "$DRY_RUN" -eq 1 ]; then COMMAND=plan
        elif [ "$JSON" -eq 0 ] && [ -t 0 ] && [ -t 1 ]; then COMMAND=menu
        else COMMAND=scan
        fi
    fi
    [ "$COMMAND" != status ] || COMMAND=scan
    if [ "$COMMAND" = plan ]; then
        COMMAND=disable
        DRY_RUN=1
        [ -n "$AGENTS" ] || ALL=1
    fi
    [ "$JSON" -eq 0 ] || [ "$COMMAND" = scan ] || { error '--json requires scan.'; return 2; }
    case "$COMMAND" in
        disable|remove)
            [ "$ALL" -eq 1 ] || [ -n "$AGENTS" ] || { error 'Select --agents IDS or --all.'; return 2; }
            ;;
        restore)
            if [ "$ALL" -ne 0 ] || [ -n "$AGENTS" ]; then
                error 'restore uses a snapshot, not --agents/--all.'
                return 2
            fi
            ;;
    esac
    [ -z "$SNAPSHOT_ID" ] || [ "$COMMAND" = restore ] || { error '--snapshot requires restore.'; return 2; }
    if [ -n "$AUTOSTART" ]; then
        case "$COMMAND:$AUTOSTART" in install:--autostart|autostart:*) ;;
            *) error 'Use --autostart alone or with --install; --no-autostart is a separate action.'; return 2 ;;
        esac
        if [ "$AUTOSTART" = --autostart ]; then
            [ "$ALL" -eq 1 ] || [ -n "$AGENTS" ] || { error '--autostart requires --agents IDS or --all.'; return 2; }
        elif [ "$ALL" -eq 1 ] || [ -n "$AGENTS" ]; then
            error '--no-autostart removes the complete boot entry; omit agent selection.'
            return 2
        fi
    fi
    if [ "$COMMAND" != install ] && { [ -n "$SOURCE" ] || [ -n "$REF" ] || [ "$RUN" -eq 1 ]; }; then
        error '--source, --ref and --run require --install.'; return 2
    fi
    if [ "$LEGACY" -eq 1 ] && [ "$COMMAND" != uninstall ]; then error '--legacy requires --uninstall.'; return 2; fi
    if [ "$COMMAND" = uninstall ] && { [ "$ALL" -eq 1 ] || [ -n "$AGENTS" ]; }; then
        error '--uninstall removes the tool; use --remove for agents.'; return 2
    fi
    if [ "$COMMAND" = install ] && [ -z "$AUTOSTART" ] && { [ "$ALL" -eq 1 ] || [ -n "$AGENTS" ]; }; then
        error '--install accepts agent selection only with --autostart.'; return 2
    fi
    case "$STATE_DIR" in
        /|*/../*|*/..|*/./*|*/.) error 'Use a dedicated, absolute state directory.'; return 2 ;;
        /*) STATE_DIR=${STATE_DIR%/} ;;
        *) error '--state-dir must be absolute.'; return 2 ;;
    esac
    validate_agents
}

known_agent() { catalog | awk -F '|' -v id="$1" '$1 == id { found=1 } END { exit !found }'; }

validate_agents() (
    [ -n "$AGENTS" ] || exit 0
    case "$AGENTS" in ,*|*,|*,,*|*[!a-z0-9,-]*) error 'Invalid agent list.'; exit 2 ;; esac
    IFS=,
    for entry in $AGENTS; do
        known_agent "$entry" || { error "Unknown agent: $entry (see antimon --list)"; exit 2; }
    done
)

selected() {
    [ "$ALL" -eq 1 ] || [ -z "$AGENTS" ] && return 0
    case ",$AGENTS," in *",$1,"*) return 0 ;; *) return 1 ;; esac
}

has() { command -v "$1" >/dev/null 2>&1; }

detect_platform() {
    [ "$(uname -s)" = Linux ] || { error 'Linux is required. Use --help or list on other operating systems.'; return 2; }
    platform_id=
    platform_like=
    if [ -r "$SYSTEM_ROOT/etc/os-release" ]; then
        while IFS='=' read -r platform_key platform_value; do
            platform_value=${platform_value#\"}
            platform_value=${platform_value%\"}
            platform_value=${platform_value#\'}
            platform_value=${platform_value%\'}
            case "$platform_key" in
                ID) platform_id=$platform_value ;;
                ID_LIKE) platform_like=$platform_value ;;
                PRETTY_NAME) DISTRO=$platform_value ;;
            esac
        done < "$SYSTEM_ROOT/etc/os-release"
    fi
    PKG_MANAGER=none
    case " $platform_id $platform_like " in
        *' debian '*|*' ubuntu '*) has apt-get && has dpkg-query && PKG_MANAGER=apt ;;
        *' opensuse '*|*' opensuse-leap '*|*' opensuse-tumbleweed '*|*' suse '*|*' sles '*) native_rpm_available && has zypper && PKG_MANAGER=zypper ;;
        *' fedora '*|*' rhel '*|*' centos '*) detect_rpm_manager ;;
        *' arch '*|*' manjaro '*) has pacman && PKG_MANAGER=pacman ;;
        *' alpine '*) has apk && PKG_MANAGER=apk ;;
        *' void '*) has xbps-query && has xbps-remove && PKG_MANAGER=xbps ;;
        *' nixos '*|*' guix '*|*' gentoo '*) PKG_MANAGER=manual ;;
    esac
    if [ "$PKG_MANAGER" = none ]; then
        if has apt-get && has dpkg-query; then PKG_MANAGER=apt
        elif native_rpm_available; then detect_rpm_manager
        elif has pacman; then PKG_MANAGER=pacman
        elif has apk; then PKG_MANAGER=apk
        elif has xbps-query && has xbps-remove; then PKG_MANAGER=xbps
        fi
    fi
    # An immutable host's deployment manager owns its packages, even if rpm exists.
    if has rpm-ostree || [ -e "$SYSTEM_ROOT/run/ostree-booted" ]; then PKG_MANAGER=manual; fi
    detect_init
}

locate_rpm() (
    # An explicit executable path bypasses standalone ash's limited rpm applet,
    # including builds where the env applet also prefers internal commands.
    IFS=:
    for rpm_dir in ${PATH:-}; do
        [ -n "$rpm_dir" ] || rpm_dir=.
        if [ -f "$rpm_dir/rpm" ] && [ -x "$rpm_dir/rpm" ] && "$rpm_dir/rpm" --version >/dev/null 2>&1; then
            printf '%s\n' "$rpm_dir/rpm"
            exit 0
        fi
    done
    exit 1
)

native_rpm_available() {
    [ -z "$RPM_BIN" ] || return 0
    has rpm || return 1
    RPM_BIN=$(locate_rpm)
}

detect_rpm_manager() {
    if ! native_rpm_available; then return 0
    elif has dnf; then PKG_MANAGER=dnf
    elif has dnf5; then PKG_MANAGER=dnf5
    elif has yum; then PKG_MANAGER=yum
    elif has zypper; then PKG_MANAGER=zypper
    else PKG_MANAGER=rpm
    fi
}

detect_init() {
    INIT_SYSTEM=none
    init_process=unknown
    if [ -r "$SYSTEM_ROOT/proc/1/comm" ]; then IFS= read -r init_process < "$SYSTEM_ROOT/proc/1/comm"; fi
    if [ "$init_process" = systemd ] && has systemctl && systemctl --system show --property=Version >/dev/null 2>&1; then
        INIT_SYSTEM=systemd
    elif { [ "$init_process" = init ] || [ "$init_process" = openrc-init ]; } && has rc-service && has rc-update && has rc-status && rc-status --runlevel >/dev/null 2>&1; then
        INIT_SYSTEM=openrc
    elif { [ "$init_process" = runit ] || [ "$init_process" = runit-init ]; } && has sv && { [ -d "$SYSTEM_ROOT/var/service" ] || [ -d "$SYSTEM_ROOT/etc/service" ]; }; then
        INIT_SYSTEM=runit
        if [ -d "$SYSTEM_ROOT/var/service" ]; then RUNIT_DIR=$SYSTEM_ROOT/var/service; else RUNIT_DIR=$SYSTEM_ROOT/etc/service; fi
    elif [ "$init_process" = init ] && has service && [ -d "$SYSTEM_ROOT/etc/init.d" ]; then
        if has update-rc.d; then INIT_SYSTEM=sysv; SYSV_TOOL=update-rc.d
        elif has chkconfig; then INIT_SYSTEM=sysv; SYSV_TOOL=chkconfig
        fi
    fi
}

inventory() {
    case "$PKG_MANAGER" in
        apt) dpkg-query -W '-f=${binary:Package}|${db:Status-Status}\n' ;;
        dnf|dnf5|yum|zypper|rpm) "$RPM_BIN" -qa --queryformat '%{NAME}\n' ;;
        pacman) pacman -Qq ;;
        apk) apk info ;;
        xbps) xbps-query -l ;;
        *) return 0 ;;
    esac
}

load_inventory() {
    INSTALLED=
    if inventory_output=$(inventory); then
        case "$PKG_MANAGER" in
            apt) INSTALLED=$(printf '%s\n' "$inventory_output" | awk -F '|' '$2 == "installed" { print $1 }') ;;
            xbps) INSTALLED=$(printf '%s\n' "$inventory_output" | awk '$1 == "ii" { sub(/-[^-]+$/, "", $2); print $2 }') ;;
            *) INSTALLED=$inventory_output ;;
        esac
    else
        error "Cannot read package inventory ($PKG_MANAGER)."
        SCAN_ERRORS=$((SCAN_ERRORS + 1))
    fi
    SNAPS=
    if has snap; then
        if snap_output=$(snap list 2>&1); then
            SNAPS=$(printf '%s\n' "$snap_output" | awk 'NR > 1 { print $1 }')
        else
            case "$snap_output" in
                *'No snaps are installed yet.'*) ;;
                *) error "$snap_output"; SCAN_ERRORS=$((SCAN_ERRORS + 1)) ;;
            esac
        fi
    fi
}

native_matches() {
    printf '%s\n' "$INSTALLED" | awk -v name="$1" '{ base=$0; sub(/:[^:]+$/, "", base); if (base == name) print $0 }'
}

snap_present() {
    printf '%s\n' "$SNAPS" | awk -v name="$1" '$0 == name { found=1 } END { exit !found }'
}

load_service_names() {
    SERVICE_NAMES=
    case "$INIT_SYSTEM" in
        systemd)
            if service_files=$(systemctl list-unit-files --type=service --no-legend --no-pager) && \
                service_loaded=$(systemctl list-units --all --type=service --no-legend --no-pager --plain); then
                SERVICE_NAMES=$(printf '%s\n%s\n' "$service_files" "$service_loaded" | awk '$1 ~ /\.service$/ { sub(/\.service$/, "", $1); print $1 }')
            else
                error 'Cannot enumerate systemd services.'
                SCAN_ERRORS=$((SCAN_ERRORS + 1))
            fi
            ;;
        openrc)
            if SERVICE_NAMES=$(rc-service --list); then :
            else error 'Cannot enumerate OpenRC services.'; SCAN_ERRORS=$((SCAN_ERRORS + 1))
            fi
            ;;
    esac
}

service_candidate() {
    case "$INIT_SYSTEM" in
        systemd|openrc) printf '%s\n' "$SERVICE_NAMES" | awk -v name="$1" '$0 == name { found=1 } END { exit !found }' ;;
        *) return 0 ;;
    esac
}

sysv_levels() (
    if [ "$SYSV_TOOL" = chkconfig ]; then
        chkconfig --list "$1" 2>/dev/null | awk '{ for (i=2; i<=NF; i++) if ($i ~ /^[0-6]:on$/) printf "%s ", substr($i,1,1) }'
    else
        set +f
        for link in "$SYSTEM_ROOT"/etc/rc[0-6S].d/S[0-9][0-9]"$1"; do
            [ -L "$link" ] || continue
            level=${link#"$SYSTEM_ROOT/etc/rc"}
            printf '%s ' "${level%%.*}"
        done
    fi
)

# Output: canonical-name|startup-state|active/inactive. Exit 1 means absent.
service_state() (
    name=$1
    active=inactive
    startup=-
    case "$INIT_SYSTEM" in
        systemd)
            probe_status=0
            data=$(systemctl show --property=Id --property=LoadState --property=UnitFileState --property=ActiveState "$name.service" 2>/dev/null) || probe_status=$?
            load=
            unit_state=
            while IFS='=' read -r key value; do
                case "$key" in
                    Id) name=${value%.service} ;;
                    LoadState) load=$value ;;
                    UnitFileState) startup=${value:--} ;;
                    ActiveState) unit_state=$value ;;
                esac
            done <<EOF
$data
EOF
            case "$load" in not-found) exit 1 ;; loaded|masked) ;; *) exit 2 ;; esac
            [ "$probe_status" -eq 0 ] || exit 2
            case "$unit_state" in active|activating|reloading|deactivating) active=active ;; inactive|failed) ;; *) exit 2 ;; esac
            ;;
        openrc)
            rc-service --exists "$name" >/dev/null 2>&1 || exit 1
            levels=$(rc-update show -v 2>/dev/null) || exit 2
            startup=$(printf '%s\n' "$levels" | awk -v name="$name" '$1 == name { for (i=3; i<=NF; i++) printf "%s ", $i }')
            [ -n "$startup" ] || startup=-
            if rc-service "$name" status >/dev/null 2>&1; then active=active; fi
            ;;
        runit)
            [ -d "$RUNIT_DIR/$name" ] || exit 1
            startup=enabled
            [ ! -e "$RUNIT_DIR/$name/down" ] || startup=disabled
            data=$(sv status "$RUNIT_DIR/$name" 2>/dev/null)
            case "$data" in run:*) active=active ;; down:*) ;; *) exit 2 ;; esac
            ;;
        sysv)
            [ -x "$SYSTEM_ROOT/etc/init.d/$name" ] || exit 1
            startup=$(sysv_levels "$name")
            [ -n "$startup" ] || startup=-
            if service "$name" status >/dev/null 2>&1; then active=active; fi
            ;;
        *) exit 1 ;;
    esac
    printf '%s|%s|%s\n' "$name" "$startup" "$active"
)

add_finding() {
    # Aliases can resolve to the same systemd unit; operate on it only once.
    if printf '%s\n' "$FINDINGS" | awk -F '|' -v kind="$1" -v name="$3" '$1 == kind && $3 == name { found=1 } END { exit !found }'; then
        return 0
    fi
    FINDINGS="${FINDINGS}$1|$2|$3|$4|$5
"
}

manual_virtualbox() (
    set +f
    for directory in "$SYSTEM_ROOT"/opt/VBoxGuestAdditions-*; do
        [ ! -d "$directory" ] || printf '%s\n' "$directory"
    done
)

scan() {
    FINDINGS=
    SCAN_ERRORS=0
    load_inventory
    load_service_names
    while IFS='|' read -r scan_id _ scan_packages scan_services _; do
        selected "$scan_id" || continue
        for scan_package in $scan_packages; do
            for scan_match in $(native_matches "$scan_package"); do
                add_finding package "$scan_id" "$scan_match" installed -
            done
        done
        if [ "$scan_id" = aws-ssm ] && snap_present amazon-ssm-agent; then
            add_finding snap "$scan_id" amazon-ssm-agent installed -
        fi
        for scan_service in $scan_services; do
            service_candidate "$scan_service" || continue
            if scan_state=$(service_state "$scan_service"); then
                scan_name=${scan_state%%|*}
                scan_state=${scan_state#*|}
                add_finding service "$scan_id" "$scan_name" "${scan_state%%|*}" "${scan_state#*|}"
            else
                scan_status=$?
                if [ "$scan_status" -ne 1 ]; then
                    error "Cannot inspect service: $scan_service"
                    SCAN_ERRORS=$((SCAN_ERRORS + 1))
                fi
            fi
        done
        if [ "$scan_id" = virtualbox ]; then
            while IFS= read -r scan_path; do
                [ -z "$scan_path" ] || add_finding manual "$scan_id" "$scan_path" unmanaged -
            done <<EOF
$(manual_virtualbox)
EOF
        fi
    done <<EOF
$(catalog)
EOF
}

finding_count() {
    printf '%s\n' "$FINDINGS" | awk -F '|' -v kind="$1" -v id="${2-}" '$1 == kind && (id == "" || $2 == id) { n++ } END { print n+0 }'
}

json_string() {
    printf '%s' "$1" | awk '
        BEGIN { printf "\""; for (i=1; i<32; i++) escapes[sprintf("%c",i)]=sprintf("\\u%04x",i) }
        NR > 1 { printf "\\n" }
        { for (i=1; i<=length($0); i++) {
            c=substr($0,i,1)
            if (c == "\\") printf "\\\\"
            else if (c == "\"") printf "\\\""
            else if (c in escapes) printf "%s", escapes[c]
            else printf "%s", c
        } }
        END { printf "\"" }'
}

scan_complete() {
    [ "$SCAN_ERRORS" -eq 0 ] && [ "$INIT_SYSTEM" != none ] && [ "$PKG_MANAGER" != none ] && [ "$PKG_MANAGER" != manual ]
}

print_json() {
    printf '{"schema_version":1,"version":"%s","system":{"distribution":' "$VERSION"
    json_string "$DISTRO"
    printf ',"package_manager":"%s","init_system":"%s"},"complete":' "$PKG_MANAGER" "$INIT_SYSTEM"
    if scan_complete; then printf true; else printf false; fi
    printf ',"agents":['
    json_separator=
    while IFS='|' read -r json_id json_label _ _ json_impact; do
        selected "$json_id" || continue
        printf '%s{"id":"%s","name":' "$json_separator" "$json_id"
        json_string "$json_label"
        printf ',"impact":'
        json_string "$json_impact"
        printf ',"findings":['
        json_finding_separator=
        while IFS='|' read -r json_kind json_agent json_name json_startup json_active; do
            [ "$json_agent" = "$json_id" ] || continue
            printf '%s{"kind":"%s","name":' "$json_finding_separator" "$json_kind"
            json_string "$json_name"
            printf ',"startup":'
            json_string "$json_startup"
            printf ',"active":'
            json_string "$json_active"
            printf '}'
            json_finding_separator=,
        done <<EOF
$FINDINGS
EOF
        printf ']}'
        json_separator=,
    done <<EOF
$(catalog)
EOF
    printf '],"counts":{"packages":%s,"snaps":%s,"services":%s,"manual":%s},"probe_errors":%s}\n' \
        "$(finding_count package)" "$(finding_count snap)" "$(finding_count service)" "$(finding_count manual)" "$SCAN_ERRORS"
}

print_scan() {
    printf '\nANTI-MONITORING / %s\n%s\n' "$VERSION" "$DISTRO"
    printf 'packages: %s  |  services: %s\n\n' "$PKG_MANAGER" "$INIT_SYSTEM"
    while IFS='|' read -r print_id print_label _ _ print_impact; do
        selected "$print_id" || continue
        printf '%-18s %s\n' "$print_id" "$print_label"
        print_found=0
        while IFS='|' read -r print_kind print_agent print_name print_startup print_active; do
            [ "$print_agent" = "$print_id" ] || continue
            printf '  %-8s %-48s %s %s\n' "$print_kind" "$print_name" "$print_startup" "$print_active"
            print_found=1
        done <<EOF
$FINDINGS
EOF
        if [ "$print_found" -eq 0 ]; then
            say '  No matches in available backends.' '  В доступных источниках совпадений нет.'
        elif [ "$COMMAND" != scan ]; then
            printf '  Impact: %s\n' "$print_impact"
        fi
    done <<EOF
$(catalog)
EOF
    printf '\npackages: %s  |  snaps: %s  |  services: %s  |  manual: %s\n' \
        "$(finding_count package)" "$(finding_count snap)" "$(finding_count service)" "$(finding_count manual)"
    if ! scan_complete; then
        say 'Partial inventory: a backend is unavailable or a probe failed. Missing entries do not prove absence.' \
            'Неполная проверка: источник недоступен или произошла ошибка. Отсутствие совпадений не доказывает отсутствие агента.'
    fi
}

require_root() {
    [ "$(id -u)" -eq 0 ] || {
        say 'This action requires root. Run it with sudo (scan/plan do not need sudo).' \
            'Для этого действия нужен root. Используй sudo (scan/plan работают без sudo).' >&2
        return 2
    }
}

confirm() {
    [ "$YES" -eq 0 ] || return 0
    # /dev/tty keeps prompts separate from a piped installer or redirected stdin.
    if ! (exec 3<>/dev/tty) 2>/dev/null; then
        error 'No terminal for confirmation. Use --yes with an explicit action.'
        return 2
    fi
    say 'Guest integration, provisioning, backups or remote sessions may be affected. Type yes to apply:' \
        'Могут перестать работать интеграция VM, настройка сети, бэкапы или удалённые сессии. Введи yes для применения:' > /dev/tty
    IFS= read -r answer < /dev/tty || return 3
    case "$answer" in yes|YES) return 0 ;; *) say 'Cancelled.' 'Отменено.'; return 3 ;; esac
}

known_service() (
    while IFS='|' read -r _ _ _ services _; do
        for service_name in $services; do
            [ "$service_name" != "$1" ] || exit 0
        done
    done <<EOF
$(catalog)
EOF
    exit 1
)

validate_service_record() {
    if ! known_agent "$1" || ! known_service "$2"; then error "Unrecognized snapshot service: $2"; return 2; fi
    case "$4" in active|inactive) ;; *) error 'Invalid service activity state.'; return 2 ;; esac
    case "$INIT_SYSTEM:$3" in
        systemd:enabled|systemd:enabled-runtime|systemd:disabled|systemd:static|systemd:indirect|systemd:generated|systemd:transient|systemd:masked|systemd:masked-runtime) ;;
        runit:enabled|runit:disabled) ;;
        openrc:*)
            case "$3" in *[!a-zA-Z0-9_\ -]*) error 'Invalid OpenRC runlevel.'; return 2 ;; esac
            ;;
        sysv:*)
            case "$3" in *[!0-6S\ -]*) error 'Invalid SysV runlevel.'; return 2 ;; esac
            ;;
        *) error "Cannot reversibly manage $2 with startup state '$3'."; return 2 ;;
    esac
}

preflight_services() {
    while IFS='|' read -r pre_kind pre_agent pre_name pre_startup pre_active; do
        [ "$pre_kind" = service ] || continue
        validate_service_record "$pre_agent" "$pre_name" "$pre_startup" "$pre_active" || return 2
        if [ "$INIT_SYSTEM" = systemd ] && [ "$COMMAND" != restore ] && [ -e "$SYSTEM_ROOT/etc/systemd/system/$pre_name.service" ] && [ ! -L "$SYSTEM_ROOT/etc/systemd/system/$pre_name.service" ]; then
            error "Local unit cannot be masked without moving its file: $pre_name. Manage it manually."
            return 2
        fi
    done <<EOF
$FINDINGS
EOF
}

native_targets() { printf '%s\n' "$FINDINGS" | awk -F '|' '$1 == "package" { print $3 }'; }
snap_targets() { printf '%s\n' "$FINDINGS" | awk -F '|' '$1 == "snap" { print $3 }'; }

check_transaction() (
    expected=$(native_targets)
    actual=$(printf '%s\n' "$1" | awk '{ for (i=1; i<=NF; i++) print $i }')
    for name in $actual; do
        if ! printf '%s\n' "$expected" | awk -v name="$name" '$0 == name { found=1 } END { exit !found }'; then
            error "Package manager also wants to remove '$name'. Transaction refused."
            exit 2
        fi
    done
    for name in $expected; do
        if ! printf '%s\n' "$actual" | awk -v name="$name" '$0 == name { found=1 } END { exit !found }'; then
            error "Package manager did not plan removal of '$name'. Transaction refused."
            exit 2
        fi
    done
)

preflight_packages() (
    # Expansion is intentional: targets come from exact, known package names.
    set --
    for target in $(native_targets); do set -- "$@" "$target"; done
    [ "$#" -gt 0 ] || exit 0
    case "$PKG_MANAGER" in
        apt)
            simulation=$(apt-get -s -o APT::Get::AutomaticRemove=false remove -- "$@") || exit 2
            if printf '%s\n' "$simulation" | awk '$1 == "Inst" { found=1 } END { exit !found }'; then
                error 'APT also wants to install packages. Resolve the transaction manually.'
                exit 2
            fi
            planned=$(printf '%s\n' "$simulation" | awk '$1 == "Remv" || $1 == "Purg" { print $2 }')
            # APT omits the native architecture suffix in its simulation output.
            normalized=
            for name in $planned; do
                match=$(native_targets | awk -v name="$name" '{ base=$0; sub(/:[^:]+$/, "", base); if ($0 == name || base == name) print $0 }')
                normalized="$normalized ${match:-$name}"
            done
            check_transaction "$normalized"
            ;;
        dnf|dnf5|yum|zypper|rpm) "$RPM_BIN" -e --test -- "$@" ;;
        pacman) pacman -Rp --print-format '%n' -- "$@" >/dev/null ;;
        apk)
            simulation=$(apk del --simulate -- "$@" 2>&1) || { error "$simulation"; exit 2; }
            planned=$(printf '%s\n' "$simulation" | awk '$1 ~ /^\([0-9]+\/[0-9]+\)$/ && ($2 == "Purging" || $2 == "Removing") { print $3 }')
            check_transaction "$planned"
            ;;
        xbps) xbps-remove -n -- "$@" ;;
        *) error 'Package removal is unavailable on this system. Use its native deployment tools.'; exit 2 ;;
    esac
)

preflight() {
    [ "$SCAN_ERRORS" -eq 0 ] || { error 'Resolve inventory errors before applying changes.'; return 2; }
    preflight_services || return 2
    if [ "$COMMAND" = disable ]; then
        [ "$INIT_SYSTEM" != none ] || { error 'No supported running init system; service disabling is unavailable.'; return 2; }
        while IFS='|' read -r disable_kind disable_agent _ _ _; do
            case "$disable_kind" in
                package|snap|manual)
                    if [ "$(finding_count service "$disable_agent")" -eq 0 ]; then
                        error "No manageable services for $disable_agent. Inspect its packages/manual installation, or narrow the selection."
                        return 2
                    fi
                    ;;
            esac
        done <<EOF
$FINDINGS
EOF
    elif [ "$COMMAND" = remove ]; then
        if [ "$(finding_count manual)" -ne 0 ]; then
            error 'Vendor-installed VirtualBox was found. Use its vendor uninstaller, or select disable.'
            return 2
        fi
        if [ "$PKG_MANAGER" = manual ] || [ "$PKG_MANAGER" = none ]; then
            error 'Package removal is unavailable. Use disable or the native deployment manager.'
            return 2
        fi
        if [ "$(finding_count package)" -eq 0 ] && [ "$(finding_count snap)" -eq 0 ] && [ -n "$FINDINGS" ]; then
            error 'Services have no matching package. Use disable; unmanaged files are not deleted.'
            return 2
        fi
        preflight_packages || return 2
    fi
}

cleanup_lock() {
    if [ "$LOCK_HELD" -eq 1 ]; then
        rm -f "$STATE_DIR/.lock/pid"
        rmdir "$STATE_DIR/.lock" || error "Could not release lock: $STATE_DIR/.lock"
        LOCK_HELD=0
    fi
}

lock_state() {
    umask 077
    [ ! -L "$STATE_DIR" ] || { error 'State directory must not be a symlink.'; return 2; }
    if [ -e "$STATE_DIR" ]; then
        [ -d "$STATE_DIR" ] || { error 'State path is not a directory.'; return 2; }
        state_permissions=$(stat -c '%a:%u' "$STATE_DIR") || return 2
        case "$state_permissions" in 700:0) ;; *) error 'Existing state directory must be owned by root with mode 700.'; return 2 ;; esac
    else
        mkdir -p "$STATE_DIR" || return 1
        chmod 700 "$STATE_DIR" || return 1
    fi
    mkdir "$STATE_DIR/.lock" 2>/dev/null || { error "Another operation holds $STATE_DIR/.lock; inspect its pid before removing a stale lock."; return 2; }
    LOCK_HELD=1
    trap 'cleanup_lock' 0
    trap 'exit 130' INT
    trap 'exit 143' HUP TERM
    printf '%s\n' "$$" > "$STATE_DIR/.lock/pid" || return 1
}

write_snapshot() {
    SNAPSHOT=$(mktemp -d "$STATE_DIR/$(date -u +%Y%m%dT%H%M%SZ).XXXXXX") || return 1
    printf 'version=1\noperation=%s\ninit=%s\n' "$COMMAND" "$INIT_SYSTEM" > "$SNAPSHOT/metadata" || return 1
    printf '%s' "$FINDINGS" > "$SNAPSHOT/inventory" || return 1
    : > "$SNAPSHOT/output.log" || return 1
    if [ "$COMMAND" = disable ]; then
        printf '%s\n' "${SNAPSHOT##*/}" > "$STATE_DIR/latest-disable.new" || return 1
        mv -f "$STATE_DIR/latest-disable.new" "$STATE_DIR/latest-disable" || return 1
    fi
    printf '\nSnapshot: %s\n' "$SNAPSHOT"
}

run() {
    printf '  +'
    printf ' %s' "$@"
    printf '\n'
    if "$@" > "$SNAPSHOT/command.log" 2>&1; then run_status=0; else run_status=$?; fi
    {
        printf '\n$'
        printf ' %s' "$@"
        printf '\n'
        cat "$SNAPSHOT/command.log"
        printf '\nexit=%s\n' "$run_status"
    } >> "$SNAPSHOT/output.log" || return 1
    cat "$SNAPSHOT/command.log" >&2
    return "$run_status"
}

disable_service() (
    name=$1
    startup=$2
    active=$3
    case "$INIT_SYSTEM" in
        systemd)
            case "$startup" in enabled) run systemctl disable "$name.service" || exit 1 ;;
                enabled-runtime) run systemctl --runtime disable "$name.service" || exit 1 ;; esac
            run systemctl mask "$name.service" && run systemctl stop "$name.service"
            ;;
        openrc)
            if [ "$startup" != - ]; then
                for level in $startup; do run rc-update del "$name" "$level" || exit 1; done
            fi
            [ "$active" != active ] || run rc-service "$name" stop
            ;;
        runit)
            [ ! -L "$RUNIT_DIR/$name/down" ] || exit 1
            [ -e "$RUNIT_DIR/$name/down" ] || { : > "$RUNIT_DIR/$name/down" || exit 1; }
            run sv -w 15 down "$RUNIT_DIR/$name"
            ;;
        sysv)
            if [ "$SYSV_TOOL" = update-rc.d ]; then run update-rc.d "$name" disable || exit 1
            else run chkconfig "$name" off || exit 1
            fi
            [ "$active" != active ] || run service "$name" stop
            ;;
    esac
)

verify_disabled() (
    state=$(service_state "$1") || exit 1
    state=${state#*|}
    startup=${state%%|*}
    active=${state#*|}
    [ "$active" = inactive ] || exit 1
    case "$INIT_SYSTEM:$startup" in systemd:masked|openrc:-|sysv:-|runit:disabled) exit 0 ;; *) exit 1 ;; esac
)

restore_service() (
    name=$1
    startup=$2
    active=$3
    case "$INIT_SYSTEM" in
        systemd)
            run systemctl unmask "$name.service" || exit 1
            run systemctl --runtime unmask "$name.service" || exit 1
            current=$(service_state "$name") || exit 1
            current=${current#*|}
            case "${current%%|*}" in
                enabled) run systemctl disable "$name.service" || exit 1 ;;
                enabled-runtime) run systemctl --runtime disable "$name.service" || exit 1 ;;
            esac
            case "$startup" in
                enabled) run systemctl enable "$name.service" || exit 1 ;;
                enabled-runtime) run systemctl --runtime enable "$name.service" || exit 1 ;;
            esac
            if [ "$active" = active ]; then run systemctl start "$name.service" || exit 1
            else run systemctl stop "$name.service" || exit 1
            fi
            case "$startup" in
                masked) run systemctl mask "$name.service" || exit 1 ;;
                masked-runtime) run systemctl --runtime mask "$name.service" || exit 1 ;;
            esac
            ;;
        openrc)
            current=$(service_state "$name") || exit 1
            current=${current#*|}
            current_levels=${current%%|*}
            if [ "$current_levels" != - ]; then
                for level in $current_levels; do run rc-update del "$name" "$level" || exit 1; done
            fi
            if [ "$startup" != - ]; then
                for level in $startup; do run rc-update add "$name" "$level" || exit 1; done
            fi
            if [ "$active" = active ]; then run rc-service "$name" start
            elif [ "${current#*|}" = active ]; then run rc-service "$name" stop
            fi
            ;;
        runit)
            if [ "$startup" = enabled ]; then rm -f "$RUNIT_DIR/$name/down" || exit 1
            else
                [ ! -L "$RUNIT_DIR/$name/down" ] || exit 1
                [ -e "$RUNIT_DIR/$name/down" ] || { : > "$RUNIT_DIR/$name/down" || exit 1; }
            fi
            if [ "$active" = active ]; then run sv -w 15 up "$RUNIT_DIR/$name"
            else run sv -w 15 down "$RUNIT_DIR/$name"
            fi
            ;;
        sysv)
            current=$(service_state "$name") || exit 1
            if [ "$SYSV_TOOL" = update-rc.d ]; then run update-rc.d "$name" disable || exit 1
            else run chkconfig "$name" off || exit 1
            fi
            if [ "$startup" != - ]; then
                if [ "$SYSV_TOOL" = update-rc.d ]; then
                    set --
                    for level in $startup; do set -- "$@" "$level"; done
                    run update-rc.d "$name" enable "$@" || exit 1
                else
                    levels=$(printf '%s' "$startup" | tr -d ' ')
                    run chkconfig --level "$levels" "$name" on || exit 1
                fi
            fi
            if [ "$active" = active ]; then run service "$name" start
            elif [ "${current##*|}" = active ]; then run service "$name" stop
            fi
            ;;
    esac
)

apply_services() {
    while IFS='|' read -r apply_kind _ apply_name apply_startup apply_active; do
        [ "$apply_kind" = service ] || continue
        if [ "$COMMAND" = restore ]; then
            if restore_service "$apply_name" "$apply_startup" "$apply_active"; then
                current=$(service_state "$apply_name")
                if [ "$current" = "$apply_name|$apply_startup|$apply_active" ]; then CHANGED=$((CHANGED + 1))
                else error "State verification failed: $apply_name"; FAILED=$((FAILED + 1))
                fi
            else FAILED=$((FAILED + 1)); fi
        elif disable_service "$apply_name" "$apply_startup" "$apply_active" && verify_disabled "$apply_name"; then
            CHANGED=$((CHANGED + 1))
        else
            error "Service action or verification failed: $apply_name"
            FAILED=$((FAILED + 1))
        fi
    done <<EOF
$FINDINGS
EOF
}

remove_native() (
    set --
    for target in $(native_targets); do set -- "$@" "$target"; done
    [ "$#" -gt 0 ] || exit 0
    case "$PKG_MANAGER" in
        apt) run env DEBIAN_FRONTEND=noninteractive apt-get -y -o APT::Get::AutomaticRemove=false -o Dpkg::Use-Pty=0 --no-auto-remove remove -- "$@" ;;
        # rpm -e checks dependencies and never expands the removal set.
        dnf|dnf5|yum|zypper|rpm) run "$RPM_BIN" -e -- "$@" ;;
        pacman) run pacman -R --noconfirm -- "$@" ;;
        apk) run apk del -- "$@" ;;
        xbps) run xbps-remove -y -- "$@" ;;
        *) exit 2 ;;
    esac
)

remove_snaps() (
    set --
    for target in $(snap_targets); do set -- "$@" "$target"; done
    [ "$#" -gt 0 ] || exit 0
    run snap remove "$@"
)

apply_removal() {
    # Recheck dependency constraints after stopping services and before removal.
    preflight_packages || { FAILED=$((FAILED + 1)); return 1; }
    remove_native || { error 'Native package removal failed.'; FAILED=$((FAILED + 1)); }
    remove_snaps || { error 'Snap removal failed.'; FAILED=$((FAILED + 1)); }
    load_inventory
    [ "$SCAN_ERRORS" -eq 0 ] || FAILED=$((FAILED + 1))
    while IFS='|' read -r verify_kind _ verify_name _ _; do
        case "$verify_kind" in
            package)
                if [ -n "$(native_matches "${verify_name%%:*}")" ]; then
                    error "Package is still installed: $verify_name"; FAILED=$((FAILED + 1))
                else CHANGED=$((CHANGED + 1))
                fi
                ;;
            snap)
                if snap_present "$verify_name"; then error "Snap is still installed: $verify_name"; FAILED=$((FAILED + 1))
                else CHANGED=$((CHANGED + 1))
                fi
                ;;
        esac
    done <<EOF
$FINDINGS
EOF
}

print_plan() {
    printf '\nPLAN / %s\n' "$COMMAND"
    while IFS='|' read -r plan_kind _ plan_name plan_startup plan_active; do
        case "$plan_kind:$COMMAND" in
            service:restore) printf '  restore %-45s startup=%s active=%s\n' "$plan_name" "$plan_startup" "$plan_active" ;;
            service:*) printf '  disable %-45s (%s)\n' "$plan_name" "$INIT_SYSTEM" ;;
            package:remove|snap:remove) printf '  remove  %-45s (%s)\n' "$plan_name" "$plan_kind" ;;
            manual:*) printf '  manual  %s\n' "$plan_name" ;;
        esac
    done <<EOF
$FINDINGS
EOF
    if [ "$DRY_RUN" -eq 1 ]; then
        say 'Preview only. No services, packages or state files were changed.' \
            'Только предварительный просмотр. Службы, пакеты и файлы состояния не изменены.'
    fi
}

latest_snapshot() {
    latest=
    if [ -f "$STATE_DIR/latest-disable" ] && [ ! -L "$STATE_DIR/latest-disable" ]; then
        IFS= read -r latest < "$STATE_DIR/latest-disable" || return 1
    fi
    printf '%s\n' "$latest"
}

needs_service_change() {
    while IFS='|' read -r change_kind _ _ change_startup change_active; do
        [ "$change_kind" = service ] || continue
        [ "$change_active" = inactive ] || return 0
        case "$INIT_SYSTEM:$change_startup" in systemd:masked|openrc:-|sysv:-|runit:disabled) ;; *) return 0 ;; esac
    done <<EOF
$FINDINGS
EOF
    return 1
}

load_snapshot() {
    [ -n "$SNAPSHOT_ID" ] || SNAPSHOT_ID=$(latest_snapshot)
    case "$SNAPSHOT_ID" in ''|.*|*[!a-zA-Z0-9._-]*) error 'No valid disable snapshot found.'; return 2 ;; esac
    SNAPSHOT=$STATE_DIR/$SNAPSHOT_ID
    if [ ! -d "$SNAPSHOT" ] || [ -L "$SNAPSHOT" ] ||
        [ ! -f "$SNAPSHOT/metadata" ] || [ -L "$SNAPSHOT/metadata" ] ||
        [ ! -f "$SNAPSHOT/inventory" ] || [ -L "$SNAPSHOT/inventory" ]; then
        error "Invalid snapshot: $SNAPSHOT"
        return 2
    fi
    snapshot_version=
    snapshot_operation=
    snapshot_init=
    while IFS='=' read -r snapshot_key snapshot_value; do
        case "$snapshot_key" in
            version) snapshot_version=$snapshot_value ;;
            operation) snapshot_operation=$snapshot_value ;;
            init) snapshot_init=$snapshot_value ;;
            *) error 'Unknown snapshot metadata.'; return 2 ;;
        esac
    done < "$SNAPSHOT/metadata"
    if [ "$snapshot_version" != 1 ] || [ "$snapshot_init" != "$INIT_SYSTEM" ]; then
        error 'Snapshot version or init system does not match.'
        return 2
    fi
    case "$snapshot_operation" in disable|remove) ;; *) error 'Invalid snapshot operation.'; return 2 ;; esac
    FINDINGS=$(cat "$SNAPSHOT/inventory") || return 1
    while IFS='|' read -r restore_kind _ restore_name _ _; do
        case "$restore_kind" in
            package)
                [ -n "$(native_matches "${restore_name%%:*}")" ] || { error "Reinstall $restore_name before restoring its snapshot."; return 2; }
                ;;
            snap)
                snap_present "$restore_name" || { error "Reinstall snap $restore_name before restoring its snapshot."; return 2; }
                ;;
        esac
    done <<EOF
$FINDINGS
EOF
    preflight_services
}

apply() {
    preflight || return $?
    print_plan
    [ "$DRY_RUN" -eq 0 ] || return 0
    if [ -z "$FINDINGS" ]; then say 'Nothing to change.' 'Изменений не требуется.'; return 0; fi
    if [ "$COMMAND" = disable ] && ! needs_service_change; then
        say 'Services are already disabled. The previous recovery snapshot was preserved.' \
            'Службы уже отключены. Предыдущий снимок для восстановления сохранён.'
        return 0
    fi
    require_root || return 2
    confirm || return $?
    lock_state || return $?
    if [ "$COMMAND" != restore ]; then
        confirmed_findings=$FINDINGS
        scan
        if [ "$FINDINGS" != "$confirmed_findings" ] || [ "$SCAN_ERRORS" -ne 0 ]; then
            error 'Inventory changed after confirmation. Review a fresh plan.'
            return 2
        fi
        write_snapshot || return 1
    fi
    apply_services
    if [ "$COMMAND" = remove ] && [ "$FAILED" -eq 0 ]; then apply_removal; fi
    printf '\nverified: %s  |  failed: %s\nJournal: %s\n' "$CHANGED" "$FAILED" "$SNAPSHOT"
    if [ "$FAILED" -ne 0 ]; then
        say 'Incomplete operation. Read output.log; use restore for service changes from a disable snapshot.' \
            'Операция выполнена не полностью. Проверь output.log; изменения служб из снимка disable можно восстановить через restore.' >&2
        return 1
    fi
    say 'Requested changes verified.' 'Запрошенные изменения проверены.'
}

menu() {
    if ! (exec 3<>/dev/tty) 2>/dev/null; then error 'The menu requires a terminal. Use scan or --help.'; return 2; fi
    say '1  Scan   2  Preview disable   3  Disable   4  Remove   5  Restore   0  Exit' \
        '1  Проверка   2  План отключения   3  Отключить   4  Удалить   5  Восстановить   0 Выход' > /dev/tty
    printf '> ' > /dev/tty
    IFS= read -r menu_choice < /dev/tty || return 3
    case "$menu_choice" in
        0|'') return 0 ;;
        1) COMMAND=scan ;;
        2) COMMAND=disable; DRY_RUN=1 ;;
        3) COMMAND=disable ;;
        4) COMMAND=remove ;;
        5) COMMAND=restore ;;
        *) error 'Choose 0–5.'; return 2 ;;
    esac
    if [ "$COMMAND" = disable ] || [ "$COMMAND" = remove ]; then
        catalog | awk -F '|' '{ printf "  %-18s %s\n", $1, $2 }' > /dev/tty
        say 'Enter comma-separated IDs, or all (empty cancels):' 'Введи ID через запятую или all (пустой ввод — отмена):' > /dev/tty
        IFS= read -r AGENTS < /dev/tty || return 3
        case "$AGENTS" in '') return 3 ;; all) ALL=1; AGENTS= ;; esac
        validate_agents || return 2
    fi
    dispatch
}

dispatch() {
    if [ "$COMMAND" = restore ]; then
        # Journals contain system state and normally require root even for preview.
        load_inventory
        load_snapshot || return $?
        apply
    else
        scan
        if [ "$JSON" -eq 1 ]; then print_json; else print_scan; fi
        if [ "$COMMAND" = scan ]; then scan_complete || return 2
        else apply
        fi
    fi
}

install_prefix() {
    if [ -z "$PREFIX" ]; then
        if [ -f "$SCRIPT_FILE" ] && [ "${SCRIPT_FILE##*/}" = antimon ] && [ "$(basename "$(dirname "$SCRIPT_FILE")")" = bin ]; then
            PREFIX=$(CDPATH='' cd -- "$(dirname "$SCRIPT_FILE")/.." && pwd -P) || return 1
        elif [ "$(id -u)" -eq 0 ]; then PREFIX=/usr/local
        else
            [ -n "${HOME:-}" ] || { error 'HOME is unset; provide --prefix.'; return 2; }
            PREFIX=$HOME/.local
        fi
    fi
    case "$PREFIX" in
        /|*/../*|*/..|*/./*|*/.) error 'Use a dedicated absolute installation prefix.'; return 2 ;;
        /*) PREFIX=${PREFIX%/} ;;
        *) error '--prefix must be absolute.'; return 2 ;;
    esac
}

install_tool() (
    temp=
    staged=
    trap '[ -z "$staged" ] || rm -f "$staged"; [ -z "$temp" ] || rm -rf "$temp"' 0
    trap 'exit 130' INT
    trap 'exit 143' HUP TERM
    info() { [ "$QUIET" -eq 1 ] || printf '%s\n' "$*"; }
    fail() { error "$*"; exit 1; }
    fetch() {
        if has curl; then
            curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' --connect-timeout 15 --max-time 120 --retry 2 "$1" -o "$2"
        elif has wget; then wget -T 30 -O "$2" "$1"
        else error 'Install curl or wget for network installation, or run a local antimon.sh.'; return 1
        fi
    }
    digest() {
        if has sha256sum; then sha256sum "$1" | awk '{print $1}'
        elif has shasum; then shasum -a 256 "$1" | awk '{print $1}'
        elif has openssl; then openssl dgst -sha256 "$1" | awk '{print $NF}'
        else return 1
        fi
    }
    if [ -n "$SOURCE" ] && [ -n "$REF" ]; then fail 'Choose --source or --ref.'; fi
    if [ "$DRY_RUN" -eq 1 ]; then info "Would install: $PREFIX/bin/antimon"; exit 0; fi
    umask 077
    temp=$(mktemp -d) || fail 'Cannot create a temporary directory.'
    verify_checksum=1
    if [ -n "$SOURCE" ]; then
        case "$SOURCE" in /*) ;; *) fail '--source must be absolute.' ;; esac
        if ! cp "$SOURCE/antimon.sh" "$temp/antimon.sh" || ! cp "$SOURCE/SHA256SUMS" "$temp/SHA256SUMS"; then fail 'Incomplete checkout.'; fi
    elif [ -z "$REF" ] && [ -f "$SCRIPT_FILE" ] && grep -qx '# anti-monitoring: managed guest-agent inventory and service control.' "$SCRIPT_FILE"; then
        cp "$SCRIPT_FILE" "$temp/antimon.sh" || fail 'Cannot copy this script.'
        verify_checksum=0
    else
        REF=${REF:-main}
        case "$REF" in *[!a-zA-Z0-9._/-]*|../*|*/../*|*/..) fail 'Invalid Git ref.' ;; esac
        commit=
        if [ "${#REF}" -eq 40 ]; then case "$REF" in *[!0-9a-fA-F]*) ;; *) commit=$REF ;; esac; fi
        if [ -z "$commit" ]; then
            fetch "https://api.github.com/repos/HVHBIGNAME/anti-monitoring/commits/$REF" "$temp/commit.json" || fail 'Cannot resolve Git ref; check connectivity/rate limits or use a full commit SHA.'
            commit=$(sed -n 's/^[[:space:]]*"sha":[[:space:]]*"\([0-9a-f]*\)".*/\1/p' "$temp/commit.json" | sed -n '1p')
            [ "${#commit}" -eq 40 ] || fail 'Invalid commit response.'
        fi
        info "Source: HVHBIGNAME/anti-monitoring@$commit"
        base=https://raw.githubusercontent.com/HVHBIGNAME/anti-monitoring/$commit
        if ! fetch "$base/antimon.sh" "$temp/antimon.sh" || ! fetch "$base/SHA256SUMS" "$temp/SHA256SUMS"; then fail 'Download failed; installation was not changed.'; fi
    fi
    [ -s "$temp/antimon.sh" ] || fail 'Empty script.'
    if [ "$verify_checksum" -eq 1 ]; then
        expected=$(awk '$2 == "antimon.sh" {print $1}' "$temp/SHA256SUMS")
        [ "${#expected}" -eq 64 ] || fail 'Invalid checksum manifest.'
        case "$expected" in *[!0-9a-f]*) fail 'Invalid SHA-256 digest.' ;; esac
        actual=$(digest "$temp/antimon.sh") || fail 'Install sha256sum, shasum or openssl.'
        [ "$actual" = "$expected" ] || fail 'SHA-256 mismatch; installation was not changed.'
    fi
    sh -n "$temp/antimon.sh" || fail 'Invalid shell syntax.'
    grep -qx '# anti-monitoring: managed guest-agent inventory and service control.' "$temp/antimon.sh" || fail 'Unexpected script identity.'
    destination=$PREFIX/bin/antimon
    [ ! -L "$destination" ] || fail "Refusing to replace a symlink: $destination"
    if [ -e "$destination" ]; then
        if [ ! -f "$destination" ] || ! grep -qx '# anti-monitoring: managed guest-agent inventory and service control.' "$destination"; then
            fail "Refusing to overwrite an unrelated file: $destination"
        fi
    fi
    (umask 022; mkdir -p "$PREFIX/bin") || fail "Cannot create $PREFIX/bin. Choose a writable prefix or run as root."
    staged=$(mktemp "$PREFIX/bin/.antimon.XXXXXX") || fail 'Cannot stage installation.'
    if ! cp "$temp/antimon.sh" "$staged" || ! chmod 755 "$staged"; then fail 'Cannot prepare executable.'; fi
    mv -f "$staged" "$destination" || fail 'Cannot atomically install executable.'
    staged=
    info "Installed: $destination"
    info "Help: $destination --help"
    case ":${PATH:-}:" in *":$PREFIX/bin:"*) ;; *) info "Add $PREFIX/bin to PATH, or use the full path." ;; esac
)

boot_paths() {
    BOOT_BINARY=$PREFIX/bin/antimon
    BOOT_LINK=
    case "$INIT_SYSTEM" in
        systemd) BOOT_FILE=$SYSTEM_ROOT/etc/systemd/system/$BOOT_SERVICE.service ;;
        openrc|sysv) BOOT_FILE=$SYSTEM_ROOT/etc/init.d/$BOOT_SERVICE ;;
        runit) BOOT_FILE=$SYSTEM_ROOT/etc/sv/$BOOT_SERVICE/run; BOOT_LINK=$RUNIT_DIR/$BOOT_SERVICE ;;
        *) BOOT_FILE= ;;
    esac
}

check_boot_owner() {
    [ -n "$BOOT_FILE" ] || { error 'Autostart requires systemd, OpenRC, runit or SysV init.'; return 2; }
    if [ -L "$BOOT_FILE" ]; then error "Refusing boot-entry symlink: $BOOT_FILE"; return 2; fi
    if [ -e "$BOOT_FILE" ]; then
        if [ ! -f "$BOOT_FILE" ] || ! grep -qxF '# anti-monitoring: managed boot entry.' "$BOOT_FILE" ||
            ! grep -qxF "# executable: $BOOT_BINARY" "$BOOT_FILE"; then
            error "Boot entry belongs to another program or prefix: $BOOT_FILE"
            return 2
        fi
    fi
    if [ -n "$BOOT_LINK" ] && { [ -e "$BOOT_LINK" ] || [ -L "$BOOT_LINK" ]; }; then
        if [ ! -L "$BOOT_LINK" ] || [ "$(readlink "$BOOT_LINK")" != "${BOOT_FILE%/run}" ]; then
            error "Unrelated runit entry: $BOOT_LINK"; return 2
        fi
    fi
}

trusted_boot_path() (
    path=$1
    while [ -n "$path" ]; do
        [ ! -L "$path" ] || { error "Autostart path must not contain symlinks: $path"; exit 2; }
        if [ -e "$path" ]; then
            permissions=$(stat -c '%a:%u' "$path") || exit 2
            mode=${permissions%:*}
            if [ "${permissions##*:}" != 0 ] || [ $((0$mode & 0022)) -ne 0 ]; then
                error "Autostart requires root-owned paths without group/other write access: $path"
                exit 2
            fi
        fi
        [ "$path" != / ] || break
        path=${path%/*}
        [ -n "$path" ] || path=/
    done
)

boot_preflight() {
    check_boot_owner || return 2
    case "$BOOT_BINARY$STATE_DIR" in *[!a-zA-Z0-9_./\ -]*) error 'Autostart paths may contain letters, numbers, spaces, dots, dashes, underscores and slashes.'; return 2 ;; esac
    trusted_boot_path "$BOOT_BINARY" || return 2
    trusted_boot_path "$(dirname "$BOOT_FILE")" || return 2
    if [ "$INIT_SYSTEM" = runit ]; then
        [ -r "$SYSTEM_ROOT/proc/sys/kernel/random/boot_id" ] || { error 'runit autostart requires /proc/sys/kernel/random/boot_id.'; return 2; }
        if [ -d "${BOOT_FILE%/run}" ] && [ ! -f "$BOOT_FILE" ]; then
            error 'Existing runit directory has no owned boot entry.'; return 2
        fi
    fi
}

render_boot_entry() {
    if [ "$INIT_SYSTEM" = openrc ]; then printf '#!/sbin/openrc-run\n'
    elif [ "$INIT_SYSTEM" != systemd ]; then printf '#!/bin/sh\n'
    fi
    printf '# anti-monitoring: managed boot entry.\n# executable: %s\n' "$BOOT_BINARY"
    if [ "$ALL" -eq 1 ]; then boot_selection=--all; else boot_selection="--agents $AGENTS"; fi
    boot_command="'$BOOT_BINARY' --disable $boot_selection --yes --state-dir '$STATE_DIR' --lang $LANGUAGE"
    case "$INIT_SYSTEM" in
        systemd)
            cat <<EOF
[Unit]
Description=Anti-Monitoring selected guest-agent policy
After=network.target
[Service]
Type=oneshot
ExecStart="$BOOT_BINARY" --disable $boot_selection --yes --state-dir "$STATE_DIR" --lang $LANGUAGE
RemainAfterExit=yes
TimeoutStartSec=180
[Install]
WantedBy=multi-user.target
EOF
            ;;
        openrc)
            cat <<EOF
description="Anti-Monitoring selected guest-agent policy"
depend() { need localmount; after bootmisc; }
start() {
    ebegin "Applying Anti-Monitoring policy"
    $boot_command
    eend \$?
}
stop() { return 0; }
EOF
            ;;
        sysv)
            cat <<EOF
# chkconfig: 2345 99 01
# description: Anti-Monitoring selected guest-agent policy
### BEGIN INIT INFO
# Provides:          $BOOT_SERVICE
# Required-Start:    \$local_fs
# Required-Stop:
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Apply selected guest-agent policy
### END INIT INFO
case "\${1:-}" in
    start) $boot_command ;;
    stop) exit 0 ;;
    *) echo "Usage: \$0 start|stop" >&2; exit 2 ;;
esac
EOF
            ;;
        runit)
            registered_boot=$(cat "$SYSTEM_ROOT/proc/sys/kernel/random/boot_id") || return 1
            case "$registered_boot" in ''|*[!a-fA-F0-9-]*) error 'Invalid boot ID.'; return 2 ;; esac
            cat <<EOF
# Registration does not apply the policy during the current boot.
boot_id=\$(cat /proc/sys/kernel/random/boot_id) || exit 1
if [ "\$boot_id" != '$registered_boot' ]; then
    $boot_command
    result=\$?
    printf 'Anti-Monitoring boot exit: %s\n' "\$result"
fi
exec sv down .
EOF
            ;;
    esac
}

enable_boot() (
    [ -x "$BOOT_BINARY" ] || { error 'Install antimon first with --install.'; exit 2; }
    grep -qxF '# anti-monitoring: managed guest-agent inventory and service control.' "$BOOT_BINARY" || { error 'Installed command has an unexpected identity.'; exit 2; }
    temporary=
    trap '[ -z "$temporary" ] || rm -f "$temporary"' 0
    (umask 022; mkdir -p "$(dirname "$BOOT_FILE")") || exit 1
    temporary=$(mktemp "$(dirname "$BOOT_FILE")/.antimon-boot.XXXXXX") || exit 1
    render_boot_entry > "$temporary" || exit 1
    if [ "$INIT_SYSTEM" = systemd ]; then chmod 644 "$temporary" || exit 1
    else
        if ! sh -n "$temporary" || ! chmod 755 "$temporary"; then exit 1; fi
    fi
    mv -f "$temporary" "$BOOT_FILE" || exit 1
    temporary=
    case "$INIT_SYSTEM" in
        systemd)
            systemctl daemon-reload && systemctl enable "$BOOT_SERVICE.service" && systemctl is-enabled --quiet "$BOOT_SERVICE.service"
            ;;
        openrc)
            rc-update add "$BOOT_SERVICE" default || exit 1
            rc-update show default | awk -v name="$BOOT_SERVICE" '$1 == name {found=1} END {exit !found}'
            ;;
        sysv)
            if [ "$SYSV_TOOL" = update-rc.d ]; then
                if ! update-rc.d "$BOOT_SERVICE" defaults || ! update-rc.d "$BOOT_SERVICE" enable; then exit 1; fi
            else
                if ! chkconfig --add "$BOOT_SERVICE" || ! chkconfig "$BOOT_SERVICE" on; then exit 1; fi
            fi
            [ -n "$(sysv_levels "$BOOT_SERVICE")" ]
            ;;
        runit)
            [ -L "$BOOT_LINK" ] || ln -s "${BOOT_FILE%/run}" "$BOOT_LINK" || exit 1
            [ -L "$BOOT_LINK" ]
            ;;
    esac
)

disable_boot() {
    check_boot_owner || return 2
    if [ ! -f "$BOOT_FILE" ]; then
        [ -z "$BOOT_LINK" ] || [ ! -L "$BOOT_LINK" ] || { error 'Orphaned runit entry; inspect it manually.'; return 2; }
        return 0
    fi
    if [ "$DRY_RUN" -eq 1 ]; then printf 'Would remove autostart: %s\n' "$BOOT_FILE"; return 0; fi
    require_root || return 2
    case "$INIT_SYSTEM" in
        systemd) systemctl disable "$BOOT_SERVICE.service" || return 1 ;;
        openrc)
            boot_levels=$(rc-update show -v) || return 1
            boot_levels=$(printf '%s\n' "$boot_levels" | awk -v name="$BOOT_SERVICE" '$1 == name {for (i=3;i<=NF;i++) print $i}')
            for boot_level in $boot_levels; do rc-update del "$BOOT_SERVICE" "$boot_level" || return 1; done
            ;;
        sysv)
            if [ "$SYSV_TOOL" = update-rc.d ]; then update-rc.d -f "$BOOT_SERVICE" remove || return 1
            else chkconfig --del "$BOOT_SERVICE" || return 1
            fi
            ;;
        runit)
            if [ -L "$BOOT_LINK" ]; then
                sv down "$BOOT_LINK" || return 1
                rm -f "$BOOT_LINK" || return 1
            fi
            # Keep the inactive service definition and supervisor metadata so it
            # can be registered again without deleting runit's state directory.
            return 0
            ;;
    esac
    rm -f "$BOOT_FILE" || return 1
    if [ "$INIT_SYSTEM" = systemd ]; then systemctl daemon-reload || return 1; fi
}

configure_boot() {
    if [ "$AUTOSTART" = --no-autostart ]; then
        check_boot_owner || return 2
        if [ "$DRY_RUN" -eq 0 ] && [ -f "$BOOT_FILE" ]; then
            require_root || return 2
            lock_state || return $?
        fi
        disable_boot || return $?
        [ "$DRY_RUN" -eq 1 ] || say 'Autostart removed.' 'Автостарт выключен.'
        return 0
    fi
    boot_preflight || return 2
    printf 'Autostart / %s: %s --disable %s\n' "$INIT_SYSTEM" "$BOOT_BINARY" "${AGENTS:---all}"
    [ "$DRY_RUN" -eq 0 ] || return 0
    require_root || return 2
    confirm || return $?
    lock_state || return $?
    if ! enable_boot; then error 'Autostart setup or verification failed; inspect the boot entry.'; return 1; fi
    say 'Autostart enabled for the next boot. Guest agents were not changed now.' \
        'Автостарт включён со следующей загрузки. Сейчас состояние агентов не изменено.'
}

uninstall_tool() {
    destination=$PREFIX/bin/antimon
    if [ -L "$destination" ]; then error "Refusing to remove a symlink: $destination"; return 2; fi
    if [ -e "$destination" ] && { [ ! -f "$destination" ] || ! grep -qxF '# anti-monitoring: managed guest-agent inventory and service control.' "$destination"; }; then
        error "Refusing to remove an unrelated file: $destination"; return 2
    fi
    # An ordinary per-user installation does not own a system-wide boot entry.
    if [ -n "$BOOT_FILE" ] && [ -f "$BOOT_FILE" ] && grep -qxF "# executable: $destination" "$BOOT_FILE"; then
        if [ "$DRY_RUN" -eq 0 ]; then require_root || return 2; lock_state || return $?; fi
        disable_boot || return $?
    fi
    if [ "$DRY_RUN" -eq 1 ]; then printf 'Would remove: %s\n' "$destination"
    else rm -f "$destination" || return 1; printf 'Removed: %s\n' "$destination"
    fi
    if [ "$LEGACY" -eq 1 ]; then
        [ -n "${HOME:-}" ] || { error 'HOME is unset.'; return 2; }
        legacy_file=$HOME/.cache/system/.antimon
        if [ -e "$legacy_file" ] || [ -L "$legacy_file" ]; then
            if [ -L "$legacy_file" ] || ! grep -q 'Anti-Monitoring Tool' "$legacy_file"; then error 'Unrecognized legacy script.'; return 2; fi
            if [ "$DRY_RUN" -eq 1 ]; then printf 'Would remove: %s\n' "$legacy_file"; else rm -f "$legacy_file" || return 1; fi
        fi
    fi
    say 'Recovery snapshots and guest-agent state were preserved.' 'Снимки и состояние гостевых агентов сохранены.'
}

main() {
    parse_args "$@" || return $?
    case "$COMMAND" in
        help) usage; return 0 ;;
        version) printf '%s\n' "$VERSION"; return 0 ;;
        list) catalog | awk -F '|' '{ printf "%-18s %s\n  %s\n", $1, $2, $5 }'; return 0 ;;
    esac
    detect_platform || return $?
    case "$COMMAND" in
        install|uninstall|autostart)
            install_prefix || return $?
            boot_paths
            ;;
    esac
    case "$COMMAND" in
        install)
            if [ -n "$AUTOSTART" ]; then
                boot_preflight || return 2
                if [ "$DRY_RUN" -eq 0 ]; then require_root || return 2; fi
            fi
            install_tool || return $?
            if [ -n "$AUTOSTART" ]; then
                configure_boot || return $?
                cleanup_lock
            fi
            if [ "$RUN" -eq 1 ] && [ "$DRY_RUN" -eq 0 ]; then
                if [ -t 1 ] && (exec 3<>/dev/tty) 2>/dev/null; then sh "$PREFIX/bin/antimon" --menu --lang "$LANGUAGE" || return $?
                else sh "$PREFIX/bin/antimon" --scan --lang "$LANGUAGE" || return $?
                fi
            fi
            return 0
            ;;
        uninstall) uninstall_tool; return $? ;;
        autostart) configure_boot; return $? ;;
    esac
    if [ "$COMMAND" = menu ]; then menu; else dispatch; fi
}

main "$@"
