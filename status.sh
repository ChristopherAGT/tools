
#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

# ============================================================
#              EPRO DEV SYSTEM AUDIT
#          ADVANCED LINUX PERFORMANCE DIAGNOSTIC
# ============================================================
#
# AUDITORIA INTEGRAL:
#   - Sistema operativo y kernel
#   - CPU, RAM, SWAP y almacenamiento
#   - Todos los parametros SYSCTL
#   - Optimizacion TCP/IP
#   - BBR, CUBIC, FQ y algoritmos disponibles
#   - Netfilter, Conntrack y Firewall
#   - Interfaces, MTU y offloading
#   - Socket, backlog y retransmisiones
#   - Limites del sistema y procesos
#   - Systemd y servicios
#   - Configuraciones persistentes
#   - Seguridad y diagnostico de rendimiento
#
# IMPORTANTE:
#   SCRIPT DE SOLO LECTURA.
#   NO MODIFICA NINGUNA CONFIGURACION.
#
# ============================================================

export LC_ALL=C
export SYSTEMD_PAGER=cat
export PAGER=cat

VERSION="1.0.0"
TITLE="EPRO DEV SYSTEM AUDIT"

CYAN='\033[1;36m'
BLUE='\033[1;34m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
WHITE='\033[1;37m'
GRAY='\033[0;37m'
RESET='\033[0m'

if [[ ! -t 1 ]]; then
    CYAN='' BLUE='' GREEN='' YELLOW=''
    RED='' WHITE='' GRAY='' RESET=''
fi

line() {
    printf '%b\n' "${GRAY}────────────────────────────────────────────────────────────${RESET}"
}

header() {
    clear 2>/dev/null || true
    printf '\n'
    printf '%b\n' "${CYAN}              EPRO DEV SYSTEM AUDIT${RESET}"
    printf '%b\n' "${WHITE}          ADVANCED PERFORMANCE ANALYSIS${RESET}"
    printf '%b\n' "${GRAY}                    VERSION ${VERSION}${RESET}"
    line
    printf '\n'
}

section() {
    printf '\n'
    printf '%b\n' "${BLUE}◆  $1${RESET}"
    line
}

ok() {
    printf '  %b %s\n' "${GREEN}✓${RESET}" "$1"
}

warn() {
    printf '  %b %s\n' "${YELLOW}!${RESET}" "$1"
}

bad() {
    printf '  %b %s\n' "${RED}✗${RESET}" "$1"
}

info() {
    printf '  %b %s\n' "${CYAN}●${RESET}" "$1"
}

cmd() {
    command -v "$1" >/dev/null 2>&1
}

value() {
    local label="$1"
    local result="$2"
    printf '  %-34s %s\n' "$label" "${result:-N/D}"
}

read_file() {
    local file="$1"
    if [[ -r "$file" ]]; then
        cat "$file" 2>/dev/null || true
    else
        printf 'N/D\n'
    fi
}

run_section() {
    local description="$1"
    shift
    printf '\n  %s\n' "$description"
    "$@" 2>/dev/null || true
}

# ============================================================
# 01. SYSTEM INFORMATION
# ============================================================

system_info() {
    section "01. INFORMACION GENERAL DEL SISTEMA"

    [[ -r /etc/os-release ]] && {
        . /etc/os-release
        value "Distribucion:" "${PRETTY_NAME:-N/D}"
    }

    value "Hostname:" "$(hostname 2>/dev/null)"
    value "Kernel:" "$(uname -r)"
    value "Arquitectura:" "$(uname -m)"
    value "Version kernel:" "$(uname -v)"
    value "Tiempo encendido:" "$(uptime -p 2>/dev/null)"
    value "Fecha:" "$(date '+%Y-%m-%d %H:%M:%S %Z')"
    value "Virtualizacion:" "$(systemd-detect-virt 2>/dev/null || echo N/D)"
    value "PID 1:" "$(ps -p 1 -o comm= 2>/dev/null)"
    value "Cantidad de CPU:" "$(nproc 2>/dev/null)"
    value "Procesos activos:" "$(ps -e --no-headers 2>/dev/null | wc -l)"

    if [[ -r /proc/cmdline ]]; then
        value "Parametros de arranque:" "$(cat /proc/cmdline)"
    fi

    if cmd lsb_release; then
        value "Distribucion LSB:" "$(lsb_release -ds 2>/dev/null)"
    fi
}

