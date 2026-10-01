#!/bin/bash
#
# system_check.sh
# Script to automate checking: RAM usage, Storage space, Uptime, and Load Average
# Usage: bash system_check.sh
# You can also schedule it with cron to run periodically (see bottom of file)
#
# Author: erickmtei

# --- Colors for nicer terminal output ---
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# --- Thresholds (alert levels) - adjust to your needs ---
RAM_THRESHOLD=85     # %
SWAP_THRESHOLD=50    # %
DISK_THRESHOLD=85    # %

echo -e "${CYAN}=============================================${NC}"
echo -e "${CYAN}   SERVER STATUS REPORT - $(date '+%Y-%m-%d %H:%M:%S')${NC}"
echo -e "${CYAN}=============================================${NC}"

# ---------------------------------------------------
# 1. UPTIME AND LOAD AVERAGE (same as shown at the top of htop)
# ---------------------------------------------------
echo -e "\n${CYAN}--- UPTIME & LOAD AVERAGE ---${NC}"

UPTIME_INFO=$(uptime -p)               # e.g. "up 12 days, 22 hours, 6 minutes"
LOAD_AVG=$(uptime | awk -F'load average:' '{print $2}' | sed 's/^ *//')
CPU_CORES=$(nproc)

echo "Uptime         : $UPTIME_INFO"
echo "Load Average   : $LOAD_AVG   (CPU cores: $CPU_CORES)"

# Check if the 1-minute load average exceeds the number of CPU cores -> server under stress
LOAD_1MIN=$(echo "$LOAD_AVG" | awk -F',' '{print $1}' | tr -d ' ')
LOAD_EXCEEDS=$(echo "$LOAD_1MIN > $CPU_CORES" | bc -l 2>/dev/null)
if [ "$LOAD_EXCEEDS" == "1" ]; then
    echo -e "${RED}WARNING: Load average exceeds the number of CPU cores!${NC}"
else
    echo -e "${GREEN}Load average looks fine.${NC}"
fi

# ---------------------------------------------------
# 2. RAM AND SWAP USAGE
# ---------------------------------------------------
echo -e "\n${CYAN}--- RAM USAGE ---${NC}"

read -r TOTAL_MEM USED_MEM FREE_MEM SHARED_MEM CACHE_MEM AVAIL_MEM <<< $(free -m | awk '/^Mem:/ {print $2, $3, $4, $5, $6, $7}')
MEM_PERCENT=$(awk "BEGIN {printf \"%.1f\", ($USED_MEM/$TOTAL_MEM)*100}")

echo "Total RAM      : ${TOTAL_MEM} MB"
echo "Used           : ${USED_MEM} MB (${MEM_PERCENT}%)"
echo "Available      : ${AVAIL_MEM} MB"

if (( $(echo "$MEM_PERCENT > $RAM_THRESHOLD" | bc -l) )); then
    echo -e "${RED}WARNING: RAM usage is above ${RAM_THRESHOLD}%!${NC}"
else
    echo -e "${GREEN}RAM usage is fine.${NC}"
fi

echo -e "\n${CYAN}--- SWAP USAGE ---${NC}"
read -r TOTAL_SWAP USED_SWAP <<< $(free -m | awk '/^Swap:/ {print $2, $3}')

if [ "$TOTAL_SWAP" -gt 0 ]; then
    SWAP_PERCENT=$(awk "BEGIN {printf \"%.1f\", ($USED_SWAP/$TOTAL_SWAP)*100}")
    echo "Total Swap     : ${TOTAL_SWAP} MB"
    echo "Used           : ${USED_SWAP} MB (${SWAP_PERCENT}%)"

    if (( $(echo "$SWAP_PERCENT > $SWAP_THRESHOLD" | bc -l) )); then
        echo -e "${RED}WARNING: Swap usage is above ${SWAP_THRESHOLD}%! This usually means RAM is not enough.${NC}"
    else
        echo -e "${GREEN}Swap usage is fine.${NC}"
    fi
else
    echo "No swap configured."
fi

# ---------------------------------------------------
# 3. STORAGE / DISK SPACE
# ---------------------------------------------------
echo -e "\n${CYAN}--- STORAGE (DISK) USAGE ---${NC}"

df -h --output=target,size,used,avail,pcent -x tmpfs -x devtmpfs | tail -n +2 | while read -r MOUNT SIZE USED AVAIL PCENT; do
    PCENT_NUM=$(echo "$PCENT" | tr -d '%')
    printf "%-20s Size: %-8s Used: %-8s Avail: %-8s Used%%: %-5s" "$MOUNT" "$SIZE" "$USED" "$AVAIL" "$PCENT"
    if [ "$PCENT_NUM" -ge "$DISK_THRESHOLD" ]; then
        echo -e "${RED} <-- WARNING: Disk usage above ${DISK_THRESHOLD}%!${NC}"
    else
        echo -e "${GREEN} OK${NC}"
    fi
done

# ---------------------------------------------------
# 4. TOP PROCESSES BY RAM/CPU (like the process list in htop)
# ---------------------------------------------------
echo -e "\n${CYAN}--- TOP 5 PROCESSES BY RAM ---${NC}"
ps -eo pid,user,%mem,%cpu,comm --sort=-%mem | head -n 6

echo -e "\n${CYAN}--- TOP 5 PROCESSES BY CPU ---${NC}"
ps -eo pid,user,%mem,%cpu,comm --sort=-%cpu | head -n 6

echo -e "\n${CYAN}=============================================${NC}"
echo -e "${CYAN}   END OF REPORT${NC}"
echo -e "${CYAN}=============================================${NC}"
echo -e "${YELLOW}Script created by: system-administrator${NC}"

# ---------------------------------------------------
# HOW TO RUN THIS PERIODICALLY (CRON)
# ---------------------------------------------------
# 1. Save this script, e.g.: /home/pcclormis/system_check.sh
# 2. Make it executable:
#      chmod +x /home/pcclormis/system_check.sh
# 3. Open your crontab:
#      crontab -e
# 4. Add this line to run it every 30 minutes and save the output to a log file:
#      */30 * * * * /home/pcclormis/system_check.sh >> /home/pcclormis/system_check.log 2>&1
