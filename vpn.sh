#!/bin/bash
# VPN端口映射工具
# 作者: PanJX02
# 版本: 1.3.1
# 日期: 2025-08-02
# 配置信息
VERSION="1.3.1"
SCRIPTURL="https://raw.githubusercontent.com/PanJX02/PortMapping/refs/heads/main/vpn.sh"
# --- 修改为与安装脚本一致的路径 ---
INSTALLDIR="/etc/vpn"
SCRIPTNAME="vpn.sh"
# -----------------------------------
CONFIGDIR="/etc/vpn"
CONFIGFILE="$CONFIGDIR/portforward.conf"
IPTABLESRULES="/etc/iptables/rules.v4"
RULECOMMENT="VPNPORTFORWARD"
# 日志文件路径
LOGFILE="$CONFIGDIR/log/portforward.log"
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
# 写入日志的函数
log_action() {
    local message=$1
    # 确保日志目录存在
    mkdir -p "$(dirname "$LOGFILE")" 2>/dev/null
    # 写入带时间戳的日志
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $message" >> "$LOGFILE"
    # 可选：同时在终端显示 (取消注释下面这行)
    # echo "$(date '+%Y-%m-%d %H:%M:%S') - $message"
}
# 检查root权限
checkroot() {
    if [[ $EUID -ne 0 ]]; then
        printmsg $RED "错误: 此脚本需要root权限运行"
        log_action "ERROR: Root permission required to run the script"
        exit 1
    fi
}
# 检查更新
checkupdate() {
    printmsg $YELLOW "检查更新..."
    log_action "Checking for updates..."
    local remote_version=$(curl -s -L $SCRIPTURL | grep "^VERSION=" | cut -d'"' -f2)
    if [[ -z "$remote_version" ]]; then
        printmsg $RED "无法获取远程版本信息"
        log_action "ERROR: Failed to retrieve remote version information"
        return 1
    fi
    if [[ "$VERSION" != "$remote_version" ]]; then
        printmsg $YELLOW "发现新版本: $remote_version (当前版本: $VERSION)"
        log_action "New version found: $remote_version (Current version: $VERSION)"
        read -p "是否要更新? [y/N]: " update_choice
        if [[ "$update_choice" =~ ^[Yy]$ ]]; then
            printmsg $GREEN "正在更新..."
            log_action "Updating script..."
            curl -s -L $SCRIPTURL -o $INSTALLDIR/$SCRIPTNAME
            chmod +x $INSTALLDIR/$SCRIPTNAME
            printmsg $GREEN "更新完成! 新版本: $remote_version"
            log_action "Update completed! New version: $remote_version"
            exit 0
        else
            printmsg $BLUE "取消更新"
            log_action "Update cancelled by user"
        fi
    else
        printmsg $GREEN "当前已是最新版本: $VERSION"
        log_action "Script is up to date: $VERSION"
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
    printmsg $GREEN "  sudo /etc/vpn/vpn.sh                     进入交互式菜单"
    printmsg $GREEN "  sudo /etc/vpn/vpn.sh 8080 10000 20000   映射10000-20000端口到8080"
    printmsg $GREEN "  sudo /etc/vpn/vpn.sh off                 取消所有映射"
    printmsg $GREEN "  sudo /etc/vpn/vpn.sh status              查看当前状态"
    printmsg $GREEN "  sudo /etc/vpn/vpn.sh update              检查更新"
    printmsg $GREEN "  sudo /etc/vpn/vpn.sh uninstall           卸载工具"
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
            log_action "ERROR: Port range $new_start-$new_end conflicts with existing mapping $start_port-$end_port"
            return 1
        fi
        # 检查服务端口冲突
        if [[ "$new_service" -eq "$service_port" ]]; then
            printmsg $RED "错误: 服务端口 $new_service 已被使用"
            log_action "ERROR: Service port $new_service is already in use"
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
    log_action "Added port mapping: $start_port-$end_port -> $service_port"
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
    log_action "Deleted port mapping: $start_port-$end_port -> $service_port"
}
# 保存iptables规则
save_iptables_rules() {
    if command -v netfilter-persistent &> /dev/null; then
        netfilter-persistent save
        log_action "Saved iptables rules using netfilter-persistent"
    elif command -v iptables-save &> /dev/null; then
        iptables-save > $IPTABLESRULES
        log_action "Saved iptables rules using iptables-save"
    else
        log_action "WARNING: No method found to save iptables rules persistently"
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
            log_action "ERROR: Invalid service port entered: $service_port"
            read -p "按Enter键继续..."
            continue
        fi
        if [[ ! "$start_port" =~ ^[0-9]+$ ]] || [[ "$start_port" -lt 1 ]] || [[ "$start_port" -gt 65535 ]]; then
            printmsg $RED "错误: 起始端口必须在1-65535范围内"
            log_action "ERROR: Invalid start port entered: $start_port"
            read -p "按Enter键继续..."
            continue
        fi
        if [[ ! "$end_port" =~ ^[0-9]+$ ]] || [[ "$end_port" -lt 1 ]] || [[ "$end_port" -gt 65535 ]]; then
            printmsg $RED "错误: 结束端口必须在1-65535范围内"
            log_action "ERROR: Invalid end port entered: $end_port"
            read -p "按Enter键继续..."
            continue
        fi
        if [[ "$start_port" -gt "$end_port" ]]; then
            printmsg $RED "错误: 起始端口不能大于结束端口"
            log_action "ERROR: Start port ($start_port) cannot be greater than end port ($end_port)"
            read -p "按Enter键继续..."
            continue
        fi
        # 添加映射
        if add_single_mapping "$service_port" "$start_port" "$end_port"; then
            echo
            printmsg $GREEN "映射添加成功!"
            log_action "User successfully added mapping via menu: $start_port-$end_port -> $service_port"
            echo
            read -p "是否继续添加其他映射? [y/N]: " continue_add
            if [[ ! "$continue_add" =~ ^[Yy]$ ]]; then
                break
            fi
        else
            echo
            log_action "User failed to add mapping via menu: $start_port-$end_port -> $service_port"
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
            log_action "User accessed delete menu, but no active mappings found"
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
                log_action "User exited delete menu"
                return
                ;;
            a|A)
                echo
                printmsg $RED "警告: 此操作将删除所有端口映射!"
                read -p "确定要继续吗? [y/N]: " confirm
                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    delete_all_mappings
                    printmsg $GREEN "所有端口映射已删除"
                    log_action "User deleted ALL port mappings"
                    read -p "按Enter键继续..."
                    return
                else
                    printmsg $BLUE "取消操作"
                    log_action "User cancelled deletion of all mappings"
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
                        log_action "User deleted single mapping: $start_port-$end_port -> $service_port"
                        read -p "按Enter键继续..."
                    else
                        printmsg $BLUE "取消删除"
                        log_action "User cancelled deletion of mapping: $start_port-$end_port -> $service_port"
                        read -p "按Enter键继续..."
                    fi
                else
                    printmsg $RED "无效选择"
                    log_action "ERROR: Invalid choice in delete menu: $choice"
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
    log_action "Deleted ALL port mappings and cleared configuration file"
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
            log_action "WARNING: iptables rule count ($rule_count) does not match config count (${#mappings[@]})"
        fi
        log_action "Status checked: ${#mappings[@]} active mappings, $rule_count iptables rules"
    else
        printmsg $YELLOW "✗ 当前没有活动的端口映射"
        echo
        printmsg $BLUE "您可以通过以下方式添加映射:"
        echo "  1. 使用交互式菜单中的选项 1"
        echo "  2. 直接运行命令: $SCRIPTNAME <服务端口> <起始端口> <结束端口>"
        echo
        printmsg $BLUE "示例: $SCRIPTNAME 8080 10000 20000"
        log_action "Status checked: No active mappings found"
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
                log_action "User selected menu option 1: Add port mapping"
                add_mapping_menu
                ;;
            2)
                log_action "User selected menu option 2: Manage port mappings"
                delete_mapping_menu
                ;;
            3)
                log_action "User selected menu option 3: Show status"
                showstatus
                read -p "按Enter键继续..."
                ;;
            4)
                log_action "User selected menu option 4: Check for updates"
                checkupdate
                read -p "按Enter键继续..."
                ;;
            5)
                log_action "User selected menu option 5: Show version"
                showversion
                read -p "按Enter键继续..."
                ;;
            6)
                echo
                printmsg $RED "警告: 此操作将完全卸载VPN端口映射工具!"
                printmsg $RED "所有配置和规则将被删除!"
                read -p "确定要继续吗? [y/N]: " confirm
                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    log_action "User initiated uninstallation"
                    uninstall
                    exit 0
                else
                    printmsg $BLUE "取消卸载"
                    log_action "User cancelled uninstallation"
                    read -p "按Enter键继续..."
                fi
                ;;
            0)
                printmsg $BLUE "退出程序"
                log_action "User exited the program"
                exit 0
                ;;
            *)
                printmsg $RED "无效选择，请重新输入"
                log_action "ERROR: Invalid menu choice: $choice"
                read -p "按Enter键继续..."
                ;;
        esac
    done
}
# 卸载函数 (已修正)
uninstall() {
    printmsg $YELLOW "正在卸载VPN端口映射工具..."
    log_action "Starting uninstallation process..."

    # 1. 删除所有端口映射规则
    printmsg $YELLOW "删除所有端口映射规则..."
    delete_all_mappings # 这个函数会处理 iptables 规则和清空配置文件

    # 2. 清理配置文件和日志文件 (但不删除主目录)
    printmsg $YELLOW "删除配置文件和日志..."
    if [[ -f "$CONFIGFILE" ]]; then
        rm -f "$CONFIGFILE"
        log_action "Removed configuration file: $CONFIGFILE"
    fi
    if [[ -d "$(dirname "$LOGFILE")" ]]; then
        rm -rf "$(dirname "$LOGFILE")"
        log_action "Removed log directory: $(dirname "$LOGFILE")"
    fi

    # 3. 清理定时任务 (如果存在)
    # printmsg $YELLOW "清理可能存在的定时任务..."
    # (crontab -l 2>/dev/null | grep -v "$INSTALLDIR/$SCRIPTNAME") | crontab -
    # log_action "Attempted to remove cron job."

    # 4. 创建一个后台子进程，延迟执行最后的删除操作
    #    这样可以让主脚本先退出，解除对文件和目录的占用
    (
        # 等待2秒，确保主脚本已经完全退出
        sleep 2
        # 删除脚本文件本身
        if [[ -f "$INSTALLDIR/$SCRIPTNAME" ]]; then
            rm -f "$INSTALLDIR/$SCRIPTNAME"
        fi
        # 删除空的 /etc/vpn 目录
        # 使用 rmdir 尝试删除，如果目录非空（不太可能，但为了安全），则用 rm -rf
        rmdir "$CONFIGDIR" 2>/dev/null || rm -rf "$CONFIGDIR" 2>/dev/null
    ) &

    # 使用 disown 命令，使后台任务与当前终端脱钩，防止终端关闭时任务被杀掉
    # 这确保了即使通过 SSH 执行脚本，关闭窗口后，清理任务也能完成
    disown

    printmsg $GREEN "卸载程序已启动，将在几秒钟内完成清理。"
    log_action "Uninstallation cleanup process has been dispatched."
    printmsg $BLUE "感谢您使用本工具。如需重新安装，请运行安装脚本。"
    printmsg $BLUE "重新安装命令: wget -N https://raw.githubusercontent.com/PanJX02/PortMapping/refs/heads/main/install.sh && sudo bash install.sh"
    
    # 注意：这里函数执行完毕后，主脚本会退出，然后后台的延迟任务开始执行
}

