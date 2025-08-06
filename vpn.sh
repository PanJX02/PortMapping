#!/bin/bash
# VPN端口映射工具 (支持 IPv4 & IPv6)
# 作者: PanJX02 
# 版本: 2.0.0
# 日期: 2025-08-03

# --- 配置信息 ---
VERSION="2.0.0"
SCRIPTURL="https://raw.githubusercontent.com/PanJX02/PortMapping/refs/heads/main/vpn.sh" # 假设新版在此
INSTALLDIR="/etc/vpn"
SCRIPTNAME="vpn.sh"
CONFIGDIR="/etc/vpn"
CONFIGFILE="$CONFIGDIR/portforward.conf"
IPTABLESRULES="/etc/iptables/rules.v4"
IP6TABLESRULES="/etc/iptables/rules.v6"
RULECOMMENT_PREFIX="VPNPORTFORWARD"

# --- 日志和颜色 ---
LOGFILE="$CONFIGDIR/log/portforward.log"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# --- 辅助函数 ---
printmsg() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

log_action() {
    local message=$1
    mkdir -p "$(dirname "$LOGFILE")" 2>/dev/null
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $message" >> "$LOGFILE"
}

checkroot() {
    if [[ $EUID -ne 0 ]]; then
        printmsg $RED "错误: 此脚本需要root权限运行"
        log_action "ERROR: Root permission required"
        exit 1
    fi
}

# --- 核心功能函数 ---

# 生成唯一的规则ID
generate_rule_id() {
    local protocol=$1
    local service_port=$2
    local start_port=$3
    local end_port=$4
    echo "${RULECOMMENT_PREFIX}_${protocol}_${service_port}_${start_port}_${end_port}"
}

