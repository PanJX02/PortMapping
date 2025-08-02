#!/bin/bash

# VPN端口映射工具
# 作者: AI Assistant
# 版本: 1.0.0
# 日期: 2025-08-01

# 配置信息
VERSION="1.0.2"
SCRIPTURL="https://raw.githubusercontent.com/PanJX02/PortMappingPortMapping/refs/heads/main/vpn.sh"
INSTALLDIR="/usr/local/bin"
SCRIPTNAME="vpn"
CONFIGDIR="/etc/vpn"
CONFIGFILE="$CONFIGDIR/portforward.conf"
IPTABLESRULES="/etc/iptables/rules.v4"
RULECOMMENT="VPNPORTFORWARD"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 打印带颜色的消息
printmsg() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# 检查root权限
checkroot() {
    if [[ $EUID -ne 0 ]]; then
        printmsg $RED "错误: 此脚本需要root权限运行"
        exit 1
    fi
}

# 检查更新
checkupdate() {
    printmsg $YELLOW "检查更新..."
    local remote_version=$(curl -s -L $SCRIPTURL | grep "^VERSION=" | cut -d'"' -f2)
    
    if [[ -z "$remote_version" ]]; then
        printmsg $RED "无法获取远程版本信息"
        return 1
    fi
    
    if [[ "$VERSION" != "$remote_version" ]]; then
        printmsg $YELLOW "发现新版本: $remote_version (当前版本: $VERSION)"
        read -p "是否要更新? [y/N]: " update_choice
        if [[ "$update_choice" =~ ^[Yy]$ ]]; then
            printmsg $GREEN "正在更新..."
            curl -s -L $SCRIPTURL -o $INSTALLDIR/$SCRIPTNAME
            chmod +x $INSTALLDIR/$SCRIPTNAME
            printmsg $GREEN "更新完成! 新版本: $remote_version"
            exit 0
        else
            printmsg $BLUE "取消更新"
        fi
    else
        printmsg $GREEN "当前已是最新版本: $VERSION"
    fi
}

# 显示版本信息
showversion() {
    printmsg $BLUE "VPN端口映射工具 v$VERSION"
    printmsg $BLUE "作者: AI Assistant"
    printmsg $BLUE "项目地址: https://github.com/PanJX02/PortMappingPortMapping"
}

# 显示帮助信息
showhelp() {
    showversion
    echo
    printmsg $BLUE "用法: $SCRIPTNAME [选项] [参数]"
    echo
    printmsg $BLUE "选项:"
    printmsg $GREEN "  无参数         进入交互式菜单"
    printmsg $GREEN "  <服务端口> <起始端口> <结束端口>  添加端口映射"
    printmsg $GREEN "  off            取消所有端口映射"
    printmsg $GREEN "  status         显示当前映射状态"
    printmsg $GREEN "  version        显示版本信息"
    printmsg $GREEN "  update         检查并更新脚本"
    printmsg $GREEN "  uninstall      卸载VPN端口映射工具"
    printmsg $GREEN "  help           显示此帮助信息"
    echo
    printmsg $BLUE "示例:"
    printmsg $GREEN "  sudo vpn                     进入交互式菜单"
    printmsg $GREEN "  sudo vpn 8080 10000 20000   映射10000-20000端口到8080"
    printmsg $GREEN "  sudo vpn off                 取消所有映射"
    printmsg $GREEN "  sudo vpn status              查看当前状态"
    printmsg $GREEN "  sudo vpn update              检查更新"
    printmsg $GREEN "  sudo vpn uninstall           卸载工具"
}

# 添加iptables规则
addrules() {
    local service_port=$1
    local start_port=$2
    local end_port=$3
    
    # 清除旧规则
    deleterules
    
    # 添加新规则 (仅UDP)
    iptables -t nat -A PREROUTING -p udp --dport $start_port:$end_port -j DNAT --to-destination :$service_port -m comment --comment "$RULECOMMENT"
    
    # 保存规则
    if command -v netfilter-persistent &> /dev/null; then
        netfilter-persistent save
    elif command -v iptables-save &> /dev/null; then
        iptables-save > $IPTABLESRULES
    fi
    
    # 保存配置
    echo "$service_port $start_port $end_port" > $CONFIGFILE
    
    printmsg $GREEN "端口映射已添加: $start_port-$end_port -> $service_port"
}