# ============================================================
# 02. CPU
# ============================================================

cpu_info() {
    section "02. CPU Y PROCESAMIENTO"

    value "Modelo:" "$(awk -F: '/model name/ {gsub(/^[ \t]+/,"",$2); print $2; exit}' /proc/cpuinfo)"
    value "Nucleos disponibles:" "$(nproc)"
    value "Load average:" "$(cat /proc/loadavg)"
    value "CPU online:" "$(cat /sys/devices/system/cpu/online 2>/dev/null)"
    value "CPU governor:" "$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null)"
    value "Frecuencia actual:" "$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq 2>/dev/null)"
    value "Frecuencia minima:" "$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq 2>/dev/null)"
    value "Frecuencia maxima:" "$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq 2>/dev/null)"
    value "CPU idle:" "$(grep '^cpu ' /proc/stat)"

    printf '\n  TOP PROCESOS POR CPU\n'
    ps -eo pid,comm,%cpu,%mem --sort=-%cpu 2>/dev/null | head -11

    printf '\n  INTERRUPCIONES\n'
    head -12 /proc/interrupts 2>/dev/null || true

    printf '\n  CONTEXT SWITCHES\n'
    grep -E 'ctxt|processes|procs_running|procs_blocked' /proc/stat
}

# ============================================================
# 03. MEMORY
# ============================================================

memory_info() {
    section "03. MEMORIA RAM Y SWAP"

    free -h

    printf '\n  DETALLE DE MEMORIA\n'
    grep -E '^(MemTotal|MemFree|MemAvailable|Buffers|Cached|SReclaimable|Shmem|SwapTotal|SwapFree|Dirty|Writeback|Slab|PageTables|KernelStack|Unevictable|Mlocked|Committed_AS|CommitLimit):' /proc/meminfo

    printf '\n  SWAPPINESS Y VM\n'
    for key in \
        vm.swappiness \
        vm.vfs_cache_pressure \
        vm.dirty_ratio \
        vm.dirty_background_ratio \
        vm.dirty_bytes \
        vm.dirty_background_bytes \
        vm.overcommit_memory \
        vm.overcommit_ratio \
        vm.min_free_kbytes \
        vm.zone_reclaim_mode \
        vm.page-cluster \
        vm.max_map_count
    do
        sysctl "$key" 2>/dev/null || true
    done

    printf '\n  PRESION DE MEMORIA (PSI)\n'
    for f in /proc/pressure/cpu /proc/pressure/memory /proc/pressure/io; do
        if [[ -r "$f" ]]; then
            printf '\n  %s\n' "$f"
            cat "$f"
        fi
    done

    printf '\n  PROCESOS CON MAYOR CONSUMO RAM\n'
    ps -eo pid,comm,%mem,rss --sort=-%mem 2>/dev/null | head -11

    printf '\n  OOM EVENTS\n'
    if [[ -r /proc/vmstat ]]; then
        grep -E '^(oom_kill|pgmajfault|pswpin|pswpout|pgscan|pgsteal)' /proc/vmstat || true
    fi
}

# ============================================================
# 04. STORAGE AND I/O
# ============================================================

storage_info() {
    section "04. ALMACENAMIENTO Y DISCO"

    printf '\n  PARTICIONES\n'
    df -hT

    printf '\n  DISPOSITIVOS\n'
    if cmd lsblk; then
        lsblk -o NAME,TYPE,SIZE,FSTYPE,MOUNTPOINT,ROTA,SCHED 2>/dev/null || lsblk
    fi

    printf '\n  I/O SCHEDULER\n'
    for f in /sys/block/*/queue/scheduler; do
        [[ -r "$f" ]] || continue
        printf '  %-24s %s\n' "$f" "$(cat "$f")"
    done

    printf '\n  PARAMETROS DE COLA DE DISCO\n'
    for f in /sys/block/*/queue/{nr_requests,read_ahead_kb,rotational,rq_affinity,nomerges}; do
        [[ -r "$f" ]] || continue
        printf '  %-55s %s\n' "$f" "$(cat "$f")"
    done

    printf '\n  ESTADISTICAS DE DISCO\n'
    cat /proc/diskstats 2>/dev/null

    printf '\n  MONTAGENS\n'
    findmnt -o TARGET,SOURCE,FSTYPE,OPTIONS 2>/dev/null || true

    if cmd iostat; then
        printf '\n  IOSTAT\n'
        iostat -xz 1 1 2>/dev/null || true
    else
        warn "Instala sysstat para obtener iostat."
    fi
}

