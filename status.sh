
#!/usr/bin/env bash

# ============================================================
#          VPS TRAFFIC & SYSTEM DIAGNOSTIC
#                   EPRO DEV
# ============================================================
#
# ANALISIS INTEGRAL:
#   - Usuarios y sesiones
#   - CPU y carga del sistema
#   - RAM y SWAP
#   - Trafico de red en tiempo real
#   - Errores y paquetes descartados
#   - Estadisticas TCP y retransmisiones
#   - Conexiones y puertos
#   - Procesos y servicios
#   - Almacenamiento
#   - Kernel y limites
#   - Conntrack
#   - Firewall y rutas
#
# COMPATIBILIDAD:
#   Debian / Ubuntu / Linux
#
# REQUISITOS:
#   Bash, awk, grep, ps, df
#
# SEGURIDAD:
#   Solo lectura. No modifica el sistema.
#
# ============================================================

set -u
umask 077

VERSION="1.0.0"
INTERVAL=2

# ------------------------------------------------------------
# COLORES
# ------------------------------------------------------------

if [[ -t 1 && "${TERM:-}" != "dumb" ]]; then
    R='\033[0m'
    B='\033[1m'
    D='\033[2m'
    RED='\033[1;31m'
    GREEN='\033[1;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[1;34m'
    CYAN='\033[1;36m'
    WHITE='\033[1;37m'
else
    R='' B='' D='' RED='' GREEN=''
    YELLOW='' BLUE='' CYAN='' WHITE=''
fi

# ------------------------------------------------------------
# FUNCIONES GENERALES
# ------------------------------------------------------------

have() {
    command -v "$1" >/dev/null 2>&1
}

line() {
    printf '%b\n' "${D}────────────────────────────────────────────────────────${R}"
}

title() {
    printf '\n%b\n' "${CYAN}${B}◆  $1${R}"
    line
}

info() {
    printf '  %-27s %b\n' "$1" "$2"
}

ok() {
    printf '  %b %s\n' "${GREEN}✓${R}" "$1"
}

warn() {
    printf '  %b %s\n' "${YELLOW}!${R}" "$1"
}

bad() {
    printf '  %b %s\n' "${RED}✗${R}" "$1"
}

value() {
    printf '%b\n' "${WHITE}$1${R}"
}

run() {
    if have "$1"; then
        shift
        "$@" 2>/dev/null || true
    else
        printf '  Comando no disponible: %s\n' "$1"
    fi
}

bytes_human() {
    awk -v n="${1:-0}" 'BEGIN {
        split("B KB MB GB TB",u," ")
        i=1
        while(n>=1024 && i<5){n/=1024;i++}
        printf "%.2f %s",n,u[i]
    }'
}

# ------------------------------------------------------------
# ENCABEZADO
# ------------------------------------------------------------

clear 2>/dev/null || true

printf '\n'
printf '  %bVPS TRAFFIC & SYSTEM DIAGNOSTIC%b\n' "$WHITE$B" "$R"
printf '  %bE P R O   D E V%b\n' "$CYAN" "$R"
printf '  %bVERSION %s%b\n' "$D" "$VERSION" "$R"
printf '\n'

info "FECHA" "$(date '+%Y-%m-%d %H:%M:%S %Z' 2>/dev/null)"
info "HOSTNAME" "$(hostname 2>/dev/null || echo N/D)"
info "USUARIO" "$(id -un 2>/dev/null || echo N/D)"
info "PERMISOS" "$([[ ${EUID:-$(id -u)} -eq 0 ]] && echo ROOT || echo USUARIO)"
info "ARQUITECTURA" "$(uname -m 2>/dev/null)"
info "KERNEL" "$(uname -r 2>/dev/null)"
info "UPTIME" "$(uptime -p 2>/dev/null || uptime 2>/dev/null)"

if [[ -r /etc/os-release ]]; then
    . /etc/os-release
    info "DISTRIBUCION" "${PRETTY_NAME:-Linux}"
fi

# ------------------------------------------------------------
# 1. CPU
# ------------------------------------------------------------

title "01. ANALISIS DE PROCESADOR"

CORES=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)
LOAD=$(awk '{print $1" / "$2" / "$3}' /proc/loadavg 2>/dev/null || echo N/D)