# 删除iptables规则
deleterules() {
    # 查找并删除规则
    while read -r rule; do
        if [[ -n "$rule" ]]; then
            iptables -t nat -D $rule
        fi
    done < <(iptables -t nat -L PREROUTING --line-numbers | grep "$RULECOMMENT" | awk '{print $1}' | sort -nr)
    
    # 保存规则
    if command -v netfilter-persistent &> /dev/null; then
        netfilter-persistent save
    elif command -v iptables-save &> /dev/null; then
        iptables-save > $IPTABLESRULES
    fi
    
    # 清除配置
    > $CONFIGFILE
    
    printmsg $GREEN "所有端口映射已删除"
}

# 显示当前状态
showstatus() {
    printmsg $BLUE "===== 当前端口映射状态 ====="
    echo
    
    if [[ -f $CONFIGFILE ]] && [[ -s $CONFIGFILE ]]; then
        local service_port start_port end_port
        read service_port start_port end_port < $CONFIGFILE
        
        printmsg $GREEN "✓ 活动映射已配置"
        echo
        printmsg $BLUE "映射详情:"
        echo "  └─ 端口范围: $start_port-$end_port"
        echo "  └─ 服务端口: $service_port"
        echo "  └─ 协议类型: UDP"
        echo
        
        # 显示iptables规则
        printmsg $BLUE "iptables规则详情:"
        iptables -t nat -L PREROUTING | grep "$RULECOMMENT"
    else
        printmsg $YELLOW "✗ 当前没有活动的端口映射"
        echo
        printmsg $BLUE "您可以通过以下方式添加映射:"
        echo "  1. 使用交互式菜单中的选项 1"
        echo "  2. 直接运行命令: $SCRIPTNAME <服务端口> <起始端口> <结束端口>"
        echo
        printmsg $BLUE "示例: $SCRIPTNAME 8080 10000 20000"
    fi
    echo
}

# 显示交互式菜单
showmenu() {
    while true; do
        clear
        showversion
        echo
        printmsg $BLUE "===== VPN端口映射工具菜单 ====="
        echo
        printmsg $GREEN "1. 添加/修改端口映射"
        printmsg $GREEN "2. 取消所有端口映射"
        printmsg $GREEN "3. 查看当前映射状态"
        printmsg $GREEN "4. 检查更新"
        printmsg $GREEN "5. 显示版本信息"
        printmsg $GREEN "6. 卸载VPN端口映射工具"
        printmsg $GREEN "0. 退出"
        echo
        read -p "请选择操作 [0-6]: " choice
        
        case $choice in
            1)
                echo
                read -p "请输入服务端口: " service_port
                read -p "请输入起始端口: " start_port
                read -p "请输入结束端口: " end_port
                
                # 验证端口
                if [[ ! "$service_port" =~ ^[0-9]+$ ]] || [[ "$service_port" -lt 1 ]] || [[ "$service_port" -gt 65535 ]]; then
                    printmsg $RED "错误: 服务端口必须在1-65535范围内"
                    read -p "按Enter键继续..."
                    continue
                fi
                
                if [[ ! "$start_port" =~ ^[0-9]+$ ]] || [[ "$start_port" -lt 1 ]] || [[ "$start_port" -gt 65535 ]]; then
                    printmsg $RED "错误: 起始端口必须在1-65535范围内"
                    read -p "按Enter键继续..."
                    continue
                fi
                
                if [[ ! "$end_port" =~ ^[0-9]+$ ]] || [[ "$end_port" -lt 1 ]] || [[ "$end_port" -gt 65535 ]]; then
                    printmsg $RED "错误: 结束端口必须在1-65535范围内"
                    read -p "按Enter键继续..."
                    continue
                fi
                
                if [[ "$start_port" -gt "$end_port" ]]; then
                    printmsg $RED "错误: 起始端口不能大于结束端口"
                    read -p "按Enter键继续..."
                    continue
                fi
                
                addrules "$service_port" "$start_port" "$end_port"
                read -p "按Enter键继续..."
                ;;
            2)
                deleterules
                read -p "按Enter键继续..."
                ;;
            3)
                showstatus
                read -p "按Enter键继续..."
                ;;
            4)
                checkupdate
                read -p "按Enter键继续..."
                ;;
            5)
                showversion
                read -p "按Enter键继续..."
                ;;
            6)
                echo
                printmsg $RED "警告: 此操作将完全卸载VPN端口映射工具!"
                printmsg $RED "所有配置和规则将被删除!"
                read -p "确定要继续吗? [y/N]: " confirm
                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    uninstall
                    exit 0
                else
                    printmsg $BLUE "取消卸载"
                    read -p "按Enter键继续..."
                fi
                ;;
            0)
                printmsg $BLUE "退出程序"
                exit 0
                ;;
            *)
                printmsg $RED "无效选择，请重新输入"
                read -p "按Enter键继续..."
                ;;
        esac
    done
}