# ============================================================
# 05. KERNEL
# ============================================================

kernel_info() {
    section "05. KERNEL Y CONFIGURACION"

    value "Kernel release:" "$(uname -r)"
    value "Kernel version:" "$(uname -v)"
    value "Kernel taint:" "$(cat /proc/sys/kernel/tainted 2>/dev/null)"
    value "Modules cargados:" "$(lsmod 2>/dev/null | wc -l)"
    value "Kernel lockdown:" "$(cat /sys/kernel/security/lockdown 2>/dev/null)"
    value "Random entropy:" "$(cat /proc/sys/kernel/random/entropy_avail 2>/dev/null)"

    printf '\n  PARAMETROS KERNEL\n'
    for key in \
        kernel.pid_max \
        kernel.threads-max \
        kernel.core_pattern \
        kernel.core_uses_pid \
        kernel.panic \
        kernel.panic_on_oops \
        kernel.sched_autogroup_enabled \
        kernel.numa_balancing \
        kernel.kptr_restrict \
        kernel.dmesg_restrict \
        kernel.perf_event_paranoid \
        kernel.unprivileged_bpf_disabled \
        kernel.yama.ptrace_scope
    do
        sysctl "$key" 2>/dev/null || true
    done

    printf '\n  MODULOS RELEVANTES\n'
    lsmod 2>/dev/null | grep -Ei 'tcp|bbr|sch_fq|nf_conntrack|ip_tables|nf_tables|xt_' || true

    printf '\n  ERRORES RECIENTES DEL KERNEL\n'
    if cmd journalctl; then
        journalctl -k -p err -n 30 --no-pager 2>/dev/null || true
    elif cmd dmesg; then
        dmesg --level=err,warn 2>/dev/null | tail -30 || true
    fi
}

# ============================================================
# 06. ALL SYSCTL
# ============================================================

all_sysctl() {
    section "06. INVENTARIO COMPLETO SYSCTL"

    info "Leyendo todos los parametros activos del kernel."
    printf '\n'

    sysctl -a 2>/dev/null | sort || true
}

# ============================================================
# 07. TCP/IP
# ============================================================

tcp_info() {
    section "07. OPTIMIZACION TCP/IP"

    local keys=(
        net.ipv4.ip_forward
        net.ipv4.tcp_congestion_control
        net.ipv4.tcp_available_congestion_control
        net.ipv4.tcp_allowed_congestion_control
        net.ipv4.tcp_available_ulp
        net.ipv4.tcp_rmem
        net.ipv4.tcp_wmem
        net.ipv4.tcp_mem
        net.core.rmem_max
        net.core.rmem_default
        net.core.wmem_max
        net.core.wmem_default
        net.core.optmem_max
        net.core.netdev_max_backlog
        net.core.netdev_budget
        net.core.netdev_budget_usecs
        net.core.somaxconn
        net.core.default_qdisc
        net.ipv4.tcp_max_syn_backlog
        net.ipv4.tcp_max_tw_buckets
        net.ipv4.tcp_max_orphans
        net.ipv4.tcp_fin_timeout
        net.ipv4.tcp_keepalive_time
        net.ipv4.tcp_keepalive_intvl
        net.ipv4.tcp_keepalive_probes
        net.ipv4.tcp_retries1
        net.ipv4.tcp_retries2
        net.ipv4.tcp_syn_retries
        net.ipv4.tcp_synack_retries
        net.ipv4.tcp_syncookies
        net.ipv4.tcp_fastopen
        net.ipv4.tcp_sack
        net.ipv4.tcp_dsack
        net.ipv4.tcp_window_scaling
        net.ipv4.tcp_timestamps
        net.ipv4.tcp_ecn
        net.ipv4.tcp_mtu_probing
        net.ipv4.tcp_no_metrics_save
        net.ipv4.tcp_moderate_rcvbuf
        net.ipv4.tcp_notsent_lowat
        net.ipv4.tcp_limit_output_bytes
        net.ipv4.tcp_autocorking
        net.ipv4.tcp_low_latency
        net.ipv4.tcp_tw_reuse
        net.ipv4.ip_local_port_range
        net.ipv4.ip_local_reserved_ports
        net.ipv4.route.gc_timeout
        net.ipv4.neigh.default.gc_thresh1
        net.ipv4.neigh.default.gc_thresh2
        net.ipv4.neigh.default.gc_thresh3
    )

    for key in "${keys[@]}"; do
        sysctl "$key" 2>/dev/null || true
    done

    printf '\n  ALGORITMOS TCP DISPONIBLES\n'
    cat /proc/sys/net/ipv4/tcp_available_congestion_control 2>/dev/null || true

    printf '\n  QDISC DISPONIBLES\n'
    if cmd tc; then
        tc qdisc show 2>/dev/null || true
        printf '\n  DISCIPLINAS DISPONIBLES\n'
        tc qdisc help 2>&1 | head -25 || true
    fi

    printf '\n  TCP GLOBAL\n'
    cat /proc/net/snmp 2>/dev/null

    printf '\n  TCP EXTENDIDO\n'
    cat /proc/net/netstat 2>/dev/null

    printf '\n  TCP SOCKET MEMORY\n'
    cat /proc/net/sockstat 2>/dev/null
    cat /proc/net/sockstat6 2>/dev/null || true
}

