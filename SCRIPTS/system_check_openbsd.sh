#!/usr/local/bin/bash
#
# system_check.sh (OpenBSD version)
# Automated check of: RAM usage, Swap, Storage space, Uptime, and Load Average
# Emails a daily report using OpenBSD's native mail/smtpd.
#
# NOTE: OpenBSD base does NOT include bash by default. Install it first:
#   doas pkg_add bash
# Then run this script with: bash system_check.sh
#
# Author: erickmtei

# ============ CONFIGURATION ============
EMAIL_TO="yourname@example.com"          # <-- badilisha na email yako
HOSTNAME_LABEL=$(hostname)
REPORT_FILE="/tmp/system_check_report_$(date +%Y%m%d_%H%M%S).txt"

RAM_THRESHOLD=85     # %
SWAP_THRESHOLD=50    # %
DISK_THRESHOLD=85    # %
# ========================================

{
echo "============================================="
echo "   SERVER STATUS REPORT (OpenBSD)"
echo "   Server   : $HOSTNAME_LABEL"
echo "   Date/Time: $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================="

# --- UPTIME & LOAD AVERAGE ---
# OpenBSD uptime format: "9:15AM  up 12 days, 22:06, 2 users, load averages: 0.63, 0.64, 0.56"
echo -e "\n--- UPTIME & LOAD AVERAGE ---"
UPTIME_RAW=$(uptime)
UPTIME_INFO=$(echo "$UPTIME_RAW" | sed -E 's/^.*up ([^,]+, [^,]+),.*/\1/')
LOAD_AVG=$(echo "$UPTIME_RAW" | sed -E 's/.*load averages?: //')
CPU_CORES=$(sysctl -n hw.ncpu)

echo "Uptime         : $UPTIME_INFO"
echo "Load Average   : $LOAD_AVG   (CPU cores: $CPU_CORES)"

LOAD_1MIN=$(echo "$LOAD_AVG" | awk -F',' '{print $1}' | tr -d ' ')
LOAD_EXCEEDS=$(echo "$LOAD_1MIN > $CPU_CORES" | bc -l 2>/dev/null)
if [ "$LOAD_EXCEEDS" == "1" ]; then
    echo "WARNING: Load average exceeds the number of CPU cores!"
else
    echo "Load average looks fine."
fi

# --- RAM USAGE ---
# OpenBSD has no 'free' command; we use sysctl + vmstat
echo -e "\n--- RAM USAGE ---"
PAGESIZE=$(sysctl -n hw.pagesize)
TOTAL_MEM_BYTES=$(sysctl -n hw.physmem)
FREE_PAGES=$(vmstat -s | awk '/pages free/ {print $1}')
FREE_MEM_BYTES=$(( FREE_PAGES * PAGESIZE ))
USED_MEM_BYTES=$(( TOTAL_MEM_BYTES - FREE_MEM_BYTES ))

TOTAL_MEM=$(( TOTAL_MEM_BYTES / 1024 / 1024 ))
USED_MEM=$(( USED_MEM_BYTES / 1024 / 1024 ))
FREE_MEM=$(( FREE_MEM_BYTES / 1024 / 1024 ))
MEM_PERCENT=$(awk "BEGIN {printf \"%.1f\", ($USED_MEM/$TOTAL_MEM)*100}")

echo "Total RAM      : ${TOTAL_MEM} MB"
echo "Used           : ${USED_MEM} MB (${MEM_PERCENT}%)"
echo "Free           : ${FREE_MEM} MB"

if (( $(echo "$MEM_PERCENT > $RAM_THRESHOLD" | bc -l) )); then
    echo "WARNING: RAM usage is above ${RAM_THRESHOLD}%!"
else
    echo "RAM usage is fine."
fi

# --- SWAP USAGE ---
# swapctl -l columns: Device 1K-blocks Used Avail Capacity Priority
echo -e "\n--- SWAP USAGE ---"
SWAP_DATA=$(swapctl -l 2>/dev/null | tail -n +2)

if [ -n "$SWAP_DATA" ]; then
    TOTAL_SWAP_KB=$(echo "$SWAP_DATA" | awk '{sum+=$2} END{print sum+0}')
    USED_SWAP_KB=$(echo "$SWAP_DATA" | awk '{sum+=$3} END{print sum+0}')
    TOTAL_SWAP=$(( TOTAL_SWAP_KB / 1024 ))
    USED_SWAP=$(( USED_SWAP_KB / 1024 ))

    if [ "$TOTAL_SWAP" -gt 0 ]; then
        SWAP_PERCENT=$(awk "BEGIN {printf \"%.1f\", ($USED_SWAP/$TOTAL_SWAP)*100}")
        echo "Total Swap     : ${TOTAL_SWAP} MB"
        echo "Used           : ${USED_SWAP} MB (${SWAP_PERCENT}%)"
        if (( $(echo "$SWAP_PERCENT > $SWAP_THRESHOLD" | bc -l) )); then
            echo "WARNING: Swap usage is above ${SWAP_THRESHOLD}%! This usually means RAM is not enough."
        else
            echo "Swap usage is fine."
        fi
    else
        echo "No swap configured."
    fi
else
    echo "No swap configured."
fi

# --- STORAGE / DISK ---
echo -e "\n--- STORAGE (DISK) USAGE ---"
df -h | grep -v -E '^Filesystem' | while read -r FS SIZE USED AVAIL CAP MOUNT; do
    CAP_NUM=$(echo "$CAP" | tr -d '%')
    LINE=$(printf "%-20s Size: %-8s Used: %-8s Avail: %-8s Used%%: %-5s" "$MOUNT" "$SIZE" "$USED" "$AVAIL" "$CAP")
    if [ "$CAP_NUM" -ge "$DISK_THRESHOLD" ] 2>/dev/null; then
        echo "$LINE <-- WARNING: Disk usage above ${DISK_THRESHOLD}%!"
    else
        echo "$LINE OK"
    fi
done

# --- TOP PROCESSES ---
# BSD ps uses -axo (no GNU --sort), so we pipe to sort manually
echo -e "\n--- TOP 5 PROCESSES BY RAM ---"
echo "PID   USER      %CPU  %MEM  COMMAND"
ps -axo pid,user,%cpu,%mem,comm | tail -n +2 | sort -rn -k4 | head -n 5

echo -e "\n--- TOP 5 PROCESSES BY CPU ---"
echo "PID   USER      %CPU  %MEM  COMMAND"
ps -axo pid,user,%cpu,%mem,comm | tail -n +2 | sort -rn -k3 | head -n 5

echo -e "\n============================================="
echo "   END OF REPORT"
echo "============================================="
echo "Script created by: erickmtei"

} > "$REPORT_FILE"

# ============ TUMA EMAIL ============
# OpenBSD tayari ina 'mail' na OpenSMTPD (smtpd) kwenye base system.
# Hakikisha /etc/mail/smtpd.conf imewekwa kuruhusu relay kwenda mail server ya kampuni
# (angalia maelekezo yanayofuata baada ya faili hii).
SUBJECT="[$HOSTNAME_LABEL] Daily System Report - $(date '+%Y-%m-%d')"
mail -s "$SUBJECT" "$EMAIL_TO" < "$REPORT_FILE"

# rm -f "$REPORT_FILE"   # ondoa # ukitaka kufuta faili la muda baada ya kutuma
