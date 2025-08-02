#!/bin/bash

# VPN端口映射工具安装脚本
# 作者: PanJX02
# 版本: 1.2.0
# 日期: 2025-08-01

# 设置错误处理
set -e
trap 'echo "安装过程中出现错误，退出安装"; exit 1' ERR

# 检查是否为更新模式
if [[ "$1" == "--self-update" ]]; then
    echo "正在更新安装脚本..."
    exit 0
fi

# 脚本URL
SCRIPT_URL="https://raw.githubusercontent.com/PanJX02/PortMapping/refs/heads/main/vpn.sh"
INSTALL_DIR="/usr/local/bin"
SCRIPT_NAME="vpn"
CONFIG_DIR="/etc/vpn"
CONFIG_FILE="$CONFIG_DIR/portforward.conf"
LOG_DIR="/var/log/vpn"
LOG_FILE="$LOG_DIR/portforward.log"
VERSION="1.1.0"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 打印带颜色的消息
print_msg() {
    local color=$1
    local message=$2
    echo -e "${color}[$(date '+%Y-%m-%d %H:%M:%S')] ${message}${NC}"
}

# 检查root权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_msg $RED "错误: 此脚本必须以root权限运行"
        print_msg $YELLOW "请使用: sudo $0"
        exit 1
    fi
    print_msg $GREEN "Root权限检查通过"
}

# 检查网络连接
check_network() {
    print_msg $YELLOW "正在检查网络连接..."
    if ! ping -c 1 github.com &> /dev/null && ! ping -c 1 8.8.8.8 &> /dev/null; then
        print_msg $RED "错误: 无法连接到互联网，请检查网络设置"
        exit 1
    fi
    print_msg $GREEN "网络连接正常"
}

# 检测系统类型
detect_os() {
    if [[ -f /etc/debian_version ]]; then
        OS="debian"
        PACKAGE_MANAGER="apt-get"
        PERSISTENT_PKG="iptables-persistent"
    elif [[ -f /etc/redhat-release ]]; then
        OS="redhat"
        PACKAGE_MANAGER="yum"
        PERSISTENT_PKG="iptables-services"
    elif [[ -f /etc/arch-release ]]; then
        OS="arch"
        PACKAGE_MANAGER="pacman"
        PERSISTENT_PKG="iptables"
    else
        print_msg $RED "错误: 不支持的操作系统"
        exit 1
    fi
    print_msg $GREEN "检测到系统类型: $OS"
}

# 安装依赖
install_dependencies() {
    print_msg $YELLOW "正在安装依赖包..."
    
    # 更新包列表
    case $OS in
        debian)
            $PACKAGE_MANAGER update -y
            ;;
        redhat)
            $PACKAGE_MANAGER update -y
            ;;
        arch)
            $PACKAGE_MANAGER -Sy
            ;;
    esac
    
    # 安装必要包
    case $OS in
        debian)
            $PACKAGE_MANAGER install -y wget iptables $PERSISTENT_PKG
            ;;
        redhat)
            $PACKAGE_MANAGER install -y wget iptables $PERSISTENT_PKG
            ;;
        arch)
            $PACKAGE_MANAGER -S --noconfirm wget iptables
            ;;
    esac
    
    if [[ $? -eq 0 ]]; then
        print_msg $GREEN "依赖安装成功"
    else
        print_msg $RED "依赖安装失败"
        exit 1
    fi
}

# 下载主脚本
download_script() {
    print_msg $YELLOW "正在下载VPN脚本..."
    
    # 创建安装目录
    mkdir -p $INSTALL_DIR
    
    # 下载脚本
    wget -N -O $INSTALL_DIR/$SCRIPT_NAME $SCRIPT_URL
    
    if [[ $? -eq 0 ]]; then
        chmod +x $INSTALL_DIR/$SCRIPT_NAME
        print_msg $GREEN "脚本下载成功: $INSTALL_DIR/$SCRIPT_NAME"
    else
        print_msg $RED "脚本下载失败"
        exit 1
    fi
}

