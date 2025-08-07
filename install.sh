#!/bin/bash
# VPN端口映射工具智能安装脚本 (v4.0 - UFW/Firewalld/iptables 自动适配版)
# 作者: PanJX02
# 版本: 4.0.0
# 日期: 2025-08-05
# 描述: 此版本能自动检测UFW和Firewalld。
#       - 优先适配 UFW。
#       - 其次适配 Firewalld。
#       - 最后回退到 iptables-persistent 模式。

set -e
trap 'echo -e "\n${RED}安装过程中出现错误，已终止安装。${NC}"; exit 1' ERR

# --- 配置 ---
SCRIPT_URL_BASE="https://raw.githubusercontent.com/PanJX02/PortMapping/main"
SCRIPT_URL_IPTABLES="${SCRIPT_URL_BASE}/vpn-iptables.sh"
SCRIPT_URL_UFW="${SCRIPT_URL_BASE}/vpn-ufw.sh"
SCRIPT_URL_FIREWALLD="${SCRIPT_URL_BASE}/vpn-firewalld.sh"

INSTALL_DIR="/etc/vpn"
SCRIPT_NAME="vpn.sh"
CONFIG_FILE="$INSTALL_DIR/vpn.conf"
LOG_DIR="/etc/vpn/log"
SYMLINK_PATH="/usr/local/bin/vpn"
DATA_FILE="$INSTALL_DIR/portforward.rules"

# --- 颜色定义 ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# --- 全局变量 ---
FIREWALL_MANAGER=""

# --- 函数 ---
print_msg() {
    local color=$1
    local message=$2
    echo -e "${color}[$(date '+%H:%M:%S')] ${message}${NC}"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_msg $RED "错误: 此脚本必须以root权限运行。请尝试: sudo bash $0"
        exit 1
    fi
}

check_network() {
    print_msg $YELLOW "正在检查网络连接..."
    if ! ping -c 1 -W 3 github.com &> /dev/null; then
        print_msg $RED "错误: 无法连接到 GitHub.com，请检查您的网络设置和DNS。"
        exit 1
    fi
    print_msg $GREEN "网络连接正常。"
}