# ============================================================
# 08. UDP / SOCKETS
# ============================================================

socket_info() {
    section "08. UDP, SOCKETS Y CONEXIONES"

    printf '\n  UDP CONFIGURACION\n'
    for key in \
        net.ipv4.udp_mem \
        net.ipv4.udp_rmem_min \
        net.ipv4.udp_wmem_min \
        net.ipv4.udp_early_demux \
        net.ipv4.udp_l3mdev_accept
    do
        sysctl "$key" 2>/dev/null || true
    done

    printf '\n  ESTADOS TCP\n'
    if cmd ss; then
        ss -s
        printf '\n  CONEXIONES POR ESTADO\n'
        ss -tanH 2>/dev/null | awk '{count[$1]++} END {for (s in count) print s, count[s]}' | sort
        printf '\n  PUERTOS ESCUCHANDO\n'
        ss -lntup 2>/dev/null || true
        printf '\n  CONEXIONES ESTABLECIDAS\n'
        ss -tan state established 2>/dev/null | head -30
    fi

    printf '\n  CONTEO DE SOCKETS\n'
    for f in /proc/net/tcp /proc/net/tcp6 /proc/net/udp /proc/net/udp6; do
        [[ -r "$f" ]] || continue
        value "$f:" "$(( $(wc -l < "$f") - 1 ))"
    done
}

# ============================================================
# 09. CONNTRACK / FIREWALL
# ============================================================

firewall_info() {
    section "09. NETFILTER, CONNTRACK Y FIREWALL"

    for key in \
        net.netfilter.nf_conntrack_max \
        net.netfilter.nf_conntrack_count \
        net.netfilter.nf_conntrack_buckets \
        net.netfilter.nf_conntrack_tcp_timeout_established \
        net.netfilter.nf_conntrack_tcp_timeout_time_wait \
        net.netfilter.nf_conntrack_tcp_timeout_close_wait \
        net.netfilter.nf_conntrack_udp_timeout \
        net.netfilter.nf_conntrack_udp_timeout_stream
    do
        sysctl "$key" 2>/dev/null || true
    done

    printf '\n  CONNTRACK\n'
    if [[ -r /proc/sys/net/netfilter/nf_conntrack_count ]]; then
        value "Conexiones actuales:" "$(cat /proc/sys/net/netfilter/nf_conntrack_count)"
        value "Limite maximo:" "$(cat /proc/sys/net/netfilter/nf_conntrack_max)"
    fi

    printf '\n  NFTABLES\n'
    if cmd nft; then
        nft list ruleset 2>/dev/null || warn "No se pudo leer nftables."
    fi

    printf '\n  IPTABLES\n'
    if cmd iptables; then
        iptables -L -n -v 2>/dev/null || true
    fi

    printf '\n  IP6TABLES\n'
    if cmd ip6tables; then
        ip6tables -L -n -v 2>/dev/null || true
    fi

    printf '\n  UFW\n'
    if cmd ufw; then
        ufw status verbose 2>/dev/null || true
    fi
}