# 验证配置文件格式
validateconfig() {
    if [[ ! -f "$CONFIGFILE" ]] || [[ ! -s "$CONFIGFILE" ]]; then return 1; fi
    while IFS= read -r line; do
        if [[ -z "$line" ]] || [[ "$line" =~ ^[[:space:]]*# ]]; then continue; fi
        local proto svc_port start_port end_port
        read proto svc_port start_port end_port <<< "$line"
        if [[ ! "$proto" =~ ^(ipv4|ipv6|all)$ ]] || [[ ! "$svc_port" =~ ^[0-9]+$ ]] || [[ ! "$start_port" =~ ^[0-9]+$ ]] || [[ ! "$end_port" =~ ^[0-9]+$ ]]; then
            return 1
        fi
    done < "$CONFIGFILE"
    return 0
}

# 读取所有映射配置
read_all_mappings() {
    if [[ ! -f "$CONFIGFILE" ]] || [[ ! -s "$CONFIGFILE" ]]; then
        echo ""
        return
    fi
    # 过滤掉注释和空行
    grep -Ev '^[[:space:]]*#|^[[:space:]]*$' "$CONFIGFILE"
}

# 检查端口范围是否冲突
check_port_conflict() {
    local new_protocol=$1
    local new_service=$2
    local new_start=$3
    local new_end=$4
    
    local mappings
    readarray -t mappings <<< "$(read_all_mappings)"
    
    for mapping in "${mappings[@]}"; do
        if [[ -z "$mapping" ]]; then continue; fi
        
        local proto svc_port start_port end_port
        read proto svc_port start_port end_port <<< "$mapping"

        # 检查指定协议的冲突
        if [[ "$new_protocol" == "$proto" ]] || [[ "$new_protocol" == "all" ]] || [[ "$proto" == "all" ]]; then
            # 检查端口范围冲突
            if [[ "$new_start" -le "$end_port" ]] && [[ "$new_end" -ge "$start_port" ]]; then
                printmsg $RED "错误: 端口范围 $new_start-$new_end 与现有 ${proto} 映射 $start_port-$end_port 冲突"
                log_action "ERROR: Port range conflict for ${proto}: new $new_start-$new_end vs existing $start_port-$end_port"
                return 1
            fi
            # 检查服务端口冲突
            if [[ "$new_service" -eq "$svc_port" ]]; then
                printmsg $RED "错误: 服务端口 $new_service 已被用于 ${proto} 协议的映射"
                log_action "ERROR: Service port $new_service already used for ${proto}"
                return 1
            fi
        fi
    done
    return 0
}

# 保存iptables/ip6tables规则
save_netfilter_rules() {
    if command -v netfilter-persistent &> /dev/null; then
        netfilter-persistent save >/dev/null 2>&1
        log_action "Saved rules using netfilter-persistent"
    else
        if command -v iptables-save &> /dev/null; then
            iptables-save > "$IPTABLESRULES"
            log_action "Saved IPv4 rules to $IPTABLESRULES"
        else
            log_action "WARNING: iptables-save command not found. IPv4 rules not saved."
        fi
        if command -v ip6tables-save &> /dev/null; then
            # 确保 ip6tables NAT 表已加载
            modprobe ip6_tables
            modprobe ip6table_nat
            ip6tables-save > "$IP6TABLESRULES"
            log_action "Saved IPv6 rules to $IP6TABLESRULES"
        else
            log_action "WARNING: ip6tables-save command not found. IPv6 rules not saved."
        fi
    fi
}

# 添加单个端口映射
add_single_mapping() {
    local protocol=$1
    local service_port=$2
    local start_port=$3
    local end_port=$4

    if ! check_port_conflict "$protocol" "$service_port" "$start_port" "$end_port"; then
        return 1
    fi

    local added=0
    # 添加IPv4规则
    if [[ "$protocol" == "ipv4" ]] || [[ "$protocol" == "all" ]]; then
        local rule_id=$(generate_rule_id "ipv4" "$service_port" "$start_port" "$end_port")
        iptables -t nat -A PREROUTING -p udp --dport "$start_port":"$end_port" -j DNAT --to-destination ":$service_port" -m comment --comment "$rule_id"
        printmsg $GREEN "IPv4 映射已添加: $start_port-$end_port -> $service_port"
        log_action "Added IPv4 mapping: $start_port-$end_port -> $service_port"
        added=1
    fi

    # 添加IPv6规则
    if [[ "$protocol" == "ipv6" ]] || [[ "$protocol" == "all" ]]; then
        # 确保 IPv6 NAT 相关内核模块已加载
        modprobe ip6_tables
        modprobe ip6table_nat
        
        local rule_id=$(generate_rule_id "ipv6" "$service_port" "$start_port" "$end_port")
        ip6tables -t nat -A PREROUTING -p udp --dport "$start_port":"$end_port" -j DNAT --to-destination ":$service_port" -m comment --comment "$rule_id"
        printmsg $GREEN "IPv6 映射已添加: $start_port-$end_port -> $service_port"
        log_action "Added IPv6 mapping: $start_port-$end_port -> $service_port"
        added=1
    fi

    if [[ "$added" -eq 1 ]]; then
        mkdir -p "$CONFIGDIR"
        echo "$protocol $service_port $start_port $end_port" >> "$CONFIGFILE"
        save_netfilter_rules
        return 0
    else
        printmsg $RED "错误: 无效的协议 '$protocol'"
        log_action "ERROR: Invalid protocol '$protocol' for add_single_mapping"
        return 1
    fi
}

# 删除单个端口映射
delete_single_mapping() {
    local protocol=$1
    local service_port=$2
    local start_port=$3
    local end_port=$4

    # 删除IPv4规则
    if [[ "$protocol" == "ipv4" ]] || [[ "$protocol" == "all" ]]; then
        local rule_id_v4=$(generate_rule_id "ipv4" "$service_port" "$start_port" "$end_port")
        local rules_v4=$(iptables -t nat -L PREROUTING --line-numbers | grep "$rule_id_v4" | awk '{print $1}' | sort -rn)
        if [[ -n "$rules_v4" ]]; then
            while read -r rule; do iptables -t nat -D PREROUTING "$rule"; done <<< "$rules_v4"
            printmsg $GREEN "IPv4 映射已删除: $start_port-$end_port -> $service_port"
            log_action "Deleted IPv4 mapping: $start_port-$end_port -> $service_port"
        fi
    fi

    # 删除IPv6规则
    if [[ "$protocol" == "ipv6" ]] || [[ "$protocol" == "all" ]]; then
        local rule_id_v6=$(generate_rule_id "ipv6" "$service_port" "$start_port" "$end_port")
        local rules_v6=$(ip6tables -t nat -L PREROUTING --line-numbers 2>/dev/null | grep "$rule_id_v6" | awk '{print $1}' | sort -rn)
        if [[ -n "$rules_v6" ]]; then
            while read -r rule; do ip6tables -t nat -D PREROUTING "$rule"; done <<< "$rules_v6"
            printmsg $GREEN "IPv6 映射已删除: $start_port-$end_port -> $service_port"
            log_action "Deleted IPv6 mapping: $start_port-$end_port -> $service_port"
        fi
    fi

    # 从配置文件中删除
    if [[ -f "$CONFIGFILE" ]]; then
        local temp_file=$(mktemp)
        grep -v "^$protocol $service_port $start_port $end_port$" "$CONFIGFILE" > "$temp_file"
        mv "$temp_file" "$CONFIGFILE"
    fi
    save_netfilter_rules
}

# 删除所有端口映射
delete_all_mappings() {
    # 删除所有相关的iptables规则
    local rules_v4=$(iptables -t nat -L PREROUTING --line-numbers | grep "$RULECOMMENT_PREFIX" | awk '{print $1}' | sort -rn)
    if [[ -n "$rules_v4" ]]; then
        while read -r rule; do iptables -t nat -D PREROUTING "$rule"; done <<< "$rules_v4"
    fi
    # 删除所有相关的ip6tables规则
    local rules_v6=$(ip6tables -t nat -L PREROUTING --line-numbers 2>/dev/null | grep "$RULECOMMENT_PREFIX" | awk '{print $1}' | sort -rn)
    if [[ -n "$rules_v6" ]]; then
        while read -r rule; do ip6tables -t nat -D PREROUTING "$rule"; done <<< "$rules_v6"
    fi
    
    # 清空配置文件
    if [[ -f "$CONFIGFILE" ]]; then > "$CONFIGFILE"; fi
    
    save_netfilter_rules
    log_action "Deleted ALL port mappings (IPv4 & IPv6) and cleared configuration file"
}

# --- 菜单和用户交互 ---

# 添加端口映射菜单
add_mapping_menu() {
    clear
    printmsg $BLUE "===== 添加端口映射 ====="
    echo
    read -p "服务端口 (目标端口): " service_port
    read -p "起始端口: " start_port
    read -p "结束端口: " end_port
    echo
    printmsg $CYAN "请选择协议:"
    echo "  1. IPv4"
    echo "  2. IPv6"
    echo "  3. 两者(all)"
    read -p "请选择 [1-3, 默认 1]: " proto_choice
    
    local protocol
    case $proto_choice in
        2) protocol="ipv6" ;;
        3) protocol="all" ;;
        *) protocol="ipv4" ;;
    esac

    # 验证端口
    for port in $service_port $start_port $end_port; do
        if ! [[ "$port" =~ ^[0-9]+$ ]] || [[ "$port" -lt 1 ]] || [[ "$port" -gt 65535 ]]; then
            printmsg $RED "错误: 端口 '$port' 无效，必须是 1-65535 之间的数字"
            log_action "ERROR: Invalid port entered: $port"
            read -p "按Enter键返回..."
            return
        fi
    done
    if [[ "$start_port" -gt "$end_port" ]]; then
        printmsg $RED "错误: 起始端口不能大于结束端口"
        read -p "按Enter键返回..."
        return
    fi
    
    if add_single_mapping "$protocol" "$service_port" "$start_port" "$end_port"; then
        printmsg $GREEN "映射添加成功!"
    else
        printmsg $RED "映射添加失败，请检查冲突或日志。"
    fi
    read -p "按Enter键继续..."
}