info "NUCLEOS DISPONIBLES" "$CORES"
info "CARGA 1 / 5 / 15 MIN" "$LOAD"

if [[ -r /proc/stat ]]; then
    read -r _ u1 n1 s1 i1 w1 irq1 sirq1 st1 _ < /proc/stat
    idle1=$((i1 + w1))
    total1=$((u1+n1+s1+i1+w1+irq1+sirq1+st1))

    sleep "$INTERVAL"

    read -r _ u2 n2 s2 i2 w2 irq2 sirq2 st2 _ < /proc/stat
    idle2=$((i2+w2))
    total2=$((u2+n2+s2+i2+w2+irq2+sirq2+st2))

    dt=$((total2-total1))
    di=$((idle2-idle1))

    if (( dt > 0 )); then
        CPU_USAGE=$(( (100*(dt-di))/dt ))
        info "USO CPU PROMEDIO" "${CPU_USAGE}%"

        (( CPU_USAGE >= 90 )) && warn "CPU con utilizacion elevada"
        (( CPU_USAGE < 90 )) && ok "CPU dentro del umbral de observacion"
    fi
fi

printf '\n  PROCESOS DE MAYOR CONSUMO CPU\n'
run ps -eo pid,ppid,user,%cpu,%mem,stat,comm --sort=-%cpu |
    head -n 9

# ------------------------------------------------------------
# 2. MEMORIA
# ------------------------------------------------------------

title "02. MEMORIA RAM Y SWAP"

if [[ -r /proc/meminfo ]]; then
    awk '
    /^MemTotal:/ {t=$2}
    /^MemAvailable:/ {a=$2}
    /^MemFree:/ {f=$2}
    /^Cached:/ {c=$2}
    /^Buffers:/ {b=$2}
    /^SwapTotal:/ {st=$2}
    /^SwapFree:/ {sf=$2}
    END {
        if(t>0) {
            printf "  RAM TOTAL:        %.2f GB\n",t/1048576
            printf "  RAM DISPONIBLE:   %.2f GB\n",a/1048576
            printf "  RAM LIBRE:        %.2f GB\n",f/1048576
            printf "  CACHE:            %.2f GB\n",c/1048576
            printf "  BUFFERS:          %.2f GB\n",b/1048576
            printf "  RAM UTILIZADA:    %.1f%%\n",(t-a)*100/t
            if(a/t<0.10) print "  ALERTA: RAM DISPONIBLE INFERIOR AL 10%"
        }
        if(st>0) {
            printf "  SWAP TOTAL:       %.2f GB\n",st/1048576
            printf "  SWAP UTILIZADA:   %.2f GB\n",(st-sf)/1048576
            printf "  SWAP USADA:       %.1f%%\n",(st-sf)*100/st
        } else {
            print "  SWAP: NO CONFIGURADA"
        }
    }' 
fi

printf '\n  PROCESOS DE MAYOR CONSUMO RAM\n'
run ps -eo pid,user,%mem,rss,stat,comm --sort=-%mem |
    head -n 9

if [[ -r /proc/vmstat ]]; then
    printf '\n  ACTIVIDAD DE MEMORIA VIRTUAL\n'
    awk '
    /pswpin|pswpout|pgmajfault|oom_kill/ {
        print "  " $1 ": " $2
    }' /proc/vmstat
fi

# ------------------------------------------------------------
# 3. USUARIOS Y SESIONES
# ------------------------------------------------------------

title "03. USUARIOS Y ACTIVIDAD"

info "SESIONES ACTIVAS" "$(who 2>/dev/null | wc -l)"
info "USUARIOS CONECTADOS" "$(who 2>/dev/null | awk '{print $1}' | sort -u | wc -l)"

printf '\n  SESIONES ACTUALES\n'
run who

printf '\n  ACTIVIDAD DEL SISTEMA\n'
run w

printf '\n  PROCESOS POR USUARIO\n'
ps -eo user= 2>/dev/null |
    awk '{c[$1]++}
    END {
        for(u in c) printf "  %-20s %d procesos\n",u,c[u]
    }' | sort -k3nr | head -n 15