# ============================================================
# 10. NETWORK INTERFACES
# ============================================================

network_info() {
    section "10. INTERFACES DE RED"

    printf '\n  INTERFACES\n'
    if cmd ip; then
        ip -br address 2>/dev/null || ip address
        printf '\n  ROUTING\n'
        ip route show 2>/dev/null
        printf '\n  ROUTING IPv6\n'
        ip -6 route show 2>/dev/null
        printf '\n  RULES\n'
        ip rule show 2>/dev/null
    fi

    printf '\n  PARAMETROS POR INTERFAZ\n'
    for dir in /sys/class/net/*; do
        [[ -d "$dir" ]] || continue
        local iface
        iface="${dir##*/}"

        printf '\n  INTERFAZ: %s\n' "$iface"

        for key in mtu tx_queue_len operstate speed duplex carrier \
                   address type ifindex; do
            [[ -r "$dir/$key" ]] || continue
            printf '    %-18s %s\n' "$key" "$(cat "$dir/$key" 2>/dev/null)"
        done

        for key in rx_bytes tx_bytes rx_packets tx_packets \
                   rx_errors tx_errors rx_dropped tx_dropped \
                   collisions rx_missed_errors; do
            [[ -r "$dir/statistics/$key" ]] || continue
            printf '    %-18s %s\n' "$key" "$(cat "$dir/statistics/$key")"
        done

        if cmd ethtool; then
            printf '\n    OFFLOADING\n'
            ethtool -k "$iface" 2>/dev/null || true
            printf '\n    DRIVER\n'
            ethtool -i "$iface" 2>/dev/null || true
        fi
    done

    printf '\n  TCP/IP INTERFACES\n'
    for key in \
        net.ipv4.conf.all.rp_filter \
        net.ipv4.conf.default.rp_filter \
        net.ipv4.conf.all.accept_redirects \
        net.ipv4.conf.all.send_redirects \
        net.ipv4.conf.all.accept_source_route \
        net.ipv4.conf.all.log_martians \
        net.ipv4.conf.all.arp_filter \
        net.ipv4.conf.all.arp_ignore \
        net.ipv4.conf.all.arp_announce \
        net.ipv6.conf.all.disable_ipv6 \
        net.ipv6.conf.all.accept_ra \
        net.ipv6.conf.all.forwarding
    do
        sysctl "$key" 2>/dev/null || true
    done
}

# ============================================================
# 11. LIMITS
# ============================================================

limits_info() {
    section "11. LIMITES DEL SISTEMA"

    value "Ulimit actual:" "$(ulimit -a | tr '\n' ' ')"

    printf '\n  LIMITES DEL PROCESO ACTUAL\n'
    cat /proc/self/limits 2>/dev/null

    printf '\n  FILE HANDLES\n'
    for key in \
        fs.file-max \
        fs.nr_open \
        fs.inotify.max_user_instances \
        fs.inotify.max_user_watches \
        fs.aio-max-nr \
        fs.aio-nr
    do
        sysctl "$key" 2>/dev/null || true
    done

    printf '\n  FILE DESCRIPTORS DEL SISTEMA\n'
    cat /proc/sys/fs/file-nr 2>/dev/null || true

    printf '\n  PAM LIMITS\n'
    if [[ -r /etc/security/limits.conf ]]; then
        grep -Ev '^[[:space:]]*(#|$)' /etc/security/limits.conf || true
    fi

    printf '\n  LIMITS.D\n'
    if [[ -d /etc/security/limits.d ]]; then
        grep -RHnEv '^[[:space:]]*(#|$)' /etc/security/limits.d/ 2>/dev/null || true
    fi
}

# ============================================================
# 12. SYSTEMD
# ============================================================