# 初始化配置
initconfig() {
    # 确保配置目录存在
    mkdir -p "$CONFIGDIR"
    # 如果配置文件不存在，创建空配置文件
    if [[ ! -f "$CONFIGFILE" ]]; then
        > "$CONFIGFILE"
        log_action "Created new configuration file: $CONFIGFILE"
    fi
    # 验证并清理无效配置
    if ! validateconfig; then
        printmsg $YELLOW "检测到无效的配置文件，正在清理..."
        log_action "Invalid config file detected, clearing it..."
        > "$CONFIGFILE"
    fi
}
# 主程序
main() {
    # 记录脚本启动
    log_action "Script started with arguments: $*"
    # 检查root权限
    checkroot
    # 初始化配置
    initconfig
    # 处理命令行参数
    case $# in
        0)
            log_action "Entering interactive menu mode"
            showmenu
            ;;
        1)
            case $1 in
                "off")
                    delete_all_mappings
                    printmsg $GREEN "所有端口映射已删除"
                    log_action "All port mappings deleted via 'off' command"
                    ;;
                "status")
                    log_action "Status requested via 'status' command"
                    showstatus
                    ;;
                "version")
                    log_action "Version requested via 'version' command"
                    showversion
                    ;;
                "update")
                    log_action "Update check requested via 'update' command"
                    checkupdate
                    ;;
                "help")
                    log_action "Help requested via 'help' command"
                    showhelp
                    ;;
                "uninstall")
                    log_action "Uninstall requested via 'uninstall' command"
                    printmsg $RED "警告: 此操作将完全卸载VPN端口映射工具!"
                    printmsg $RED "所有配置和规则将被删除!"
                    read -p "确定要继续吗? [y/N]: " confirm
                    if [[ "$confirm" =~ ^[Yy]$ ]]; then
                        log_action "User confirmed uninstallation via command line"
                        uninstall
                    else
                        printmsg $BLUE "取消卸载"
                        log_action "User cancelled uninstallation via command line"
                    fi
                    ;;
                *)
                    printmsg $RED "错误: 未知参数 '$1'"
                    log_action "ERROR: Unknown argument '$1'"
                    showhelp
                    exit 1
                    ;;
            esac
            ;;
        3)
            # 验证端口参数
            if [[ ! "$1" =~ ^[0-9]+$ ]] || [[ "$1" -lt 1 ]] || [[ "$1" -gt 65535 ]]; then
                printmsg $RED "错误: 服务端口必须在1-65535范围内"
                log_action "ERROR: Invalid service port '$1' in command line arguments"
                exit 1
            fi
            if [[ ! "$2" =~ ^[0-9]+$ ]] || [[ "$2" -lt 1 ]] || [[ "$2" -gt 65535 ]]; then
                printmsg $RED "错误: 起始端口必须在1-65535范围内"
                log_action "ERROR: Invalid start port '$2' in command line arguments"
                exit 1
            fi
            if [[ ! "$3" =~ ^[0-9]+$ ]] || [[ "$3" -lt 1 ]] || [[ "$3" -gt 65535 ]]; then
                printmsg $RED "错误: 结束端口必须在1-65535范围内"
                log_action "ERROR: Invalid end port '$3' in command line arguments"
                exit 1
            fi
            if [[ "$2" -gt "$3" ]]; then
                printmsg $RED "错误: 起始端口不能大于结束端口"
                log_action "ERROR: Start port '$2' cannot be greater than end port '$3' in command line arguments"
                exit 1
            fi
            if add_single_mapping "$1" "$2" "$3"; then
                printmsg $GREEN "端口映射添加成功"
                log_action "Port mapping added successfully via command line: $2-$3 -> $1"
            else
                log_action "ERROR: Failed to add port mapping via command line: $2-$3 -> $1"
                exit 1
            fi
            ;;
        *)
            printmsg $RED "错误: 参数数量不正确"
            log_action "ERROR: Incorrect number of arguments: $#"
            showhelp
            exit 1
            ;;
    esac
    # 记录脚本结束
    log_action "Script execution completed"
}
# 执行主程序
main "$@"
