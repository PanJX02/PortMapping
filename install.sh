#!/bin/bash

# VPN端口映射工具安装脚本
# 作者: PanJX02
# 版本: 1.3.0
# 日期: 2025-08-01

# 设置错误处理
set -e
trap 'echo "安装过程中出现错误，退出安装"; exit 1' ERR

# 检查是否为更新模式
if [[ "$1" == "--self-update" ]]; then
    echo "正在更新安装脚本..."
    exit 0
fi

# 脚本URL (修复：移除末尾空格)
SCRIPT_URL="https://raw.githubusercontent.com/PanJX02/PortMapping/refs/heads/main/vpn.sh"
INSTALL_DIR="/etc/vpn"
SCRIPT_NAME="vpn.sh"
CONFIG_DIR="/etc/vpn"
CONFIG_FILE="$CONFIG_DIR/portforward.conf"
LOG_DIR="/etc/vpn/log"
LOG_FILE="$LOG_DIR/install.log"
VERSION="1.3.0"
SYMLINK_PATH="/usr/local/bin/vpn" # 添加软链接路径

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
        PACKAGE_MANAGER="yum" # 或 dnf，但 yum 通常向后兼容
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
    mkdir -p "$INSTALL_DIR"

    # 下载脚本 (修复：使用正确的 URL 和文件名)
    if wget -N -O "$INSTALL_DIR/$SCRIPT_NAME" "$SCRIPT_URL"; then
        chmod +x "$INSTALL_DIR/$SCRIPT_NAME"
        print_msg $GREEN "脚本下载成功: $INSTALL_DIR/$SCRIPT_NAME"
    else
        print_msg $RED "脚本下载失败"
        exit 1
    fi
}

# 创建软链接以便直接使用 'vpn' 命令
create_symlink() {
    print_msg $YELLOW "正在创建软链接 $SYMLINK_PATH..."
    # 如果软链接已存在，先删除它
    if [[ -L "$SYMLINK_PATH" ]]; then
        rm -f "$SYMLINK_PATH"
        print_msg $BLUE "已删除旧的软链接 $SYMLINK_PATH"
    fi
    # 如果目标位置是文件或目录，发出警告但不覆盖
    if [[ -e "$SYMLINK_PATH" ]]; then
        print_msg $RED "警告: $SYMLINK_PATH 已存在且不是软链接，无法创建软链接。请手动删除或移动该文件/目录。"
        print_msg $YELLOW "您仍然可以通过 $INSTALL_DIR/$SCRIPT_NAME 运行脚本。"
        return 1 # 不算致命错误
    fi

    # 创建软链接
    if ln -s "$INSTALL_DIR/$SCRIPT_NAME" "$SYMLINK_PATH"; then
        print_msg $GREEN "软链接创建成功: $SYMLINK_PATH -> $INSTALL_DIR/$SCRIPT_NAME"
        return 0
    else
        print_msg $RED "创建软链接失败: $SYMLINK_PATH"
        print_msg $YELLOW "您可以通过 $INSTALL_DIR/$SCRIPT_NAME 运行脚本。"
        return 1 # 不算致命错误
    fi
}


# 创建配置目录和文件
create_config() {
    print_msg $YELLOW "正在创建配置目录和文件..."

    # 创建配置目录
    mkdir -p "$CONFIG_DIR" # 使用引号

    # 创建日志目录
    mkdir -p "$LOG_DIR" # 使用引号
    touch "$LOG_FILE" # 使用引号
    chmod 640 "$LOG_FILE" # 使用引号

    # 创建配置文件
    # 注意：这里的 LOG_FILE 变量引用的是 install.log，但 vpn.sh 脚本里用的是 portforward.log
    # 为了保持一致性，最好让 vpn.sh 使用 /etc/vpn/log/portforward.log
    # 这里暂时保持原样，但建议修改 vpn.sh 中的 LOGFILE 路径
    cat > "$CONFIG_FILE" << EOL
# VPN端口映射配置文件
# 此文件由VPN工具自动管理
# 请勿手动修改

# 版本信息
VERSION="$VERSION"

# 规则标记
RULE_COMMENT="vpn_port_forward"

# iptables规则保存路径
IPTABLES_RULES="/etc/iptables/rules.v4"

# 日志文件路径 (注意：这应与 vpn.sh 中的 LOGFILE 一致)
LOG_FILE="/etc/vpn/log/portforward.log"

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
            # Debian/Ubuntu 通常使用 netfilter-persistent
            if systemctl is-enabled netfilter-persistent &>/dev/null; then
                 print_msg $BLUE "netfilter-persistent 已启用"
            else
                systemctl enable netfilter-persistent
            fi
            systemctl start netfilter-persistent
            ;;
        redhat)
            # RHEL/CentOS/Fedora 使用 iptables-services
            if systemctl is-enabled iptables &>/dev/null; then
                 print_msg $BLUE "iptables 服务已启用"
            else
                systemctl enable iptables
            fi
            systemctl start iptables
            ;;
        arch)
            # Arch Linux 使用 iptables 服务
            if systemctl is-enabled iptables &>/dev/null; then
                 print_msg $BLUE "iptables 服务已启用"
            else
                systemctl enable iptables
            fi
            systemctl start iptables
            ;;
    esac

    # 检查服务状态
    local service_status=1
    case $OS in
        debian)
            systemctl is-active --quiet netfilter-persistent && service_status=0
            ;;
        redhat|arch)
            systemctl is-active --quiet iptables && service_status=0
            ;;
    esac

    if [[ $service_status -eq 0 ]]; then
        print_msg $GREEN "iptables持久化已启用并正在运行"
    else
        print_msg $RED "启用或启动iptables持久化服务失败"
        # 不退出，因为用户可能手动处理或系统不同
    fi
}


