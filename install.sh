#!/bin/bash
# VPN 端口映射工具 - 智能安装程序 V1.4
# 功能: 从在线URL下载主脚本，并强制将其安装为 'portmap' 命令。

# --- 配置 ---
# 我们期望安装到系统中的命令名称和相关路径
DESIRED_COMMAND_NAME="portmap" 
INSTALL_PATH="/usr/local/bin/${DESIRED_COMMAND_NAME}"
CONFIG_DIR_BASE="/etc/${DESIRED_COMMAND_NAME}"
# 从 GitHub 直接获取主脚本
SCRIPT_URL="https://raw.githubusercontent.com/PanJX02/PortMapping/main/vpn.sh"

# --- 颜色和辅助函数 ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

printmsg() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        printmsg "错误: 此安装程序需要root权限运行。请使用 'sudo ./install.sh'" "$RED"
        exit 1
    fi
}

# --- 核心安装逻辑 ---

# 1. 检测操作系统类型 (此处省略，与之前版本相同)
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
    else
        printmsg "无法检测到操作系统类型。" "$RED"; exit 1
    fi
}

# 2. 按需安装依赖 (此处省略，与之前版本相同)
install_dependencies() {
    printmsg "正在检测防火墙和所需依赖..." "$YELLOW"
    if systemctl is-active --quiet firewalld; then
        printmsg "检测到 Firewalld。" "$GREEN"; return
    fi
    if command -v ufw &>/dev/null && ufw status | grep -q "Status: active"; then
        printmsg "检测到 UFW。" "$GREEN"; return
    fi
    printmsg "未检测到 Firewalld 或 UFW，准备为 iptables 配置持久化..." "$YELLOW"
    case "$OS" in
        ubuntu|debian)
            apt-get update >/dev/null 2>&1
            DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent >/dev/null 2>&1
            ;;
        centos|rhel|fedora)
            yum install -y iptables-services >/dev/null 2>&1
            systemctl enable --now iptables >/dev/null 2>&1
            systemctl enable --now ip6tables >/dev/null 2>&1
            ;;
        *) printmsg "此操作系统 ($OS) 不支持自动配置 iptables 持久化。" "$RED" ;;
    esac
    printmsg "依赖项配置完成。" "$GREEN"
}

# 3. 下载、修改并创建主脚本文件
create_main_script() {
    printmsg "正在从 GitHub 下载最新版本的主程序..." "$YELLOW"
    
    local temp_script
    temp_script=$(mktemp) # 创建一个临时文件来存储下载内容
    
    # 优先使用 curl, 其次使用 wget
    if command -v curl &>/dev/null; then
        if ! curl -sSL --fail -o "$temp_script" "$SCRIPT_URL"; then
            printmsg "错误: curl 下载失败。URL: $SCRIPT_URL" "$RED"; rm -f "$temp_script"; exit 1
        fi
    elif command -v wget &>/dev/null; then
        if ! wget -q -O "$temp_script" "$SCRIPT_URL"; then
            printmsg "错误: wget 下载失败。URL: $SCRIPT_URL" "$RED"; rm -f "$temp_script"; exit 1
        fi
    else
        printmsg "错误: 需要 'curl' 或 'wget' 才能下载主程序。请先安装它们。" "$RED"; exit 1
    fi

    if [ ! -s "$temp_script" ]; then
        printmsg "错误: 主程序下载失败或文件为空。请检查网络和URL。" "$RED"; rm -f "$temp_script"; exit 1
    fi

    printmsg "下载成功。正在修改脚本以适配 '${DESIRED_COMMAND_NAME}' 命令..." "$YELLOW"

    # ✨ 关键步骤: 使用 sed 修改脚本内容
    # 1. 查找 'SCRIPTNAME="..."' 这一行，并替换成我们期望的值。
    # 2. 查找 'CONFIGDIR=...' 这一行，并替换成我们期望的值。
    sed -e "s/^$SCRIPTNAME *= *$\".*\"/\1\"${DESIRED_COMMAND_NAME}\"/" \
        -e "s|^$CONFIGDIR *= *$\".*\"|\1\"${CONFIG_DIR_BASE}\"|" \
        "$temp_script" > "$INSTALL_PATH"

    rm -f "$temp_script" # 删除临时文件

    # 赋予执行权限
    chmod +x "$INSTALL_PATH"
    printmsg "主程序已成功定制并安装到: $INSTALL_PATH" "$GREEN"
}

# --- 主安装流程 ---
main() {
    check_root
    
    # 清理可能存在的旧版本残留
    if [ -f "/usr/local/bin/vpn-port-map" ]; then
        printmsg "检测到旧的 'vpn-port-map' 文件，正在清理..." "$YELLOW"
        rm -f "/usr/local/bin/vpn-port-map"
    fi
    
    if [ -f "$INSTALL_PATH" ]; then
        printmsg "检测到已安装版本。如果需要重新安装，请先运行 'sudo ${DESIRED_COMMAND_NAME} uninstall' 并选择卸载。" "$YELLOW"
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
    printmsg "    sudo ${DESIRED_COMMAND_NAME}" "$YELLOW"
    echo
}

# --- 程序入口 ---
# 检查是否请求卸载
if [[ "$1" == "uninstall" ]]; then
    if [[ ! -f "$INSTALL_PATH" ]]; then
        printmsg "未找到已安装的 portmap。无需卸载。" "$YELLOW"
        exit 0
    fi
    # 将卸载任务委托给已安装的脚本自身
    printmsg "正在调用已安装脚本的卸载程序..." "$YELLOW"
    sudo "$INSTALL_PATH" uninstall
    exit $?
fi

main