# 管理/删除端口映射菜单
delete_mapping_menu() {
    while true; do
        clear
        printmsg $BLUE "===== 管理端口映射 ====="
        local mappings
        readarray -t mappings <<< "$(read_all_mappings)"
        if [[ ${#mappings[@]} -eq 0 ]] || [[ -z "${mappings[0]}" ]]; then
            printmsg $YELLOW "当前没有活动的端口映射"
            read -p "按Enter键返回主菜单..."
            return
        fi
        
        printmsg $CYAN "当前的端口映射:"
        local i=1
        for mapping in "${mappings[@]}"; do
            read proto svc_port start_port end_port <<< "$mapping"
            printf "  %-3s %-7s %-20s -> %-5s (UDP)\n" "$i." "[$proto]" "$start_port-$end_port" "$svc_port"
            ((i++))
        done
        echo
        printmsg $GREEN "选择操作: 1-$((${#mappings[@]}))删除指定映射, 'a'删除所有, '0'返回"
        read -p "请选择: " choice

        case $choice in
            0) return ;;
            a|A)
                printmsg $RED "警告: 此操作将删除所有 IPv4 和 IPv6 端口映射!"
                read -p "确定吗? [y/N]: " confirm
                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    delete_all_mappings
                    printmsg $GREEN "所有端口映射已删除"
                    read -p "按Enter键继续..."
                    return
                fi
                ;;
            *)
                if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le "${#mappings[@]}" ]]; then
                    local selected_mapping="${mappings[$((choice-1))]}"
                    read proto svc_port start_port end_port <<< "$selected_mapping"
                    printmsg $YELLOW "确认删除映射: [$proto] $start_port-$end_port -> $svc_port"
                    read -p "确定吗? [y/N]: " confirm
                    if [[ "$confirm" =~ ^[Yy]$ ]]; then
                        delete_single_mapping "$proto" "$svc_port" "$start_port" "$end_port"
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

