#!/bin/bash
# VPN 端口映射工具 - 安全安装程序 V1.2 (采用在线下载方式)
# 安装后的命令为 'portmap'

# --- 配置 ---
INSTALL_PATH="/usr/local/bin/portmap"
CONFIG_DIR="/etc/portmap"
# 从 GitHub 直接获取主脚本
SCRIPT_URL="https://raw.githubusercontent.com/PanJX02/PortMapping/main/vpn.sh"


# --- 颜色和辅助函数 ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

printmsg() {
    echo -e "${2}${1}${NC}"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        printmsg "错误: 此安装程序需要root权限运行。请使用 'sudo ./install.sh'" "$RED"
        exit 1
    fi
}

# --- 核心安装逻辑 ---

# 1. 检测操作系统类型
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
    else
        printmsg "无法检测到操作系统类型。" "$RED"
        exit 1
    fi
}

# 2. 按需安装依赖
install_dependencies() {
    printmsg "正在检测防火墙和所需依赖..." "$YELLOW"

    if systemctl is-active --quiet firewalld; then
        printmsg "检测到 Firewalld。无需安装额外依赖。" "$GREEN"
        return
    fi
    
    if command -v ufw &>/dev/null && ufw status | grep -q "Status: active"; then
        printmsg "检测到 UFW。无需安装额外依赖。" "$GREEN"
        return
    fi

    printmsg "未检测到 Firewalld 或 UFW。将为原生 iptables 安装持久化工具。" "$YELLOW"

    case "$OS" in
        ubuntu|debian)
            printmsg "正在为 Debian/Ubuntu 安装 'iptables-persistent'..." "$YELLOW"
            apt-get update >/dev/null
            echo "iptables-persistent iptables-persistent/autosave_v4 boolean true" | debconf-set-selections
            echo "iptables-persistent iptables-persistent/autosave_v6 boolean true" | debconf-set-selections
            apt-get install -y iptables-persistent >/dev/null
            ;;
        centos|rhel|fedora)
            printmsg "正在为 RHEL/CentOS 安装 'iptables-services'..." "$YELLOW"
            yum install -y iptables-services >/dev/null
            systemctl enable iptables &>/dev/null
            systemctl enable ip6tables &>/dev/null
            systemctl start iptables &>/dev/null
            systemctl start ip6tables &>/dev/null
            ;;
        *)
            printmsg "此操作系统 ($OS) 的 iptables 持久化配置不受自动支持。请手动配置。" "$RED"
            ;;
    esac
    printmsg "依赖项配置完成。" "$GREEN"
}

# 3. 下载并创建主脚本文件
create_main_script() {
    printmsg "正在从 GitHub 下载最新版本的主程序..." "$YELLOW"
    
    # 优先使用 curl, 其次使用 wget
    if command -v curl &>/dev/null; then
        curl -sSL -o "$INSTALL_PATH" "$SCRIPT_URL"
    elif command -v wget &>/dev/null; then
        wget -q -O "$INSTALL_PATH" "$SCRIPT_URL"
    else
        printmsg "错误: 需要 'curl' 或 'wget' 才能下载主程序。请先安装它们。" "$RED"
        exit 1
    fi

    # 检查下载是否成功 (文件是否存在且非空)
    if [ ! -s "$INSTALL_PATH" ]; then
        printmsg "错误: 主程序下载失败。请检查您的网络连接或URL是否正确。" "$RED"
        printmsg "URL: $SCRIPT_URL" "$YELLOW"
        exit 1
    fi

    # 赋予执行权限
    chmod +x "$INSTALL_PATH"
    printmsg "主程序已成功下载并安装到: $INSTALL_PATH" "$GREEN"
}

# --- 主安装流程 ---
main() {
    check_root
    
    if [ -f "$INSTALL_PATH" ]; then
        # 注意：这里的卸载提示需要根据 vpn.sh 的实际命令来调整
        # 假设新的 vpn.sh 同样是用 portmap uninstall 来卸载
        printmsg "检测到已安装版本。如果需要重新安装，请先运行 'sudo portmap uninstall' 并选择卸载。" "$YELLOW"
        exit 0
    fi

    printmsg "欢迎使用 端口映射工具 安装程序" "$GREEN"
    detect_os
    install_dependencies
    create_main_script
    
    printmsg "==================================================" "$GREEN"
    printmsg "          安装成功!" "$GREEN"
    printmsg "==================================================" "$GREEN"
    printmsg "现在您可以通过运行以下命令来使用此工具:" "$NC"
    echo
    printmsg "    sudo portmap" "$YELLOW"
    echo
}

main
