#!/bin/bash
# VPN端口映射工具安装脚本 (v2.0 - 优化版)
# 作者: PanJX02 (由 AI 协助优化)
# 版本: 2.0.0
# 日期: 2025-08-03
# 描述: 此版本增加了防火墙冲突检测，并全面支持IPv4/IPv6依赖安装。

set -e
trap 'echo -e "\n${RED}安装过程中出现错误，已终止安装。${NC}"; exit 1' ERR

# --- 配置 ---
SCRIPT_URL="https://raw.githubusercontent.com/PanJX02/PortMapping/refs/heads/main/vpn.sh" # 应指向支持IPv6的新版脚本
INSTALL_DIR="/etc/vpn"
SCRIPT_NAME="vpn.sh"
LOG_DIR="/etc/vpn/log"
SYMLINK_PATH="/usr/local/bin/vpn"

# --- 颜色定义 ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
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
        PERSISTENT_PKG_V4="iptables-persistent"
        PERSISTENT_PKG_V6="iptables-persistent" # 在Debian系中，同一个包管理v4和v6
    elif [[ -f /etc/redhat-release ]]; then
        OS="redhat"
        PACKAGE_MANAGER="yum"
        # CentOS/RHEL 7+ 使用不同的服务包
        PERSISTENT_PKG_V4="iptables-services"
        PERSISTENT_PKG_V6="iptables-services" # ip6tables 服务也由这个包提供
    else
        print_msg $RED "错误: 不支持的操作系统。此脚本仅支持 Debian/Ubuntu 和 RHEL/CentOS 系列。"
        exit 1
    fi
    print_msg $GREEN "检测到系统: $OS"
}

# 修改后的防火墙检查函数 - 改为提示而不是强制退出
check_firewall_conflict() {
    print_msg $YELLOW "正在检查现有防火墙..."
    local conflict=0
    local firewall_list=""
    
    if command -v ufw &>/dev/null && [[ "$(ufw status)" != "Status: inactive" ]]; then
        print_msg $YELLOW "检测到 UFW (Uncomplicated Firewall) 正在运行。"
        conflict=1
        firewall_list="${firewall_list}UFW "
    fi
    
    if systemctl is-active --quiet firewalld; then
        print_msg $YELLOW "检测到 Firewalld 正在运行。"
        conflict=1
        firewall_list="${firewall_list}Firewalld "
    fi

    if [[ "$conflict" -eq 1 ]]; then
        echo
        print_msg $YELLOW "========================== 重要提示 =========================="
        print_msg $CYAN "检测到以下防火墙正在运行: ${firewall_list}"
        print_msg $YELLOW "此脚本通过直接管理 iptables 和 ip6tables 工作。"
        print_msg $YELLOW "同时使用多个防火墙可能会导致规则冲突。"
        echo
        print_msg $BLUE "建议操作:"
        print_msg $BLUE "• Debian/Ubuntu 用户: sudo ufw disable"
        print_msg $BLUE "• CentOS/RHEL 用户: sudo systemctl stop firewalld && sudo systemctl disable firewalld"
        echo
        print_msg $YELLOW "您可以选择:"
        print_msg $YELLOW "1. 现在退出，禁用防火墙后重新运行"
        print_msg $YELLOW "2. 继续安装（需要您自行处理可能的冲突）"
        echo
        
        # 添加用户选择
        read -p "是否继续安装？(y/N): " -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_msg $BLUE "安装已取消。请在处理防火墙后重新运行此脚本。"
            exit 0
        fi
        
        print_msg $GREEN "用户选择继续安装。"
    else
        print_msg $GREEN "未发现活动的 UFW 或 Firewalld。"
    fi
}

install_dependencies() {
    print_msg $YELLOW "正在安装依赖: wget, iptables, 和持久化服务..."
    case $OS in
        debian)
            $PACKAGE_MANAGER update -y
            # 预设 debconf 选项，避免 iptables-persistent 安装时卡住提问
            echo "iptables-persistent iptables-persistent/autosave_v4 boolean true" | debconf-set-selections
            echo "iptables-persistent iptables-persistent/autosave_v6 boolean true" | debconf-set-selections
            $PACKAGE_MANAGER install -y wget iptables "$PERSISTENT_PKG_V4"
            ;;
        redhat)
            $PACKAGE_MANAGER install -y wget "$PERSISTENT_PKG_V4"
            ;;
    esac
    print_msg $GREEN "依赖安装成功。"
}

download_script() {
    print_msg $YELLOW "正在下载主脚本..."
    mkdir -p "$INSTALL_DIR"
    if wget -O "$INSTALL_DIR/$SCRIPT_NAME" "$SCRIPT_URL"; then
        chmod +x "$INSTALL_DIR/$SCRIPT_NAME"
        print_msg $GREEN "主脚本下载成功: $INSTALL_DIR/$SCRIPT_NAME"
    else
        print_msg $RED "主脚本下载失败，请检查网络或URL是否正确。"
        exit 1
    fi
}

create_symlink() {
    print_msg $YELLOW "正在创建命令软链接..."
    # 使用 -f 强制覆盖可能存在的旧的软链接
    if ln -sf "$INSTALL_DIR/$SCRIPT_NAME" "$SYMLINK_PATH"; then
        print_msg $GREEN "命令 'vpn' 创建成功。现在您可以在任何路径下使用 'vpn' 命令。"
    else
        print_msg $RED "创建软链接失败。您仍然可以通过完整路径 /etc/vpn/vpn.sh 运行。"
    fi
}

setup_environment() {
    print_msg $YELLOW "正在设置配置环境..."
    # 只创建目录，主脚本会自动初始化配置文件
    mkdir -p "$LOG_DIR"
    
    # 备份现有配置（如果存在）
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
    # 确保iptables规则在重启后生效
    case $OS in
        debian)
            systemctl enable netfilter-persistent
            systemctl restart netfilter-persistent
            ;;
        redhat)
            systemctl enable iptables
            systemctl enable ip6tables
            systemctl start iptables
            systemctl start ip6tables
            ;;
    esac
    print_msg $GREEN "持久化服务已启用。"
}

show_completion() {
    echo
    print_msg $GREEN "====================================================="
    print_msg $GREEN "  VPN端口映射工具 (v2.0) 安装成功!  "
    print_msg $GREEN "====================================================="
    echo
    print_msg $YELLOW "您现在可以使用 'vpn' 命令来管理端口映射:"
    echo -e "  ${BLUE}sudo vpn${NC}              - 进入交互式菜单 (推荐)"
    echo -e "  ${BLUE}sudo vpn status${NC}       - 查看当前映射状态"
    echo -e "  ${BLUE}sudo vpn help${NC}         - 获取帮助和查看更多命令"
    echo
    print_msg $YELLOW "要添加一个映射，可以运行:"
    echo -e "  ${CYAN}sudo vpn ipv4 8080 10000 20000${NC}   (仅IPv4)"
    echo -e "  ${CYAN}sudo vpn ipv6 8080 10000 20000${NC}   (仅IPv6)"
    echo -e "  ${CYAN}sudo vpn all  8080 10000 20000${NC}   (同时用于IPv4和IPv6)"
    echo
    print_msg $BLUE "项目地址: https://github.com/PanJX02/PortMapping"
    echo
}

# --- 主流程 ---
main() {
    check_root
    check_network
    detect_os
    check_firewall_conflict # 修改后的检查函数
    install_dependencies
    download_script
    create_symlink
    setup_environment
    enable_persistence
    show_completion
}

main "$@"