systemd_info() {
    section "12. SYSTEMD Y SERVICIOS"

    if ! cmd systemctl; then
        warn "Systemd no disponible."
        return
    fi

    value "Version:" "$(systemctl --version | head -1)"
    value "Servicios activos:" "$(systemctl list-units --type=service --state=running --no-legend 2>/dev/null | wc -l)"
    value "Servicios fallidos:" "$(systemctl --failed --no-legend 2>/dev/null | wc -l)"

    printf '\n  SERVICIOS HCR / BHTTP\n'
    systemctl list-units --all --type=service --no-legend 2>/dev/null |
        grep -Ei 'hcr-server|bhttp-server' || true

    printf '\n  SERVICIOS FALLIDOS\n'
    systemctl --failed --no-pager 2>/dev/null || true

    printf '\n  DEFAULT LIMITS\n'
    systemctl show --property=DefaultLimitNOFILE \
        --property=DefaultTasksMax \
        --property=DefaultTimeoutStartSec 2>/dev/null || true

    printf '\n  SYSTEMD MANAGER\n'
    systemctl show --no-pager \
        -p DefaultCPUAccounting \
        -p DefaultMemoryAccounting \
        -p DefaultTasksAccounting \
        -p DefaultLimitNOFILE \
        -p DefaultTasksMax 2>/dev/null || true

    printf '\n  SERVICIOS HCR / BHTTP: CONFIGURACION\n'
    while IFS= read -r service; do
        [[ -n "$service" ]] || continue
        printf '\n  %s\n' "$service"
        systemctl show "$service" --no-pager \
            -p ActiveState \
            -p SubState \
            -p MainPID \
            -p LimitNOFILE \
            -p TasksMax \
            -p CPUQuotaPerSecUSec \
            -p MemoryMax \
            -p MemoryHigh \
            -p OOMScoreAdjust \
            -p Nice \
            -p Restart \
            -p ExecStart 2>/dev/null || true
    done < <(
        systemctl list-units --all --type=service --no-legend 2>/dev/null |
        awk '{print $1}' | grep -E '^(hcr-server|bhttp-server).*\.service$' || true
    )
}

# ============================================================
# 13. PERSISTENT CONFIGURATION
# ============================================================

persistent_info() {
    section "13. CONFIGURACIONES PERSISTENTES"

    printf '\n  /etc/sysctl.conf\n'
    if [[ -r /etc/sysctl.conf ]]; then
        grep -nEv '^[[:space:]]*(#|$)' /etc/sysctl.conf || true
    fi

    printf '\n  /etc/sysctl.d/\n'
    if [[ -d /etc/sysctl.d ]]; then
        find /etc/sysctl.d -maxdepth 1 -type f -name '*.conf' -print 2>/dev/null |
        sort |
        while IFS= read -r file; do
            printf '\n  FILE: %s\n' "$file"
            grep -nEv '^[[:space:]]*(#|$)' "$file" || true
        done
    fi

    printf '\n  /usr/lib/sysctl.d Y /lib/sysctl.d\n'
    for dir in /usr/lib/sysctl.d /lib/sysctl.d /run/sysctl.d; do
        [[ -d "$dir" ]] || continue
        find "$dir" -maxdepth 1 -type f -name '*.conf' -print 2>/dev/null | sort
    done

    printf '\n  SYSCTL CONFIGURACIONES DE RED\n'
    for dir in /etc/NetworkManager/conf.d /etc/systemd/network; do
        [[ -d "$dir" ]] || continue
        find "$dir" -maxdepth 2 -type f -print 2>/dev/null
    done

    printf '\n  GRUB KERNEL PARAMETERS\n'
    if [[ -r /etc/default/grub ]]; then
        grep -nE 'GRUB_CMDLINE_LINUX|GRUB_DEFAULT' /etc/default/grub || true
    fi
}

# ============================================================
# 14. SECURITY
# ============================================================

security_info() {
    section "14. SEGURIDAD DEL SISTEMA"

    for key in \
        kernel.kptr_restrict \
        kernel.dmesg_restrict \
        kernel.randomize_va_space \
        kernel.yama.ptrace_scope \
        kernel.unprivileged_bpf_disabled \
        net.ipv4.tcp_syncookies \
        net.ipv4.conf.all.accept_redirects \
        net.ipv4.conf.all.send_redirects \
        net.ipv4.conf.all.accept_source_route \
        net.ipv4.conf.all.rp_filter \
        net.ipv6.conf.all.accept_redirects
    do
        sysctl "$key" 2>/dev/null || true
    done

    printf '\n  SECURITY STATUS\n'
    if cmd aa-status; then
        aa-status 2>/dev/null | head -20 || true
    fi

    if cmd sestatus; then
        sestatus 2>/dev/null || true
    fi

    printf '\n  SSH CONFIGURACION EFECTIVA\n'
    if cmd sshd; then
        sshd -T 2>/dev/null |
            grep -E '^(maxsessions|maxstartups|clientaliveinterval|clientalivecountmax|tcpkeepalive|usepam|permitrootlogin)' || true
    fi
}