printf '\n  PROCESOS DE USUARIOS\n'
run ps -eo user,pid,ppid,%cpu,%mem,stat,comm --sort=-%cpu |
    head -n 16

# ------------------------------------------------------------
# 4. INTERFACES Y TRAFICO DE RED
# ------------------------------------------------------------

title "04. TRAFICO DE RED"

if [[ -r /proc/net/dev ]]; then

    printf '\n  CONTADORES ACUMULADOS DE INTERFACES\n'

    awk -F'[: ]+' 'NR>2 {
        iface=$2
        if(iface!="") {
            printf "  %-12s RX: %s bytes | TX: %s bytes\n",
            iface,$3,$11
            printf "  %-12s RX errores: %s | RX drops: %s | TX errores: %s | TX drops: %s\n",
            "",$4,$5,$12,$13
        }
    }' /proc/net/dev

    printf '\n  VELOCIDAD APROXIMADA DURANTE %s SEGUNDOS\n' "$INTERVAL"

    TMP1=$(mktemp 2>/dev/null || echo "")
    TMP2=$(mktemp 2>/dev/null || echo "")

    if [[ -n "$TMP1" && -n "$TMP2" ]]; then
        awk -F'[: ]+' 'NR>2 && $2!="" {
            print $2,$3,$11
        }' /proc/net/dev > "$TMP1"

        sleep "$INTERVAL"

        awk -F'[: ]+' 'NR>2 && $2!="" {
            print $2,$3,$11
        }' /proc/net/dev > "$TMP2"

        awk -v t="$INTERVAL" '
        NR==FNR {
            rx[$1]=$2
            tx[$1]=$3
            next
        }
        {
            drx=$2-rx[$1]
            dtx=$3-tx[$1]
            if(drx<0)drx=0
            if(dtx<0)dtx=0
            printf "  %-12s RX: %.2f KB/s | TX: %.2f KB/s\n",
            $1,drx/1024/t,dtx/1024/t
        }' "$TMP1" "$TMP2"

        rm -f "$TMP1" "$TMP2"
    fi
fi

# ------------------------------------------------------------
# 5. TCP Y RETRANSMISIONES
# ------------------------------------------------------------

title "05. ESTADISTICAS TCP"

if [[ -r /proc/net/snmp ]]; then
    awk '
    /^Tcp:/ {
        if(!header) {
            for(i=2;i<=NF;i++) h[i]=$i
            header=1
        } else {
            for(i=2;i<=NF;i++) v[h[i]]=$i
            header=0
        }
    }
    END {
        split("ActiveOpens PassiveOpens AttemptFails EstabResets CurrEstab InSegs OutSegs RetransSegs",a," ")
        for(i in a)
            if(a[i] in v)
                printf "  %-20s %s\n",a[i],v[a[i]]
    }' /proc/net/snmp
fi

if [[ -r /proc/net/netstat ]]; then
    printf '\n  EXTENSIONES TCP\n'
    awk '
    /^TcpExt:/ {
        if(!h) {
            for(i=2;i<=NF;i++) names[i]=$i
            h=1
        } else {
            for(i=2;i<=NF;i++) {
                if(names[i] ~ /ListenDrops|ListenOverflows|TCPAbortOn|TCPSynRetrans|TCPTimeouts/)
                    printf "  %-25s %s\n",names[i],$i
            }
            h=0
        }
    }' /proc/net/netstat
fi

# ------------------------------------------------------------
# 6. CONEXIONES Y PUERTOS
# ------------------------------------------------------------

title "06. CONEXIONES Y SOCKETS"

if have ss; then
    printf '\n  RESUMEN DE SOCKETS\n'
    ss -s 2>/dev/null || true

    printf '\n  CONEXIONES TCP ESTABLECIDAS\n'
    EST=$(ss -Htan state established 2>/dev/null | wc -l)
    info "ESTABLISHED" "$EST"

    printf '\n  DISTRIBUCION TCP\n'
    ss -Htan 2>/dev/null |
        awk '{c[$1]++}
        END {
            for(s in c) printf "  %-20s %d\n",s,c[s]
        }' | sort

    printf '\n  PUERTOS EN ESCUCHA\n'
    ss -lntup 2>/dev/null | head -n 35

    printf '\n  CONEXIONES ESTABLECIDAS Y PROCESOS\n'
    ss -tnp state established 2>/dev/null | head -n 25