# 显示当前状态
showstatus() {
    printmsg $BLUE "===== 当前端口映射状态 ====="
    local mappings
    readarray -t mappings <<< "$(read_all_mappings)"
    
    if [[ ${#mappings[@]} -eq 0 ]] || [[ -z "${mappings[0]}" ]]; then
        printmsg $YELLOW "✗ 当前没有活动的端口映射"
        log_action "Status checked: No active mappings"
        return
    fi

    printmsg $GREEN "✓ 活动映射已配置 (共 ${#mappings[@]} 条)"
    local i=1
    for mapping in "${mappings[@]}"; do
        read proto svc_port start_port end_port <<< "$mapping"
        printf "  %-3s 协议: %-7s 端口范围: %-20s -> 服务端口: %-5s\n" "$i." "$proto" "$start_port-$end_port" "$svc_port"
        ((i++))
    done
    echo
    
    local rule_count_v4=$(iptables -t nat -L PREROUTING -n | grep -c "$RULECOMMENT_PREFIX")
    local rule_count_v6=$(ip6tables -t nat -L PREROUTING -n 2>/dev/null | grep -c "$RULECOMMENT_PREFIX")
    printmsg $BLUE "iptables 规则: $rule_count_v4 条IPv4规则, $rule_count_v6 条IPv6规则"
    
    local config_count_v4=$(grep -c -E '^(ipv4|all) ' "$CONFIGFILE" 2>/dev/null || echo 0)
    local config_count_v6=$(grep -c -E '^(ipv6|all) ' "$CONFIGFILE" 2>/dev/null || echo 0)
    
    if [[ "$rule_count_v4" -ne "$config_count_v4" ]] || [[ "$rule_count_v6" -ne "$config_count_v6" ]]; then
        printmsg $YELLOW "警告: 防火墙规则数量与配置不匹配，建议使用菜单重新应用规则。"
        log_action "WARNING: Rule/config mismatch. v4 ($rule_count_v4/$config_count_v4), v6 ($rule_count_v6/$config_count_v6)"
    fi
}

# 卸载函数
uninstall() {
    printmsg $YELLOW "正在卸载VPN端口映射工具..."
    log_action "Starting uninstallation process..."

    printmsg $YELLOW "删除所有端口映射规则 (IPv4 & IPv6)..."
    delete_all_mappings

    printmsg $YELLOW "删除配置文件和日志..."
    rm -f "$CONFIGFILE"
    rm -rf "$CONFIGDIR/log"
    log_action "Removed config and log files"

    (
        sleep 2
        rm -f "$INSTALLDIR/$SCRIPTNAME"
        rmdir "$CONFIGDIR" 2>/dev/null || rm -rf "$CONFIGDIR" 2>/dev/null
    ) &
    disown

    printmsg $GREEN "卸载程序已启动，将在几秒钟内完成清理。"
    printmsg $BLUE "感谢您使用本工具。"
}

# 初始化配置
initconfig() {
    mkdir -p "$CONFIGDIR"
    if [[ ! -f "$CONFIGFILE" ]]; then > "$CONFIGFILE"; fi
    if ! validateconfig; then
        printmsg $YELLOW "检测到无效的配置文件，已将其清空。"
        log_action "Invalid config file detected, clearing it."
        > "$CONFIGFILE"
    fi
}

# 显示帮助
showhelp() {
    echo "VPN端口映射工具 v$VERSION (支持IPv4/IPv6)"
    echo "用法: $0 [选项] [参数]"
    echo
    echo "选项:"
    echo "  无参数                进入交互式菜单"
    echo "  <proto> <svc> <start> <end>  添加端口映射 (proto: ipv4|ipv6|all)"
    echo "  off                   取消所有端口映射"
    echo "  status                显示当前映射状态"
    echo "  update                检查并更新脚本"
    echo "  uninstall             卸载工具"
    echo "  help                  显示此帮助信息"
    echo
    echo "示例:"
    echo "  $0 ipv4 8080 10000 20000  # 添加 IPv4 映射"
    echo "  $0 ipv6 8081 20001 30000  # 添加 IPv6 映射"
    echo "  $0 all  8082 40000 50000  # 同时添加 IPv4 和 IPv6 映射"
    echo "  $0 off                     # 取消所有映射"
}

# 主程序
main() {
    log_action "Script started with args: $*"
    checkroot
    initconfig

    case $# in
        0) showmenu ;;
        1)
            case $1 in
                off) delete_all_mappings; printmsg $GREEN "所有端口映射已删除" ;;
                status) showstatus ;;
                update) checkupdate ;; # checkupdate 函数未在此处提供，但保留了接口
                uninstall) 
                  printmsg $RED "警告: 此操作将完全卸载工具!"
                  read -p "确定要继续吗? [y/N]: " confirm
                  [[ "$confirm" =~ ^[Yy]$ ]] && uninstall
                  ;;
                help) showhelp ;;
                *) printmsg $RED "错误: 未知参数 '$1'"; showhelp; exit 1 ;;
            esac
            ;;
        4)
            local protocol=$1 service_port=$2 start_port=$3 end_port=$4
            if [[ ! "$protocol" =~ ^(ipv4|ipv6|all)$ ]]; then
                printmsg $RED "错误: 协议必须是 'ipv4', 'ipv6', 或 'all'"
                exit 1
            fi
            # ... (此处省略了对端口的详细命令行验证，菜单中有)
            if add_single_mapping "$protocol" "$service_port" "$start_port" "$end_port"; then
                printmsg $GREEN "端口映射添加成功"
            else
                printmsg $RED "端口映射添加失败"
                exit 1
            fi
            ;;
        *)
            printmsg $RED "错误: 参数数量不正确"
            showhelp
            exit 1
            ;;
    esac
    log_action "Script execution completed"
}