# ============================================================
# 15. SERVICES / PROCESS RESOURCE
# ============================================================

process_info() {
    section "15. PROCESOS Y RECURSOS"

    printf '\n  PROCESOS\n'
    ps -eo pid,ppid,user,stat,ni,pri,%cpu,%mem,rss,comm --sort=-%cpu 2>/dev/null | head -25

    printf '\n  PROCESOS EN ESTADO D\n'
    ps -eo pid,stat,comm 2>/dev/null | awk '$2 ~ /^D/'

    printf '\n  PROCESOS ZOMBIE\n'
    ps -eo pid,ppid,stat,comm 2>/dev/null | awk '$3 ~ /^Z/'

    printf '\n  THREADS\n'
    value "Total threads:" "$(ps -eLf --no-headers 2>/dev/null | wc -l)"

    printf '\n  RUN QUEUE\n'
    cat /proc/loadavg 2>/dev/null

    printf '\n  SCHEDULER\n'
    for f in /proc/sys/kernel/sched_*; do
        [[ -r "$f" ]] || continue
        printf '  %-55s %s\n' "$f" "$(cat "$f" 2>/dev/null)"
    done
}

# ============================================================
# 16. DIAGNOSTIC FINDINGS
# ============================================================

diagnostics() {
    section "16. ANALISIS AUTOMATICO DE HALLAZGOS"

    local mem_total mem_available swap_total
    local file_max file_used conntrack_count conntrack_max
    local syn_backlog somaxconn backlog
    local retrans syncookies congestion qdisc

    mem_total=$(awk '/MemTotal:/ {print $2}' /proc/meminfo)
    mem_available=$(awk '/MemAvailable:/ {print $2}' /proc/meminfo)
    swap_total=$(awk '/SwapTotal:/ {print $2}' /proc/meminfo)

    if [[ "$mem_total" =~ ^[0-9]+$ && "$mem_available" =~ ^[0-9]+$ && "$mem_total" -gt 0 ]]; then
        local used_percent=$(( (mem_total - mem_available) * 100 / mem_total ))
        value "RAM utilizada aproximada:" "${used_percent}%"

        if (( used_percent >= 90 )); then
            bad "Uso de RAM critico."
        elif (( used_percent >= 80 )); then
            warn "Uso elevado de RAM."
        else
            ok "Disponibilidad de RAM sin alerta critica."
        fi
    fi

    if [[ "$swap_total" =~ ^[0-9]+$ ]] && (( swap_total > 0 )); then
        ok "SWAP habilitada."
    else
        warn "No se detecta SWAP habilitada."
    fi

    file_max=$(cat /proc/sys/fs/file-max 2>/dev/null || echo 0)
    read -r file_used _ < /proc/sys/fs/file-nr 2>/dev/null || file_used=0

    if [[ "$file_max" =~ ^[0-9]+$ && "$file_used" =~ ^[0-9]+$ && "$file_max" -gt 0 ]]; then
        value "File handles utilizados:" "$file_used / $file_max"
        if (( file_used * 100 / file_max >= 90 )); then
            warn "Descriptores de archivo cercanos al limite."
        fi
    fi

    conntrack_count=$(cat /proc/sys/net/netfilter/nf_conntrack_count 2>/dev/null || echo 0)
    conntrack_max=$(cat /proc/sys/net/netfilter/nf_conntrack_max 2>/dev/null || echo 0)

    if [[ "$conntrack_count" =~ ^[0-9]+$ && "$conntrack_max" =~ ^[0-9]+$ && "$conntrack_max" -gt 0 ]]; then
        value "Conntrack:" "$conntrack_count / $conntrack_max"
        if (( conntrack_count * 100 / conntrack_max >= 85 )); then
            warn "Conntrack se encuentra cerca de su limite."
        else
            ok "Conntrack con margen disponible."
        fi
    fi

    syn_backlog=$(sysctl -n net.ipv4.tcp_max_syn_backlog 2>/dev/null || echo N/D)
    somaxconn=$(sysctl -n net.core.somaxconn 2>/dev/null || echo N/D)
    backlog=$(sysctl -n net.core.netdev_max_backlog 2>/dev/null || echo N/D)

    value "TCP SYN backlog:" "$syn_backlog"
    value "Socket backlog:" "$somaxconn"
    value "Network backlog:" "$backlog"

    congestion=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo N/D)
    qdisc=$(sysctl -n net.core.default_qdisc 2>/dev/null || echo N/D)

    value "Congestion control:" "$congestion"
    value "Default qdisc:" "$qdisc"

    if [[ "$congestion" == bbr ]]; then
        ok "BBR aparece como algoritmo congestion control activo."
    else
        warn "El algoritmo TCP activo no es BBR."
    fi

    if [[ "$qdisc" == fq ]]; then
        ok "Qdisc por defecto configurado como fq."
    else
        warn "La qdisc por defecto no aparece como fq."
    fi

    syncookies=$(sysctl -n net.ipv4.tcp_syncookies 2>/dev/null || echo N/D)
    value "TCP SYN cookies:" "$syncookies"

    printf '\n  CONTADORES DE RETRANSMISION\n'
    if [[ -r /proc/net/snmp ]]; then
        awk '
        /^Tcp:/ {
            if (!header) {
                for (i=1; i<=NF; i++) names[i]=$i
                header=1
            } else {
                for (i=1; i<=NF; i++)
                    if (names[i] == "RetransSegs")
                        print "  RetransSegs:", $i
                header=0
            }
        }' /proc/net/snmp
    fi

    printf '\n  ERRORES DE INTERFACES\n'
    for f in /sys/class/net/*/statistics/{rx_errors,tx_errors,rx_dropped,tx_dropped}; do
        [[ -r "$f" ]] || continue
        local n
        n=$(cat "$f")
        if [[ "$n" =~ ^[0-9]+$ ]] && (( n > 0 )); then
            warn "${f%/statistics/*}: ${f##*/} = $n"
        fi
    done

    printf '\n  SERVICIOS FALLIDOS\n'
    if cmd systemctl; then
        local failed
        failed=$(systemctl --failed --no-legend 2>/dev/null | wc -l)
        if (( failed > 0 )); then
            warn "Se detectan servicios fallidos."
        else
            ok "No se detectan servicios fallidos."
        fi
    fi

    printf '\n  NOTA TECNICA\n'
    info "Los valores elevados no son necesariamente optimos."
    info "La configuracion adecuada depende de RAM, CPU, NIC y carga."
    info "Las retransmisiones y errores deben evaluarse en intervalos."
    info "BBR y fq deben verificarse tambien en la interfaz real."
}