else
    warn "ss no esta instalado; comprobando netstat"
    run netstat -tulpen
fi

# ------------------------------------------------------------
# 7. PROCESOS Y SERVICIOS
# ------------------------------------------------------------

title "07. SERVICIOS Y PROCESOS"

if have systemctl; then
    info "SERVICIOS ACTIVOS" \
        "$(systemctl list-units --type=service --state=running --no-legend 2>/dev/null | wc -l)"

    info "SERVICIOS FALLIDOS" \
        "$(systemctl --failed --type=service --no-legend 2>/dev/null | wc -l)"

    printf '\n  SERVICIOS FALLIDOS\n'
    systemctl --failed --type=service --no-pager 2>/dev/null || true
fi

printf '\n  PROCESOS CON MAYOR CONSUMO\n'
run ps -eo pid,ppid,user,%cpu,%mem,stat,etime,comm --sort=-%cpu |
    head -n 16

# ------------------------------------------------------------
# 8. ALMACENAMIENTO
# ------------------------------------------------------------

title "08. DISCO Y ALMACENAMIENTO"

printf '\n  ESPACIO DISPONIBLE\n'
run df -hT -x tmpfs -x devtmpfs

printf '\n  INODOS\n'
run df -i -x tmpfs -x devtmpfs

if have iostat; then
    printf '\n  ACTIVIDAD DE DISCOS\n'
    iostat -xz 1 2 2>/dev/null | tail -n 20
else
    warn "iostat no disponible; metricas I/O avanzadas no disponibles"
fi

if [[ -r /proc/diskstats ]]; then
    printf '\n  CONTADORES DE DISPOSITIVOS\n'
    awk '{
        printf "  %-12s lecturas: %s | escrituras: %s\n",
        $3,$4,$8
    }' /proc/diskstats | head -n 15
fi

# ------------------------------------------------------------
# 9. KERNEL Y LIMITES
# ------------------------------------------------------------

title "09. KERNEL Y LIMITES"

for key in \
    net.core.somaxconn \
    net.core.netdev_max_backlog \
    net.ipv4.tcp_max_syn_backlog \
    net.ipv4.ip_local_port_range \
    net.ipv4.tcp_fin_timeout \
    net.ipv4.tcp_max_tw_buckets \
    fs.file-max
do
    val=$(sysctl -n "$key" 2>/dev/null || echo N/D)
    info "$key" "$val"
done

printf '\n  LIMITES DEL PROCESO ACTUAL\n'
ulimit -a 2>/dev/null | head -n 15

printf '\n  CONNTRACK\n'

if [[ -r /proc/sys/net/netfilter/nf_conntrack_count ]]; then
    CURRENT=$(cat /proc/sys/net/netfilter/nf_conntrack_count)
    MAXIMUM=$(cat /proc/sys/net/netfilter/nf_conntrack_max 2>/dev/null || echo 0)

    info "CONEXIONES TRACKED" "$CURRENT"
    info "MAXIMO CONNTRACK" "$MAXIMUM"

    if (( MAXIMUM > 0 )); then
        PERCENT=$((CURRENT*100/MAXIMUM))
        info "USO CONNTRACK" "${PERCENT}%"
        (( PERCENT >= 90 )) && warn "Conntrack cerca del limite"
    fi
else
    warn "Conntrack no disponible o modulo no expuesto"
fi

# ------------------------------------------------------------
# 10. CONFIGURACION DE RED
# ------------------------------------------------------------

title "10. INTERFACES Y RUTAS"

if have ip; then
    printf '\n  DIRECCIONES IP\n'
    ip -brief address 2>/dev/null || ip address 2>/dev/null

    printf '\n  RUTAS\n'
    ip route 2>/dev/null

    printf '\n  ESTADISTICAS DE INTERFACES\n'
    ip -s link 2>/dev/null | head -n 55

    printf '\n  COLAS DE RED\n'
    tc qdisc show 2>/dev/null || true
fi

# ------------------------------------------------------------
# 11. DNS Y CONECTIVIDAD
# ------------------------------------------------------------

