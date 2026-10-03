#!/usr/bin/env bash
# debug_log.sh - Tool stream log ESP realtime từ iPhone qua USB

set -e

# Đổi màu output cho terminal
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

echo -e "${CYAN}====================================================${NC}"
echo -e "${CYAN}        ESP FREE FIRE - REALTIME LOG STREAMER       ${NC}"
echo -e "${CYAN}====================================================${NC}"

# Kiểm tra idevicesyslog
if ! command -v idevicesyslog &> /dev/null; then
    echo -e "${RED}[!] Không tìm thấy idevicesyslog! Vui lòng kiểm tra lại brew install libimobiledevice.${NC}"
    exit 1
fi

# Kiểm tra thiết bị kết nối
DEVICE_ID=$(idevice_id -l | head -n 1)
if [ -z "$DEVICE_ID" ]; then
    echo -e "${YELLOW}[!] Chưa tìm thấy iPhone cắm qua USB.${NC}"
    echo -e "${YELLOW}[*] Đang chờ kết nối iPhone...${NC}"
    while [ -z "$DEVICE_ID" ]; do
        sleep 1
        DEVICE_ID=$(idevice_id -l | head -n 1)
    done
fi

DEVICE_NAME=$(ideviceinfo -u "$DEVICE_ID" -k DeviceName 2>/dev/null || echo "iPhone")
PRODUCT_VER=$(ideviceinfo -u "$DEVICE_ID" -k ProductVersion 2>/dev/null || echo "iOS")
echo -e "${GREEN}[+] Đã kết nối thiết bị: ${DEVICE_NAME} (iOS ${PRODUCT_VER}) - UDID: ${DEVICE_ID}${NC}"
echo -e "${BLUE}[*] Đang lắng nghe log từ External_ESP_FF... Nhấn Ctrl+C để dừng.${NC}"
echo -e "${CYAN}----------------------------------------------------${NC}"

LOG_FILE="$(dirname "$0")/debug_esp.log"
echo -e "${YELLOW}[*] Log đồng thời được lưu vào: ${LOG_FILE}${NC}"
> "$LOG_FILE"

# Chạy idevicesyslog và lọc các tag quan trọng
idevicesyslog -u "$DEVICE_ID" | grep --line-buffered -E "ESP_LOG|External_ESP_FF|SBSAccessibility|andrdevv" | while read -r line; do
    echo "$line" >> "$LOG_FILE"
    
    # Tô màu theo loại log
    if [[ "$line" =~ "Error" || "$line" =~ "failed" || "$line" =~ "Null" ]]; then
        echo -e "${RED}${line}${NC}"
    elif [[ "$line" =~ "[PLAYER_DBG]" ]]; then
        echo -e "${MAGENTA}${line}${NC}"
    elif [[ "$line" =~ "[VMAT]" ]]; then
        echo -e "${YELLOW}${line}${NC}"
    elif [[ "$line" =~ "[CHAIN]" || "$line" =~ "[DETAILS]" ]]; then
        echo -e "${CYAN}${line}${NC}"
    elif [[ "$line" =~ "[SCREEN]" || "$line" =~ "[DRAW]" ]]; then
        echo -e "${BLUE}${line}${NC}"
    else
        echo -e "${GREEN}${line}${NC}"
    fi
done
