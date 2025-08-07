#!/bin/bash
# VPN端口映射工具安装脚本 (v2.1 - 交互式风险提示版)
# 作者: PanJX02 (由 AI 协助优化)
# 版本: 2.1.0
# 日期: 2025-08-03
# 描述: 此版本在检测到防火墙冲突时，会警告并允许用户选择是否继续。

set -e
trap 'echo -e "\n${RED}安装过程中出现错误，已终止安装。${NC}"; exit 1' ERR

# --- 配置 ---
SCRIPT_URL="https://raw.githubusercontent.com/PanJX02/PortMapping/refs/heads/main/vpn.sh"
INSTALL_DIR="/etc/vpn"
SCRIPT_NAME="vpn.sh"
LOG_DIR="/etc/vpn/log"
SYMLINK_PATH="/usr/local/bin/vpn"

# --- 颜色定义 ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

detect_os() {
    print_msg $YELLOW "正在检测操作系统..."
    if [[ -f /etc/debian_version ]]; then
        OS="debian"
        PACKAGE_MANAGER="apt-get"
        PERSISTENT_PKG="iptables-persistent"
    elif [[ -f /etc/redhat-release ]]; then
        OS="redhat"
        PACKAGE_MANAGER="yum"
        PERSISTENT_PKG="iptables-services"
    else
        print_msg $RED "错误: 不支持的操作系统。此脚本仅支持 Debian/Ubuntu 和 RHEL/CentOS 系列。"
        exit 1
    fi
    print_msg $GREEN "检测到系统: $OS"
}

# ====================================================================
#  ↓↓↓ 核心修改部分 ↓↓↓
# ====================================================================
check_firewall_conflict() {
    print_msg $YELLOW "正在检查现有防火墙..."
    local conflict_detected=""

    if command -v ufw &>/dev/null && [[ "$(ufw status | grep 'Status:' | awk '{print $2}')" == "active" ]]; then
        conflict_detected="UFW (Uncomplicated Firewall)"
    elif systemctl is-active --quiet firewalld; then
        conflict_detected="Firewalld"
    fi

    if [[ -n "$conflict_detected" ]]; then
        echo
        print_msg $RED "========================== 严重警告 =========================="
        print_msg $YELLOW "检测到防火墙 '$conflict_detected' 正在运行！"
        print_msg $YELLOW "本工具通过直接管理 iptables 工作，与 '$conflict_detected' 同时使用"
        print_msg $YELLOW "可能会导致规则冲突、网络中断或安全策略失效。"
        print_msg $RED "强烈建议您先禁用 '$conflict_detected' 再继续。"
        echo
        print_msg $BLUE "建议操作 DANGER:"
        print_msg $BLUE "  - Debian/Ubuntu: sudo ufw disable"
        print_msg $BLUE "  - CentOS/RHEL:   sudo systemctl stop firewalld && sudo systemctl disable firewalld"
        echo
        
        # 交互式选择
        read -p "$(echo -e ${YELLOW}"您确定要忽略此警告并继续安装吗？(请输入 y 继续，其他则取消): "${NC})" user_choice
        
        if [[ "$user_choice" =~ ^[Yy]$ ]]; then
            print_msg $YELLOW "用户选择继续安装。请务必了解潜在的风险！"
        else
            print_msg $RED "用户选择取消。安装已安全终止。"
            exit 0
        fi
    else
        print_msg $GREEN "未发现活动的 UFW 或 Firewalld，检查通过。"
    fi
}
# ====================================================================
#  ↑↑↑ 核心修改部分 ↑↑↑
# ====================================================================

install_dependencies() {
    print_msg $YELLOW "正在安装依赖: wget, iptables, 和持久化服务..."
    case $OS in
        debian)
            $PACKAGE_MANAGER update -y > /dev/null
            echo "iptables-persistent iptables-persistent/autosave_v4 boolean true" | debconf-set-selections
            echo "iptables-persistent iptables-persistent/autosave_v6 boolean true" | debconf-set-selections
            $PACKAGE_MANAGER install -y wget iptables "$PERSISTENT_PKG"
            ;;
        redhat)
            $PACKAGE_MANAGER install -y wget "$PERSISTENT_PKG"
            ;;
    esac
    print_msg $GREEN "依赖安装成功。"
}

download_script() {
    print_msg $YELLOW "正在下载主脚本..."
    mkdir -p "$INSTALL_DIR"
    if wget -q -O "$INSTALL_DIR/$SCRIPT_NAME" "$SCRIPT_URL"; then
        chmod +x "$INSTALL_DIR/$SCRIPT_NAME"
        print_msg $GREEN "主脚本下载成功: $INSTALL_DIR/$SCRIPT_NAME"
    else
        print_msg $RED "主脚本下载失败，请检查网络或URL是否正确。"
        exit 1
    fi
}

create_symlink() {
    print_msg $YELLOW "正在创建命令软链接..."
    if ln -sf "$INSTALL_DIR/$SCRIPT_NAME" "$SYMLINK_PATH"; then
        print_msg $GREEN "命令 'vpn' 创建成功。您现在可以在任何路径下使用 'vpn' 命令。"
    else
        print_msg $RED "创建软链接失败。您仍然可以通过完整路径 /etc/vpn/vpn.sh 运行。"
    fi
}

setup_environment() {
    print_msg $YELLOW "正在设置配置环境..."
    mkdir -p "$LOG_DIR"
    
    local config_file="$INSTALL_DIR/portforward.conf"
    if [[ -f "$config_file" ]]; then
        print_msg $YELLOW "发现现有配置文件，正在备份..."
        mv "$config_file" "${config_file}.backup.$(date +%Y%m%d_%H%M%S)"
        print_msg $GREEN "旧配置文件已备份。"
    fi
    
    print_msg $GREEN "环境设置完成。"
}

enable_persistence() {
    print_msg $YELLOW "正在启用 iptables & ip6tables 持久化服务..."
    case $OS in
        debian)
            # 在Debian/Ubuntu上，netfilter-persistent 同时管理 v4 和 v6
            systemctl enable netfilter-persistent &>/dev/null
            systemctl restart netfilter-persistent
            ;;
        redhat)
            # 在RHEL/CentOS上，iptables-services 包提供两个独立服务
            systemctl enable iptables &>/dev/null
            systemctl enable ip6tables &>/dev/null
            systemctl start iptables
            systemctl start ip6tables
            ;;
    esac
    print_msg $GREEN "持久化服务已启用。"
}

show_completion() {
    # ... (这部分内容未变，为简洁省略)
    echo
    print_msg $GREEN "====================================================="
    print_msg $GREEN "  VPN端口映射工具 安装成功!  "
    print_msg $GREEN "====================================================="
    echo
    print_msg $YELLOW "您现在可以使用 'vpn' 命令来管理端口映射:"
    echo -e "  ${BLUE}sudo vpn${NC}              - 进入交互式菜单 (推荐)"
    echo -e "  ${BLUE}sudo vpn status${NC}       - 查看当前映射状态"
    echo -e "  ${BLUE}sudo vpn help${NC}         - 获取帮助和查看更多命令"
    echo
    print_msg $BLUE "项目地址: https://github.com/PanJX02/PortMapping"
    echo
}

# --- 主流程 ---
main() {
    check_root
    check_network
    detect_os
    check_firewall_conflict # 已更新此函数
    install_dependencies
    download_script
    create_symlink
    setup_environment
    enable_persistence
    show_completion
}

main "$@"