title "11. DNS Y CONECTIVIDAD"

if [[ -r /etc/resolv.conf ]]; then
    printf '\n  CONFIGURACION DNS\n'
    grep -E '^[[:space:]]*nameserver|^[[:space:]]*search' \
        /etc/resolv.conf 2>/dev/null || true
fi

if have getent; then
    printf '\n  RESOLUCION DNS\n'
    if getent ahosts deb.debian.org >/dev/null 2>&1; then
        ok "Resolucion DNS funcional"
    else
        warn "No se pudo resolver deb.debian.org"
    fi
fi

if have ping; then
    printf '\n  CONECTIVIDAD IP\n'
    ping -c 2 -W 2 1.1.1.1 2>/dev/null |
        tail -n 3 || warn "Sin respuesta ICMP o ICMP bloqueado"
fi

# ------------------------------------------------------------
# 12. FIREWALL
# ------------------------------------------------------------

title "12. FIREWALL"

if have nft; then
    info "NFTABLES" "$(nft list tables 2>/dev/null | wc -l) tablas"
fi

if have iptables; then
    info "IPTABLES" "$(iptables -S 2>/dev/null | wc -l) reglas"
fi

if have ufw; then
    info "UFW" "$(ufw status 2>/dev/null | head -n 1)"
fi

# ------------------------------------------------------------
# 13. ERRORES DEL SISTEMA
# ------------------------------------------------------------

title "13. EVENTOS Y ERRORES"

if have journalctl; then
    printf '\n  ULTIMOS ERRORES DEL SISTEMA\n'
    journalctl -p err -n 20 --no-pager -o short-iso 2>/dev/null |
        tail -n 20 || true
else
    warn "Journalctl no disponible"
fi

if have dmesg; then
    printf '\n  EVENTOS DEL KERNEL\n'
    dmesg 2>/dev/null |
        grep -Ei 'oom|out of memory|killed process|blocked for more than|NETDEV WATCHDOG|I/O error|link is down|reset' |
        tail -n 15 || true
fi

# ------------------------------------------------------------
# 14. RESUMEN DE DIAGNOSTICO
# ------------------------------------------------------------

title "14. INDICADORES DE RENDIMIENTO"

WARNINGS=0

if [[ -n "${CPU_USAGE:-}" ]] && (( CPU_USAGE >= 90 )); then
    bad "CPU con utilizacion igual o superior al 90%"
    WARNINGS=$((WARNINGS+1))
fi

if [[ -r /proc/meminfo ]]; then
    MEM_RESULT=$(awk '
    /^MemTotal:/ {t=$2}
    /^MemAvailable:/ {a=$2}
    END {
        if(t>0) printf "%d",a*100/t
        else print 100
    }' /proc/meminfo)

    if (( MEM_RESULT < 10 )); then
        bad "RAM disponible inferior al 10%"
        WARNINGS=$((WARNINGS+1))
    fi
fi

if [[ -r /proc/loadavg ]]; then
    LOAD1=$(awk '{print int($1)}' /proc/loadavg)
    if (( LOAD1 > CORES )); then
        warn "Carga del sistema superior al numero de nucleos"
        WARNINGS=$((WARNINGS+1))
    fi
fi

DISK_RESULT=$(df -P -x tmpfs -x devtmpfs / 2>/dev/null |
    awk 'NR==2 {gsub("%","",$5);print $5}')

if [[ "$DISK_RESULT" =~ ^[0-9]+$ ]] && (( DISK_RESULT >= 90 )); then
    bad "Disco raiz con ocupacion igual o superior al 90%"
    WARNINGS=$((WARNINGS+1))
fi

if [[ "$WARNINGS" -eq 0 ]]; then
    ok "No se detectaron alertas en los umbrales basicos"
else
    warn "Indicadores que requieren investigacion: $WARNINGS"
fi

printf '\n'
line
printf '  %bDIAGNOSTICO FINALIZADO%b\n' "$GREEN$B" "$R"
printf '  %bNo se realizaron modificaciones al sistema.%b\n' "$D" "$R"
printf '  %bE P R O   D E V%b\n' "$CYAN" "$R"
line
printf '\n'