# 卸载函数
uninstall() {
    printmsg $YELLOW "正在卸载VPN端口映射工具..."
    
    # 删除所有端口映射规则
    printmsg $YELLOW "删除所有端口映射规则..."
    deleterules
    
    # 删除配置文件和目录
    printmsg $YELLOW "删除配置文件和目录..."
    if [[ -d "$CONFIGDIR" ]]; then
        rm -rf "$CONFIGDIR"
    fi
    
    # 删除主脚本文件
    printmsg $YELLOW "删除主脚本文件..."
    if [[ -f "$INSTALLDIR/$SCRIPTNAME" ]]; then
        rm -f "$INSTALLDIR/$SCRIPTNAME"
    fi
    
    printmsg $GREEN "VPN端口映射工具已成功卸载!"
    printmsg $BLUE "如需重新安装，请运行: wget -N https://raw.githubusercontent.com/PanJX02/PortMappingPortMapping/refs/heads/main/install.sh && sudo bash install.sh"
}

# 主程序
main() {
    # 检查root权限
    checkroot
    
    # 确保配置目录存在
    mkdir -p "$CONFIGDIR"
    
    # 处理命令行参数
    case $# in
        0)
            showmenu
            ;;
        1)
            case $1 in
                "off")
                    deleterules
                    ;;
                "status")
                    showstatus
                    ;;
                "version")
                    showversion
                    ;;
                "update")
                    checkupdate
                    ;;
                "help")
                    showhelp
                    ;;
                "uninstall")
                    printmsg $RED "警告: 此操作将完全卸载VPN端口映射工具!"
                    printmsg $RED "所有配置和规则将被删除!"
                    read -p "确定要继续吗? [y/N]: " confirm
                    if [[ "$confirm" =~ ^[Yy]$ ]]; then
                        uninstall
                    else
                        printmsg $BLUE "取消卸载"
                    fi
                    ;;
                *)
                    printmsg $RED "错误: 未知参数 '$1'"
                    showhelp
                    exit 1
                    ;;
            esac
            ;;
        3)
            # 验证端口参数
            if [[ ! "$1" =~ ^[0-9]+$ ]] || [[ "$1" -lt 1 ]] || [[ "$1" -gt 65535 ]]; then
                printmsg $RED "错误: 服务端口必须在1-65535范围内"
                exit 1
            fi
            
            if [[ ! "$2" =~ ^[0-9]+$ ]] || [[ "$2" -lt 1 ]] || [[ "$2" -gt 65535 ]]; then
                printmsg $RED "错误: 起始端口必须在1-65535范围内"
                exit 1
            fi
            
            if [[ ! "$3" =~ ^[0-9]+$ ]] || [[ "$3" -lt 1 ]] || [[ "$3" -gt 65535 ]]; then
                printmsg $RED "错误: 结束端口必须在1-65535范围内"
                exit 1
            fi
            
            if [[ "$2" -gt "$3" ]]; then
                printmsg $RED "错误: 起始端口不能大于结束端口"
                exit 1
            fi
            
            addrules "$1" "$2" "$3"
            ;;
        *)
            printmsg $RED "错误: 参数数量不正确"
            showhelp
            exit 1
            ;;
    esac
}

# 执行主程序
main "$@"