# 显示安装完成信息
show_completion() {
    print_msg $GREEN "=========================================="
    print_msg $GREEN "VPN端口映射工具安装完成!"
    print_msg $GREEN "=========================================="
    echo
    print_msg $YELLOW "使用方法:"
    echo "  vpn (推荐)                           # 交互式菜单 (通过软链接)"
    echo "  /etc/vpn/vpn.sh                      # 交互式菜单 (完整路径)"
    echo "  vpn <服务端口> <起始端口> <结束端口> # 直接指定端口"
    echo "  vpn off                              # 取消映射"
    echo "  vpn status                           # 查看状态"
    echo "  vpn update                           # 检查更新"
    echo "  vpn version                          # 显示版本"
    echo "  vpn help                             # 显示帮助"
    echo ""
    print_msg $BLUE "更新安装脚本:"
    echo "  wget -N https://raw.githubusercontent.com/PanJX02/PortMapping/refs/heads/main/install.sh && sudo bash install.sh"
    echo
    print_msg $YELLOW "示例:"
    echo "  sudo vpn                     # 交互式输入 (推荐)"
    echo "  sudo vpn 8080 10000 20000    # 将外部10000-20000端口映射到内部8080端口"
    echo "  sudo vpn off                 # 取消映射"
    echo
    print_msg $BLUE "项目地址: https://github.com/PanJX02/PortMapping"
    echo
    print_msg $BLUE "注意: 请确保 /usr/local/bin 在您的 PATH 环境变量中。"
    print_msg $BLUE "      您可以通过运行 'echo \$PATH' 来检查。"
}


# 创建定时任务 (如果 vpn.sh 支持 --cron 参数)
# 注意：根据您提供的 vpn.sh 内容，它似乎不支持 update --cron。
# 如果您希望保留此功能，请确保 vpn.sh 实现了相应的逻辑。
# 否则，可以考虑移除此部分或修改为调用检查更新的命令。
create_cron_job() {
    print_msg $YELLOW "正在设置自动更新检查..."
    # 假设 vpn.sh 有一个 update 命令可以静默运行或记录日志
    # 这里我们尝试设置一个每周日 midnight 运行的 cron job
    # 它会调用脚本的 update 功能，并将输出重定向到日志

    # 检查 crontab 是否可用
    if command -v crontab &> /dev/null; then
        # 获取当前用户的 crontab 内容 (安装脚本以 root 运行，所以是 root 的 crontab)
        local current_crontab=$(crontab -l 2>/dev/null || echo "")

        # 检查是否已存在相同的任务
        if echo "$current_crontab" | grep -qF "$INSTALL_DIR/$SCRIPT_NAME update"; then
            print_msg $BLUE "自动更新任务已存在，跳过创建。"
        else
            # 创建新的 crontab 条目
            # 使用 here document 追加新任务
            { echo "$current_crontab"; echo "# VPN Port Mapping Tool Auto-Update (每周日凌晨1点)"; echo "0 1 * * 0 $INSTALL_DIR/$SCRIPT_NAME update >> $LOG_DIR/cron_update.log 2>&1"; } | crontab -
            print_msg $GREEN "自动更新检查已设置为每周日凌晨1点执行 (日志: $LOG_DIR/cron_update.log)"
        fi
    else
        print_msg $YELLOW "系统未安装 crontab，跳过定时任务设置"
    fi
}


# 备份现有配置
backup_config() {
    if [[ -f "$CONFIG_FILE" ]]; then # 使用引号
        print_msg $YELLOW "发现现有配置，正在备份..."
        local backup_name="${CONFIG_FILE}.backup.$(date +%Y%m%d%H%M%S)"
        cp "$CONFIG_FILE" "$backup_name" # 使用引号
        print_msg $GREEN "配置备份完成: $backup_name"
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
    # 尝试创建软链接
    local symlink_created=false
    if create_symlink; then
        symlink_created=true
    fi
    enable_persistence
    # create_cron_job # 根据 vpn.sh 实际功能决定是否启用
    show_completion

    # 记录安装日志
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] VPN端口映射工具 v$VERSION 安装成功" >> "$LOG_FILE" # 使用引号
}

# 执行主流程
main "$@" # 传递参数给 main 函数