# 交互式主菜单 (从旧脚本移植)
showmenu() {
    while true; do
        clear
        echo "VPN端口映射工具 v$VERSION (支持IPv4/IPv6)"
        printmsg $BLUE "=================================="
        printmsg $GREEN "1. 添加端口映射"
        printmsg $YELLOW "2. 管理/删除端口映射"
        printmsg $CYAN "3. 查看当前映射状态"
        printmsg $PURPLE "4. 检查更新"
        printmsg $RED "5. 卸载工具"
        printmsg $NC "0. 退出"
        echo
        read -p "请选择操作 [0-5]: " choice
        case $choice in
            1) add_mapping_menu ;;
            2) delete_mapping_menu ;;
            3) showstatus; read -p "按Enter键继续..." ;;
            4) checkupdate; read -p "按Enter键继续..." ;; # checkupdate 函数未在此处提供
            5)
              printmsg $RED "警告: 此操作将完全卸载工具!"
              read -p "确定要继续吗? [y/N]: " confirm
              if [[ "$confirm" =~ ^[Yy]$ ]]; then
                uninstall
                exit 0
              fi
              ;;
            0) exit 0 ;;
            *) printmsg $RED "无效选择"; read -p "按Enter键继续..." ;;
        esac
    done
}
# 定义一个空的 checkupdate 以免报错
checkupdate() {
    printmsg $YELLOW "检查更新功能暂未实现。"
    log_action "Update check skipped (not implemented)."
}


# 执行主程序
main "$@"
