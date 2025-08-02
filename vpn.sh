#!/bin/bash

# VPN端口映射工具
# 作者: PanJX02  
# 版本: 1.1.0
# 日期: 2025-08-02

# 配置信息
VERSION="1.1.0"
SCRIPTURL="https://raw.githubusercontent.com/PanJX02/PortMapping/refs/heads/main/vpn.sh"
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
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
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
    printmsg $BLUE "作者: PanJX02"
    printmsg $BLUE "项目地址: https://github.com/PanJX02/PortMapping"
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

# 生成唯一的规则ID
generate_rule_id() {
    local service_port=$1
    local start_port=$2
    local end_port=$3
    echo "${RULECOMMENT}_${service_port}_${start_port}_${end_port}"
}

# 验证配置文件格式
validateconfig() {
    if [[ ! -f "$CONFIGFILE" ]]; then
        return 1
    fi
    
    # 检查文件是否为空
    if [[ ! -s "$CONFIGFILE" ]]; then
        return 1
    fi
    
    # 检查每一行的格式
    while IFS= read -r line; do
        # 跳过空行和注释行
        if [[ -z "$line" ]] || [[ "$line" =~ ^[[:space:]]*# ]]; then
            continue
        fi
        
        # 验证格式 (应该是三个数字)
        local service_port start_port end_port
        read service_port start_port end_port <<< "$line"
        
        if [[ ! "$service_port" =~ ^[0-9]+$ ]] || [[ ! "$start_port" =~ ^[0-9]+$ ]] || [[ ! "$end_port" =~ ^[0-9]+$ ]]; then
            return 1
        fi
    done < "$CONFIGFILE"
    
    return 0
}

# 读取所有映射配置
read_all_mappings() {
    local mappings=()
    
    if [[ ! -f "$CONFIGFILE" ]] || [[ ! -s "$CONFIGFILE" ]]; then
        echo ""
        return
    fi
    
    while IFS= read -r line; do
        # 跳过空行和注释行
        if [[ -z "$line" ]] || [[ "$line" =~ ^[[:space:]]*# ]]; then
            continue
        fi
        
        local service_port start_port end_port
        read service_port start_port end_port <<< "$line"
        
        # 验证格式
        if [[ "$service_port" =~ ^[0-9]+$ ]] && [[ "$start_port" =~ ^[0-9]+$ ]] && [[ "$end_port" =~ ^[0-9]+$ ]]; then
            mappings+=("$service_port $start_port $end_port")
        fi
    done < "$CONFIGFILE"
    
    printf '%s\n' "${mappings[@]}"
}

# 检查端口范围是否冲突
check_port_conflict() {
    local new_start=$1
    local new_end=$2
    local new_service=$3
    
    local mappings
    readarray -t mappings <<< "$(read_all_mappings)"
    
    for mapping in "${mappings[@]}"; do
        if [[ -z "$mapping" ]]; then
            continue
        fi
        
        local service_port start_port end_port
        read service_port start_port end_port <<< "$mapping"
        
        # 检查端口范围冲突
        if [[ "$new_start" -le "$end_port" ]] && [[ "$new_end" -ge "$start_port" ]]; then
            printmsg $RED "错误: 端口范围 $new_start-$new_end 与现有映射 $start_port-$end_port 冲突"
            return 1
        fi
        
        # 检查服务端口冲突
        if [[ "$new_service" -eq "$service_port" ]]; then
            printmsg $RED "错误: 服务端口 $new_service 已被使用"
            return 1
        fi
    done
    
    return 0
}

# 添加单个端口映射
add_single_mapping() {
    local service_port=$1
    local start_port=$2
    local end_port=$3
    
    # 检查冲突
    if ! check_port_conflict "$start_port" "$end_port" "$service_port"; then
        return 1
    fi
    
    # 生成规则ID
    local rule_id=$(generate_rule_id "$service_port" "$start_port" "$end_port")
    
    # 添加iptables规则
    iptables -t nat -A PREROUTING -p udp --dport $start_port:$end_port -j DNAT --to-destination :$service_port -m comment --comment "$rule_id"
    
    # 保存到配置文件
    mkdir -p "$CONFIGDIR"
    echo "$service_port $start_port $end_port" >> "$CONFIGFILE"
    
    # 保存iptables规则
    save_iptables_rules
    
    printmsg $GREEN "端口映射已添加: $start_port-$end_port -> $service_port"
    return 0
}

# 删除单个端口映射
delete_single_mapping() {
    local service_port=$1
    local start_port=$2
    local end_port=$3
    
    # 生成规则ID
    local rule_id=$(generate_rule_id "$service_port" "$start_port" "$end_port")
    
    # 删除iptables规则
    local rules=$(iptables -t nat -L PREROUTING --line-numbers | grep "$rule_id" | awk '{print $1}' | sort -nr)
    
    if [[ -n "$rules" ]]; then
        while read -r rule; do
            if [[ -n "$rule" ]]; then
                iptables -t nat -D PREROUTING "$rule"
            fi
        done <<< "$rules"
    fi
    
    # 从配置文件中删除
    if [[ -f "$CONFIGFILE" ]]; then
        local temp_file=$(mktemp)
        while IFS= read -r line; do
            if [[ "$line" != "$service_port $start_port $end_port" ]]; then
                echo "$line" >> "$temp_file"
            fi
        done < "$CONFIGFILE"
        mv "$temp_file" "$CONFIGFILE"
    fi
    
    # 保存iptables规则
    save_iptables_rules
    
    printmsg $GREEN "端口映射已删除: $start_port-$end_port -> $service_port"
}

# 保存iptables规则
save_iptables_rules() {
    if command -v netfilter-persistent &> /dev/null; then
        netfilter-persistent save
    elif command -v iptables-save &> /dev/null; then
        iptables-save > $IPTABLESRULES
    fi
}

# 添加端口映射菜单
add_mapping_menu() {
    while true; do
        clear
        printmsg $BLUE "===== 添加端口映射 ====="
        echo
        
        # 显示当前映射
        local mappings
        readarray -t mappings <<< "$(read_all_mappings)"
        
        if [[ ${#mappings[@]} -gt 0 ]] && [[ -n "${mappings[0]}" ]]; then
            printmsg $CYAN "当前已有的映射:"
            local index=1
            for mapping in "${mappings[@]}"; do
                if [[ -n "$mapping" ]]; then
                    local service_port start_port end_port
                    read service_port start_port end_port <<< "$mapping"
                    echo "  $index. $start_port-$end_port -> $service_port (UDP)"
                    ((index++))
                fi
            done
            echo
        fi
        
        printmsg $GREEN "请输入新的端口映射信息:"
        echo
        read -p "服务端口 (目标端口): " service_port
        read -p "起始端口: " start_port
        read -p "结束端口: " end_port
        
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
        
        # 添加映射
        if add_single_mapping "$service_port" "$start_port" "$end_port"; then
            echo
            printmsg $GREEN "映射添加成功!"
            echo
            read -p "是否继续添加其他映射? [y/N]: " continue_add
            if [[ ! "$continue_add" =~ ^[Yy]$ ]]; then
                break
            fi
        else
            echo
            read -p "按Enter键重试..."
        fi
    done
}

# 删除端口映射菜单
delete_mapping_menu() {
    while true; do
        clear
        printmsg $BLUE "===== 管理端口映射 ====="
        echo
        
        # 读取所有映射
        local mappings
        readarray -t mappings <<< "$(read_all_mappings)"
        
        if [[ ${#mappings[@]} -eq 0 ]] || [[ -z "${mappings[0]}" ]]; then
            printmsg $YELLOW "当前没有活动的端口映射"
            read -p "按Enter键返回主菜单..."
            return
        fi
        
        printmsg $CYAN "当前的端口映射:"
        echo
        local index=1
        local valid_mappings=()
        
        for mapping in "${mappings[@]}"; do
            if [[ -n "$mapping" ]]; then
                local service_port start_port end_port
                read service_port start_port end_port <<< "$mapping"
                echo "  $index. $start_port-$end_port -> $service_port (UDP)"
                valid_mappings+=("$mapping")
                ((index++))
            fi
        done
        
        echo
        printmsg $GREEN "选择操作:"
        echo "  1-$((${#valid_mappings[@]})) - 删除指定映射"
        printmsg $RED "  a - 删除所有映射"
        printmsg $BLUE "  0 - 返回主菜单"
        echo
        read -p "请选择 [0-$((${#valid_mappings[@]}))/a]: " choice
        
        case $choice in
            0)
                return
                ;;
            a|A)
                echo
                printmsg $RED "警告: 此操作将删除所有端口映射!"
                read -p "确定要继续吗? [y/N]: " confirm
                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    delete_all_mappings
                    printmsg $GREEN "所有端口映射已删除"
                    read -p "按Enter键继续..."
                    return
                else
                    printmsg $BLUE "取消操作"
                    read -p "按Enter键继续..."
                fi
                ;;
            *)
                if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le "${#valid_mappings[@]}" ]]; then
                    local selected_mapping="${valid_mappings[$((choice-1))]}"
                    local service_port start_port end_port
                    read service_port start_port end_port <<< "$selected_mapping"
                    
                    echo
                    printmsg $YELLOW "确认删除映射: $start_port-$end_port -> $service_port"
                    read -p "确定要删除吗? [y/N]: " confirm
                    if [[ "$confirm" =~ ^[Yy]$ ]]; then
                        delete_single_mapping "$service_port" "$start_port" "$end_port"
                        read -p "按Enter键继续..."
                    else
                        printmsg $BLUE "取消删除"
                        read -p "按Enter键继续..."
                    fi
                else
                    printmsg $RED "无效选择"
                    read -p "按Enter键继续..."
                fi
                ;;
        esac
    done
}

# 删除所有端口映射
delete_all_mappings() {
    # 删除所有相关的iptables规则
    local rules=$(iptables -t nat -L PREROUTING --line-numbers | grep "$RULECOMMENT" | awk '{print $1}' | sort -nr)
    
    if [[ -n "$rules" ]]; then
        while read -r rule; do
            if [[ -n "$rule" ]]; then
                iptables -t nat -D PREROUTING "$rule"
            fi
        done <<< "$rules"
    fi
    
    # 清空配置文件
    if [[ -f "$CONFIGFILE" ]]; then
        > "$CONFIGFILE"
    fi
    
    # 保存iptables规则
    save_iptables_rules
}

# 显示当前状态
showstatus() {
    printmsg $BLUE "===== 当前端口映射状态 ====="
    echo
    
    local mappings
    readarray -t mappings <<< "$(read_all_mappings)"
    
    if [[ ${#mappings[@]} -gt 0 ]] && [[ -n "${mappings[0]}" ]]; then
        printmsg $GREEN "✓ 活动映射已配置 (共 ${#mappings[@]} 条)"
        echo
        printmsg $BLUE "映射详情:"
        local index=1
        
        for mapping in "${mappings[@]}"; do
            if [[ -n "$mapping" ]]; then
                local service_port start_port end_port
                read service_port start_port end_port <<< "$mapping"
                echo "  $index. 端口范围: $start_port-$end_port -> 服务端口: $service_port (UDP)"
                ((index++))
            fi
        done
        
        echo
        # 显示iptables规则统计
        local rule_count=$(iptables -t nat -L PREROUTING | grep -c "$RULECOMMENT")
        printmsg $BLUE "iptables规则: $rule_count 条活动规则"
        
        # 检查规则一致性
        if [[ "$rule_count" -ne "${#mappings[@]}" ]]; then
            printmsg $YELLOW "警告: iptables规则数量与配置不匹配，建议重新添加映射"
        fi
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
        printmsg $GREEN "1. 添加端口映射"
        printmsg $YELLOW "2. 管理端口映射"
        printmsg $CYAN "3. 查看当前映射状态"
        printmsg $PURPLE "4. 检查更新"
        printmsg $BLUE "5. 显示版本信息"
        printmsg $RED "6. 卸载VPN端口映射工具"
        printmsg $NC "0. 退出"
        echo
        read -p "请选择操作 [0-6]: " choice
        
        case $choice in
            1)
                add_mapping_menu
                ;;
            2)
                delete_mapping_menu
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
    delete_all_mappings
    
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
    printmsg $BLUE "如需重新安装，请运行: wget -N https://raw.githubusercontent.com/PanJX02/PortMapping/refs/heads/main/install.sh && sudo bash install.sh"
}

# 初始化配置
initconfig() {
    # 确保配置目录存在
    mkdir -p "$CONFIGDIR"
    
    # 如果配置文件不存在，创建空配置文件
    if [[ ! -f "$CONFIGFILE" ]]; then
        > "$CONFIGFILE"
    fi
    
    # 验证并清理无效配置
    if ! validateconfig; then
        printmsg $YELLOW "检测到无效的配置文件，正在清理..."
        > "$CONFIGFILE"
    fi
}

# 主程序
main() {
    # 检查root权限
    checkroot
    
    # 初始化配置
    initconfig
    
    # 处理命令行参数
    case $# in
        0)
            showmenu
            ;;
        1)
            case $1 in
                "off")
                    delete_all_mappings
                    printmsg $GREEN "所有端口映射已删除"
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
            
            if add_single_mapping "$1" "$2" "$3"; then
                printmsg $GREEN "端口映射添加成功"
            else
                exit 1
            fi
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