# 创建配置目录和文件
create_config() {
    print_msg $YELLOW "正在创建配置目录和文件..."
    
    # 创建配置目录
    mkdir -p $CONFIG_DIR
    
    # 创建日志目录
    mkdir -p $LOG_DIR
    touch $LOG_FILE
    chmod 640 $LOG_FILE
    
    # 创建配置文件
    cat > $CONFIG_FILE << EOL
# VPN端口映射配置文件
# 此文件由VPN工具自动管理
# 请勿手动修改

# 版本信息
VERSION="$VERSION"

# 规则标记
RULE_COMMENT="vpn_port_forward"

# iptables规则保存路径
IPTABLES_RULES="/etc/iptables/rules.v4"

# 日志文件路径
LOG_FILE="$LOG_FILE"

# 上次更新时间
LAST_UPDATE="$(date '+%Y-%m-%d %H:%M:%S')"
EOL
    
    print_msg $GREEN "配置文件创建成功: $CONFIG_FILE"
    print_msg $GREEN "日志文件创建成功: $LOG_FILE"
}

# 启用持久化服务
enable_persistence() {
    print_msg $YELLOW "正在启用iptables持久化..."
    
    case $OS in
        debian)
            systemctl enable netfilter-persistent
            systemctl start netfilter-persistent
            ;;
        redhat)
            systemctl enable iptables
            systemctl start iptables
            ;;
        arch)
            systemctl enable iptables
            systemctl start iptables
            ;;
    esac
    
    if [[ $? -eq 0 ]]; then
        print_msg $GREEN "iptables持久化已启用"
    else
        print_msg $RED "启用iptables持久化失败"
    fi
}

# 显示安装完成信息
show_completion() {
    print_msg $GREEN "=========================================="
    print_msg $GREEN "VPN端口映射工具安装完成!"
    print_msg $GREEN "=========================================="
    echo
    print_msg $YELLOW "使用方法:"
    echo "  vpn                          # 交互式菜单"
    echo "  vpn <服务端口> <起始端口> <结束端口>  # 直接指定端口"
    echo "  vpn off                      # 取消映射"
    echo "  vpn status                   # 查看状态"
    echo "  vpn update                   # 检查更新"
    echo "  vpn version                  # 显示版本"
    echo "  vpn help                     # 显示帮助"
    echo ""
    print_msg $BLUE "更新安装脚本:"
    echo "  wget -N https://raw.githubusercontent.com/PanJX02/PortMapping/refs/heads/main/install.sh && sudo bash install.sh"
    echo
    print_msg $YELLOW "示例:"
    echo "  sudo vpn                     # 交互式输入"
    echo "  sudo vpn 8080 10000 20000    # 将外部10000-20000端口映射到内部8080端口"
    echo "  sudo vpn off                 # 取消映射"
    echo
    print_msg $BLUE "项目地址: https://github.com/PanJX02/port_mapping"
}

# 创建定时任务
create_cron_job() {
    print_msg $YELLOW "正在设置自动更新检查..."
    
    # 创建每周自动更新检查的cron任务
    (crontab -l 2>/dev/null | grep -v "$SCRIPT_NAME update --cron"; echo "0 0 * * 0 $INSTALL_DIR/$SCRIPT_NAME update --cron") | crontab -
    
    print_msg $GREEN "自动更新检查已设置为每周执行一次"
}

# 备份现有配置
backup_config() {
    if [[ -f $CONFIG_FILE ]]; then
        print_msg $YELLOW "发现现有配置，正在备份..."
        cp $CONFIG_FILE "${CONFIG_FILE}.backup.$(date +%Y%m%d%H%M%S)"
        print_msg $GREEN "配置备份完成"
    fi
}

# 主安装流程
main() {
    print_msg $GREEN "开始安装VPN端口映射工具..."
    print_msg $BLUE "版本: $VERSION"
    
    check_root
    check_network
    detect_os
    backup_config
    install_dependencies
    download_script
    create_config
    enable_persistence
    create_cron_job
    show_completion
    
    # 记录安装日志
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] VPN端口映射工具 v$VERSION 安装成功" >> $LOG_FILE
}

# 执行主流程
main