# ============================================================
# 17. SUMMARY
# ============================================================

summary() {
    section "17. RESUMEN DEL SISTEMA"

    value "Sistema:" "$(uname -s)"
    value "Kernel:" "$(uname -r)"
    value "CPU:" "$(nproc)"
    value "RAM:" "$(free -h | awk '/Mem:/ {print $2}')"
    value "SWAP:" "$(free -h | awk '/Swap:/ {print $2}')"
    value "Disco raiz:" "$(df -h / | awk 'NR==2 {print $2 " total / " $4 " disponible"}')"
    value "TCP:" "$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)"
    value "QDISC:" "$(sysctl -n net.core.default_qdisc 2>/dev/null)"
    value "SOMAXCONN:" "$(sysctl -n net.core.somaxconn 2>/dev/null)"
    value "BACKLOG:" "$(sysctl -n net.core.netdev_max_backlog 2>/dev/null)"
    value "FD MAX:" "$(sysctl -n fs.file-max 2>/dev/null)"

    printf '\n'
    line
    printf '%b\n' "${GREEN}       AUDITORIA DEL SISTEMA COMPLETADA${RESET}"
    printf '%b\n' "${WHITE}       EPRO DEV - SYSTEM PERFORMANCE${RESET}"
    line
    printf '\n'
}

# ============================================================
# MAIN
# ============================================================

main() {
    if [[ "${EUID}" -ne 0 ]]; then
        printf '%b\n' "${YELLOW}Ejecuta este script como root para obtener una auditoria completa.${RESET}"
        printf '  sudo bash %s\n' "$0"
        exit 1
    fi

    header

    system_info
    cpu_info
    memory_info
    storage_info
    kernel_info
    tcp_info
    socket_info
    firewall_info
    network_info
    limits_info
    systemd_info
    persistent_info
    security_info
    process_info
    diagnostics
    summary
}

main "$@"