detect_and_configure_firewall() {
    print_msg $YELLOW "正在检测系统防火墙管理器..."
    if command -v ufw &>/dev/null && ufw status | grep -qw active; then
        print_msg $GREEN "检测到 UFW 正在运行。将采用 UFW 模式。"
        FIREWALL_MANAGER="ufw"
        # UFW specific configuration (from previous response)
        print_msg $YELLOW "  -> 正在配置 UFW 以支持端口转发..."
        if ! grep -qs "^net.ipv4.ip_forward=1" /etc/sysctl.conf /etc/sysctl.d/*.conf; then
            echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-vpn-portmap.conf
            sysctl -p /etc/sysctl.d/99-vpn-portmap.conf >/dev/null
        fi
        if grep -q 'DEFAULT_FORWARD_POLICY="DROP"' /etc/default/ufw; then
            sed -i -E 's/DEFAULT_FORWARD_POLICY="DROP"/DEFAULT_FORWARD_POLICY="ACCEPT"/' /etc/default/ufw
        fi
        if ! grep -q '^\*nat' /etc/ufw/before.rules; then
            sed -i '1s;^;*nat\n:PREROUTING ACCEPT [0:0]\n:POSTROUTING ACCEPT [0:0]\nCOMMIT\n;' /etc/ufw/before.rules
        fi
        print_msg $GREEN "  -> UFW 配置完成。"

    elif systemctl is-active --quiet firewalld; then
        print_msg $GREEN "检测到 Firewalld 正在运行。将采用 Firewalld 模式。"
        FIREWALL_MANAGER="firewalld"
        print_msg $YELLOW "  -> 正在配置 Firewalld 以支持端口转发..."
        # 1. 开启内核IP转发
        if ! grep -qs "^net.ipv4.ip_forward=1" /etc/sysctl.conf /etc/sysctl.d/*.conf; then
            print_msg $YELLOW "     - 启用内核IP转发..."
            echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-vpn-portmap.conf
            sysctl -p /etc/sysctl.d/99-vpn-portmap.conf >/dev/null
        fi
        # 2. 检查并开启公网区域的伪装 (Masquerade)
        local public_zone=$(firewall-cmd --get-default-zone)
        if ! firewall-cmd --zone=$public_zone --query-masquerade --permanent &>/dev/null; then
             print_msg $YELLOW "     - 在 '$public_zone' 区域启用伪装 (Masquerade)..."
            firewall-cmd --zone=$public_zone --add-masquerade --permanent >/dev/null
            firewall-cmd --reload >/dev/null
        fi
        print_msg $GREEN "  -> Firewalld 配置完成。"

    else
        print_msg $GREEN "未检测到 UFW 或 Firewalld。将采用 iptables-persistent 模式。"
        FIREWALL_MANAGER="iptables"
    fi
}

# (其他函数如 install_dependencies, setup_environment, create_symlink, show_completion 保持不变，
# 只需在 download_script 和 enable_services 中添加对 firewalld 的处理)

download_script() {
    local url_to_download=""
    print_msg $YELLOW "正在下载适配 ${FIREWALL_MANAGER} 模式的核心脚本..."
    case "$FIREWALL_MANAGER" in
        "ufw") url_to_download="$SCRIPT_URL_UFW" ;;
        "firewalld") url_to_download="$SCRIPT_URL_FIREWALLD" ;;
        "iptables") url_to_download="$SCRIPT_URL_IPTABLES" ;;
    esac

    if wget -q -O "$INSTALL_DIR/$SCRIPT_NAME" "$url_to_download"; then
        chmod +x "$INSTALL_DIR/$SCRIPT_NAME"
        print_msg $GREEN "核心脚本下载成功: $INSTALL_DIR/$SCRIPT_NAME"
    else
        print_msg $RED "核心脚本下载失败，请检查网络或URL。"
        exit 1
    fi
}

enable_services() {
    print_msg $YELLOW "正在启用/重载相关服务..."
    case "$FIREWALL_MANAGER" in
        "ufw")
            ufw reload > /dev/null
            print_msg $GREEN "UFW 重载成功。"
            ;;
        "firewalld")
            firewall-cmd --reload > /dev/null
            print_msg $GREEN "Firewalld 重载成功。"
            ;;
        "iptables")
            if [[ -f /etc/debian_version ]]; then
                systemctl enable netfilter-persistent &>/dev/null
                systemctl restart netfilter-persistent
            elif [[ -f /etc/redhat-release ]]; then
                systemctl enable iptables &>/dev/null
                systemctl restart iptables
            fi
            print_msg $GREEN "iptables 持久化服务已启用/重启。"
            ;;
    esac
}

# ... 其他函数如 install_dependencies, setup_environment, create_symlink, show_completion ...
# 确保在这些函数中也做适当的微调, 比如依赖安装。
# 这里给出完整的 main 流程, 函数体和之前类似。

# --- 主流程 ---
main() {
    # 假设所有辅助函数都已定义好
    check_root
    check_network
    detect_and_configure_firewall
    # install_dependencies # (这个函数需要根据 firewall-manager 决定是否安装东西)
    setup_environment
    download_script
    enable_services
    create_symlink
    # show_completion # (这个函数显示最终信息)
    
    # 一个简化的 show_completion
    local manager_display=$(echo "$FIREWALL_MANAGER" | tr '[:lower:]' '[:upper:]') 
    echo
    print_msg $GREEN "====================================================="
    print_msg $GREEN "  VPN端口映射工具 安装成功!  "
    print_msg $GREEN "  当前运行模式: ${manager_display}"
    print_msg $GREEN "====================================================="
    echo
    print_msg $YELLOW "您现在可以使用 'vpn' 命令来管理端口映射。"
}

main "$@"

