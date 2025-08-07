#!/bin/bash
# VPN端口映射工具 (支持 IPv4 & IPv6, 适配 UFW/Firewalld/iptables)
# 作者: PanJX02 & AI Assistant
# 版本: 3.2.0 (已根据用户需求修订)
# 日期: 2024-05-22

# --- 配置信息 ---
VERSION="3.2.0"
INSTALLDIR="/usr/local/bin"
SCRIPTNAME="vpn-port-map" # 使用更符合Linux惯例的名称
CONFIGDIR="/etc/vpn-port-map"
CONFIGFILE="$CONFIGDIR/rules.conf"
LOGFILE="$CONFIGDIR/activity.log"
RULECOMMENT_PREFIX="VPNMAP" # 简短的注释前缀
FIREWALL_MANAGER="unknown" # 将被自动检测: ufw, firewalld, iptables

# --- UFW 特定配置 ---
UFW_BEFORE_RULES="/etc/ufw/before.rules"
UFW_NAT_TABLE_MARKER="*nat" # UFW NAT 表的起始标记

# --- 日志和颜色 ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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
        printmsg $RED "错误: 此脚本需要root权限运行。请尝试使用 'sudo $0'"
        log_action "ERROR: Root permission required"
        exit 1
    fi
}

# --- 防火墙管理核心 ---

# 检测活动的防火墙管理器
detect_firewall_manager() {
    if systemctl is-active --quiet firewalld; then
        FIREWALL_MANAGER="firewalld"
        log_action "Detected firewall manager: Firewalld"
    elif command -v ufw &>/dev/null && ufw status | grep -q "Status: active"; then
        FIREWALL_MANAGER="ufw"
        log_action "Detected firewall manager: UFW"
    elif command -v iptables &>/dev/null; then
        FIREWALL_MANAGER="iptables"
        log_action "Detected firewall manager: iptables (fallback)"
    else
        printmsg $RED "错误: 未找到任何支持的防火墙工具 (firewalld, ufw, iptables)!"
        log_action "FATAL: No supported firewall tool found."
        exit 1
    fi
}

# 封装的添加规则函数
fw_add_rule() {
    local protocol=$1 service_port=$2 start_port=$3 end_port=$4
    local rule_id
    
    case $FIREWALL_MANAGER in
        "firewalld")
            local success_v4=true success_v6=true
            if [[ "$protocol" == "ipv4" ]] || [[ "$protocol" == "all" ]]; then
                rule_id=$(generate_rule_id "ipv4" "$service_port" "$start_port" "$end_port")
                firewall-cmd --permanent --zone=public --add-forward-port=port=${start_port}-${end_port}:proto=udp:toport=${service_port} --set-family=ipv4 >/dev/null 2>&1
                if [[ $? -ne 0 ]]; then success_v4=false; fi
            fi
            if [[ "$protocol" == "ipv6" ]] || [[ "$protocol" == "all" ]]; then
                rule_id=$(generate_rule_id "ipv6" "$service_port" "$start_port" "$end_port")
                firewall-cmd --permanent --zone=public --add-forward-port=port=${start_port}-${end_port}:proto=udp:toport=${service_port} --set-family=ipv6 >/dev/null 2>&1
                if [[ $? -ne 0 ]]; then success_v6=false; fi
            fi
            [[ "$success_v4" == true && "$success_v6" == true ]] && return 0 || return 1
            ;;
        "ufw")
            # <!-- 修改 -->: UFW的NAT规则默认对v4和v6都生效，因此协议总是 'all'
            rule_id=$(generate_rule_id "all" "$service_port" "$start_port" "$end_port")
            local rule_string="-A PREROUTING -p udp --dport ${start_port}:${end_port} -j REDIRECT --to-port ${service_port} -m comment --comment \"${rule_id}\""
            add_ufw_nat_rule "$rule_string"
            ;;
        "iptables")
            local success_v4=true success_v6=true
            if [[ "$protocol" == "ipv4" ]] || [[ "$protocol" == "all" ]]; then
                rule_id=$(generate_rule_id "ipv4" "$service_port" "$start_port" "$end_port")
                iptables -t nat -A PREROUTING -p udp --dport "$start_port":"$end_port" -j REDIRECT --to-port "$service_port" -m comment --comment "$rule_id"
                if [[ $? -ne 0 ]]; then success_v4=false; fi
            fi
            if [[ "$protocol" == "ipv6" ]] || [[ "$protocol" == "all" ]]; then
                modprobe ip6_tables &>/dev/null && modprobe ip6table_nat &>/dev/null
                rule_id=$(generate_rule_id "ipv6" "$service_port" "$start_port" "$end_port")
                ip6tables -t nat -A PREROUTING -p udp --dport "$start_port":"$end_port" -j REDIRECT --to-port "$service_port" -m comment --comment "$rule_id"
                if [[ $? -ne 0 ]]; then success_v6=false; fi
            fi
            [[ "$success_v4" == true && "$success_v6" == true ]] && return 0 || return 1
            ;;
    esac
    return $?
}

# 封装的删除规则函数
fw_delete_rule() {
    local protocol=$1 service_port=$2 start_port=$3 end_port=$4
    local rule_id

    case $FIREWALL_MANAGER in
        "firewalld")
            local success_v4=true success_v6=true
            if [[ "$protocol" == "ipv4" ]] || [[ "$protocol" == "all" ]]; then
                rule_id=$(generate_rule_id "ipv4" "$service_port" "$start_port" "$end_port")
                firewall-cmd --permanent --zone=public --remove-forward-port=port=${start_port}-${end_port}:proto=udp:toport=${service_port} --set-family=ipv4 >/dev/null 2>&1
                # 忽略错误，因为可能规则不存在
            fi
            if [[ "$protocol" == "ipv6" ]] || [[ "$protocol" == "all" ]]; then
                rule_id=$(generate_rule_id "ipv6" "$service_port" "$start_port" "$end_port")
                firewall-cmd --permanent --zone=public --remove-forward-port=port=${start_port}-${end_port}:proto=udp:toport=${service_port} --set-family=ipv6 >/dev/null 2>&1
                # 忽略错误
            fi
            return 0 # 总是返回成功，因为目的是移除
            ;;
        "ufw")
            # <!-- 修改 -->: UFW的规则是v4/v6共用的, 总是按'all'删除
            rule_id=$(generate_rule_id "all" "$service_port" "$start_port" "$end_port")
            local rule_string="-A PREROUTING -p udp --dport ${start_port}:${end_port} -j REDIRECT --to-port ${service_port} -m comment --comment \"${rule_id}\""
            delete_ufw_nat_rule "$rule_string"
            ;;
        "iptables")
            if [[ "$protocol" == "ipv4" ]] || [[ "$protocol" == "all" ]]; then
                rule_id=$(generate_rule_id "ipv4" "$service_port" "$start_port" "$end_port")
                while iptables -t nat -C PREROUTING -p udp --dport "$start_port":"$end_port" -j REDIRECT --to-port "$service_port" -m comment --comment "$rule_id" &>/dev/null; do
                    iptables -t nat -D PREROUTING -p udp --dport "$start_port":"$end_port" -j REDIRECT --to-port "$service_port" -m comment --comment "$rule_id" &>/dev/null
                done
            fi
            if [[ "$protocol" == "ipv6" ]] || [[ "$protocol" == "all" ]]; then
                rule_id=$(generate_rule_id "ipv6" "$service_port" "$start_port" "$end_port")
                 while ip6tables -t nat -C PREROUTING -p udp --dport "$start_port":"$end_port" -j REDIRECT --to-port "$service_port" -m comment --comment "$rule_id" &>/dev/null; do
                    ip6tables -t nat -D PREROUTING -p udp --dport "$start_port":"$end_port" -j REDIRECT --to-port "$service_port" -m comment --comment "$rule_id" &>/dev/null
                done
            fi
            return 0
            ;;
    esac
    return $?
}

# 封装的应用更改函数
fw_apply_changes() {
    printmsg $YELLOW "正在应用防火墙规则..."
    case $FIREWALL_MANAGER in
        "firewalld")
            firewall-cmd --reload >/dev/null
            ;;
        "ufw")
            ufw reload >/dev/null
            ;;
        "iptables")
            if command -v netfilter-persistent &> /dev/null; then
                netfilter-persistent save >/dev/null
                log_action "Saved rules using netfilter-persistent"
            elif command -v iptables-save &> /dev/null; then
                mkdir -p /etc/iptables
                iptables-save > /etc/iptables/rules.v4
                ip6tables-save > /etc/iptables/rules.v6
                log_action "Saved rules using iptables-save"
            fi
            ;;
    esac
    printmsg $GREEN "防火墙规则已应用。"
    log_action "Firewall changes applied."
}

# === UFW 特定处理函数 ===
add_ufw_nat_rule() {
    local rule_string="$1"
    
    # 备份
    cp "$UFW_BEFORE_RULES" "${UFW_BEFORE_RULES}.bak.$(date +%F-%T)" &>/dev/null
    
    # 确保 *nat 表存在
    if ! grep -q "^\s*\*nat" "$UFW_BEFORE_RULES"; then
        sed -i '/^\s*\*filter/i \
*nat\n\
:PREROUTING ACCEPT [0:0]\n\
COMMIT\n' "$UFW_BEFORE_RULES"
        log_action "Added *nat table to UFW before.rules"
    fi

    # 检查规则是否已存在
    if grep -qF -- "$rule_string" "$UFW_BEFORE_RULES"; then
        log_action "UFW rule already exists: $rule_string"
        return 0 
    fi

    # 在 COMMIT 前插入规则
    sed -i "/^\s*\*nat/,/^\s*COMMIT/ s/^\s*COMMIT\s*$/${rule_string}\nCOMMIT/" "$UFW_BEFORE_RULES"
    log_action "Added UFW rule: $rule_string"
}

delete_ufw_nat_rule() {
    local rule_string="$1"
    if grep -qF -- "$rule_string" "$UFW_BEFORE_RULES"; then
        cp "$UFW_BEFORE_RULES" "${UFW_BEFORE_RULES}.bak.$(date +%F-%T)" &>/dev/null
        sed -i "\#${rule_string}#d" "$UFW_BEFORE_RULES"
        log_action "Deleted UFW rule: $rule_string"
    fi
}

# --- 其他核心功能 ---

generate_rule_id() {
    local protocol=$1 service_port=$2 start_port=$3 end_port=$4
    echo "${RULECOMMENT_PREFIX}_${protocol}_${service_port}_${start_port}_${end_port}"
}

read_all_mappings() {
    [[ ! -f "$CONFIGFILE" ]] || grep -Ev '^[[:space:]]*#|^[[:space:]]*$' "$CONFIGFILE"
}

check_port_conflict() {
    local new_protocol=$1 new_service=$2 new_start=$3 new_end=$4
    
    readarray -t mappings <<< "$(read_all_mappings)"
    
    for mapping in "${mappings[@]}"; do
        [[ -z "$mapping" ]] && continue
        local proto svc_port start_port end_port
        read proto svc_port start_port end_port <<< "$mapping"

        if [[ "$new_start" -le "$end_port" ]] && [[ "$new_end" -ge "$start_port" ]]; then
            if ! ( [[ "$new_protocol" != "$proto" ]] && [[ "$new_protocol" != "all" ]] && [[ "$proto" != "all" ]] ); then
                printmsg $RED "错误: 范围 $new_start-$new_end 与现有映射 ($proto) $start_port-$end_port 冲突。"
                return 1
            fi
        fi
        if [[ "$new_service" -eq "$svc_port" ]]; then
            printmsg $RED "错误: 服务端口 $new_service 已被用于另一条映射。"
            return 1
        fi
    done
    return 0
}

add_single_mapping() {
    local protocol=$1 service_port=$2 start_port=$3 end_port=$4
    
    # <!-- 修改 -->: 区分用户选择的协议和实际执行的协议
    local config_protocol=$protocol # 用于写入配置文件的协议 (用户意图)
    local exec_protocol=$protocol   # 用于执行防火墙命令的协议
    
    if [[ "$FIREWALL_MANAGER" == "ufw" ]]; {
        # 对于UFW，实际执行的规则总是 'all'
        exec_protocol="all"
    }

    if ! check_port_conflict "$config_protocol" "$service_port" "$start_port" "$end_port"; then
        return 1
    fi
    
    if fw_add_rule "$exec_protocol" "$service_port" "$start_port" "$end_port"; then
        mkdir -p "$CONFIGDIR"
        # <!-- 修改 -->: 写入配置文件时，如果用户选'all'且非UFW，则分两行写
        if [[ "$config_protocol" == "all" ]] && [[ "$FIREWALL_MANAGER" != "ufw" ]]; then
            echo "ipv4 $service_port $start_port $end_port" >> "$CONFIGFILE"
            echo "ipv6 $service_port $start_port $end_port" >> "$CONFIGFILE"
            log_action "Added mapping to config: ipv4/ipv6 $service_port $start_port-$end_port"
        else
            echo "$config_protocol $service_port $start_port $end_port" >> "$CONFIGFILE"
            log_action "Added mapping to config: $config_protocol $service_port $start_port-$end_port"
        fi
        return 0
    else
        printmsg $RED "错误: 添加防火墙规则失败。"
        log_action "ERROR: fw_add_rule failed for $exec_protocol $service_port $start_port-$end_port"
        return 1
    fi
}

delete_single_mapping() {
    local protocol=$1 service_port=$2 start_port=$3 end_port=$4
    
    # <!-- 修改 -->: 适配UFW的删除逻辑
    local delete_protocol=$protocol
    if [[ "$FIREWALL_MANAGER" == "ufw" ]]; then
        # 无论配置文件里是ipv4/ipv6/all，UFW实际只有一条all规则
        delete_protocol="all"
    fi

    if fw_delete_rule "$delete_protocol" "$service_port" "$start_port" "$end_port"; then
        if [[ -f "$CONFIGFILE" ]]; then
            local temp_file
            temp_file=$(mktemp)
            # <!-- 修改 -->: 更精确地删除配置行
            # 如果删除 'all'，则同时移除对应的 'ipv4' 和 'ipv6' 行
            if [[ "$protocol" == "all" ]]; then
                 grep -v "^\(ipv4\|ipv6\|all\) ${service_port} ${start_port} ${end_port}$" "$CONFIGFILE" > "$temp_file"
            else
                 grep -v "^${protocol} ${service_port} ${start_port} ${end_port}$" "$CONFIGFILE" > "$temp_file"
            fi
            mv "$temp_file" "$CONFIGFILE"
            log_action "Deleted mapping from config: $protocol $service_port $start_port-$end_port"
        fi
        return 0
    else
        printmsg $RED "错误: 删除防火墙规则失败。"
        log_action "ERROR: fw_delete_rule failed for $delete_protocol $service_port $start_port-$end_port"
        return 1
    fi
}

delete_all_mappings() {
    local mappings
    readarray -t mappings <<< "$(read_all_mappings)"
    
    if [[ ${#mappings[@]} -eq 0 ]] || [[ -z "${mappings[0]}" ]]; then
        printmsg $YELLOW "没有配置需要删除。"
        return
    fi
    
    printmsg $YELLOW "正在删除所有已配置的端口映射..."
    local deleted_keys=()
    for mapping in "${mappings[@]}"; do
        local proto svc_port start_port end_port
        read proto svc_port start_port end_port <<< "$mapping"
        
        # 使用端口和服务作为键，防止重复删除
        local key="${svc_port} ${start_port} ${end_port}"
        if [[ " ${deleted_keys[*]} " =~ " ${key} " ]]; then
            continue
        fi
        
        # 无论单条是ipv4还是ipv6，我们都按"all"来删除，确保彻底清理
        delete_single_mapping "all" "$svc_port" "$start_port" "$end_port"
        deleted_keys+=("$key")
    done
    
    # 清空配置文件以防万一
    > "$CONFIGFILE"
    
    fw_apply_changes
    log_action "Deleted ALL port mappings and cleared configuration file."
}

# --- 菜单和用户交互 ---

add_mapping_menu() {
    clear
    printmsg $BLUE "===== 添加端口映射 (当前防火墙: $FIREWALL_MANAGER) ====="
    
    read -p "服务端口 (目标端口): " service_port
    read -p "起始端口: " start_port
    read -p "结束端口: " end_port
    
    for port in $service_port $start_port $end_port; do
        if ! [[ "$port" =~ ^[0-9]+$ ]] || [[ "$port" -lt 1 ]] || [[ "$port" -gt 65535 ]]; then
            printmsg $RED "错误: 端口 '$port' 无效，必须是 1-65535 之间的数字"; read -p "按回车继续..."; return
        fi
    done
    if [[ "$start_port" -gt "$end_port" ]]; then
        printmsg $RED "错误: 起始端口不能大于结束端口"; read -p "按回车继续..."; return
    fi
     if [ "$service_port" -ge "$start_port" ] && [ "$service_port" -le "$end_port" ]; then
         printmsg $RED "错误：服务端口不能在连接端口范围内！"; read -p "按回车继续..."; return
    fi

    printmsg $YELLOW "请选择协议类型:"
    echo "  1. 仅 IPv4"
    echo "  2. 仅 IPv6"
    echo "  3. IPv4 和 IPv6 (全部)"
    read -p "请选择 [1-3, 默认 3]: " proto_choice
    
    local protocol
    case $proto_choice in
        1) protocol="ipv4" ;;
        2) protocol="ipv6" ;;
        *) protocol="all" ;;
    esac

    # <!-- 新增: 对UFW的特别提示 -->
    if [[ "$FIREWALL_MANAGER" == "ufw" ]] && [[ "$protocol" != "all" ]]; then
        printmsg $YELLOW "\n注意: UFW的NAT规则默认同时对IPv4和IPv6生效。\n您的选择 '$protocol' 会被记录在配置文件中，但实际防火墙规则将应用于两个协议。"
        read -p "按Enter键确认并继续..."
    fi

    if add_single_mapping "$protocol" "$service_port" "$start_port" "$end_port"; then
        printmsg $GREEN "映射已添加至配置，正在应用更改..."
        fw_apply_changes
    else
        printmsg $RED "映射添加失败，请检查冲突或日志。"
    fi
    read -p "按Enter键继续..."
}

delete_mapping_menu() {
    while true; do
        clear
        printmsg $BLUE "===== 管理端口映射 (防火墙: $FIREWALL_MANAGER) ====="
        local mappings
        readarray -t mappings <<< "$(read_all_mappings)"
        if [[ ${#mappings[@]} -eq 0 ]] || [[ -z "${mappings[0]}" ]]; then
            printmsg $YELLOW "当前没有活动的端口映射"; read -p "按Enter键返回..."; return
        fi
        
        printmsg $YELLOW "当前的端口映射:"
        local i=1
        for mapping in "${mappings[@]}"; do
            read proto svc_port start_port end_port <<< "$mapping"
            printf "  %-3s %-7s %-20s -> %-5s (UDP)\n" "$i." "[$proto]" "$start_port-$end_port" "$svc_port"
            ((i++))
        done
        echo
        printmsg $YELLOW "选择操作: 1-$((${#mappings[@]}))删除指定映射, 'a'删除所有, '0'返回"
        read -p "请选择: " choice

        case $choice in
            0) return ;;
            a|A)
                read -p "$(printmsg $RED '警告: 确定要删除所有映射吗? [y/N]: ')" confirm
                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    delete_all_mappings
                    printmsg $GREEN "所有端口映射已删除"
                fi
                read -p "按Enter键继续..."
                ;;
            *)
                if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le "${#mappings[@]}" ]]; then
                    local selected_mapping="${mappings[$((choice-1))]}"
                    read proto svc_port start_port end_port <<< "$selected_mapping"
                    read -p "$(printmsg $YELLOW "确认删除映射: [$proto] $start_port-$end_port -> $svc_port? [y/N]: ")" confirm
                    if [[ "$confirm" =~ ^[Yy]$ ]]; then
                        if delete_single_mapping "$proto" "$svc_port" "$start_port" "$end_port"; then
                           fw_apply_changes
                        else
                           printmsg $RED "规则删除失败！"
                        fi
                    fi
                    read -p "按Enter键继续..."
                else
                    printmsg $RED "无效选择"; read -p "按Enter键继续..."
                fi
                ;;
        esac
    done
}

showstatus() {
    printmsg $BLUE "===== 当前端口映射状态 ====="
    printmsg $GREEN "检测到的防火墙管理器: $FIREWALL_MANAGER"
    echo
    local mappings
    readarray -t mappings <<< "$(read_all_mappings)"
    
    if [[ ${#mappings[@]} -eq 0 ]] || [[ -z "${mappings[0]}" ]]; then
        printmsg $YELLOW "✗ 当前没有配置的端口映射"
        log_action "Status checked: No active mappings"
        return
    fi

    printmsg $GREEN "✓ 已配置的映射 (共 ${#mappings[@]} 条):"
    local i=1
    for mapping in "${mappings[@]}"; do
        read proto svc_port start_port end_port <<< "$mapping"
        printf "  %-3s 协议: %-7s 端口范围: %-20s -> 服务端口: %-5s\n" "$i." "$proto" "$start_port-$end_port" "$svc_port"
        ((i++))
    done
    echo
    printmsg $YELLOW "注意: 以上是配置文件中的记录。请使用防火墙原生命令确认实时规则:\n- UFW: 'sudo ufw status verbose' 和 'cat /etc/ufw/before.rules'\n- Firewalld: 'sudo firewall-cmd --list-all'\n- iptables: 'sudo iptables -t nat -L' 和 'sudo ip6tables -t nat -L'"
}

uninstall() {
    printmsg $RED "警告: 此操作将删除所有映射规则并移除脚本自身！"
    read -p "确定要继续吗? [y/N]: " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        printmsg $YELLOW "卸载已取消。"
        return
    fi
    
    printmsg $YELLOW "正在卸载..."
    log_action "Starting uninstallation process..."

    delete_all_mappings

    printmsg $YELLOW "正在删除配置文件和日志目录..."
    rm -rf "$CONFIGDIR"
    log_action "Removed config directory: $CONFIGDIR"

    printmsg $YELLOW "正在删除脚本: $INSTALLDIR/$SCRIPTNAME"
    rm -f "$INSTALLDIR/$SCRIPTNAME"
    
    printmsg $GREEN "卸载完成。"
    log_action "Uninstallation complete."
    exit 0
}

install_or_init() {
    checkroot
    mkdir -p "$CONFIGDIR"
    if [[ ! -f "$CONFIGFILE" ]]; then touch "$CONFIGFILE"; fi

    if [[ "$(realpath "$0")" != "$INSTALLDIR/$SCRIPTNAME" ]]; then
        if cp "$0" "$INSTALLDIR/$SCRIPTNAME"; then
            chmod +x "$INSTALLDIR/$SCRIPTNAME"
            printmsg $GREEN "脚本已安装到 $INSTALLDIR/$SCRIPTNAME"
            printmsg $YELLOW "现在，请使用 '$SCRIPTNAME' 命令运行。"
            exit 0
        else
            printmsg $RED "错误: 脚本安装失败。请检查 $INSTALLDIR 目录权限。"
            exit 1
        fi
    fi
    
    detect_firewall_manager
}


main() {
    install_or_init
    
    while true; do
        clear
        echo "VPN端口映射工具 v$VERSION"
        printmsg $BLUE "=============================================="
        printmsg $YELLOW "防火墙管理器: $FIREWALL_MANAGER"
        printmsg $GREEN "  1. 添加端口映射"
        printmsg $YELLOW "  2. 管理/删除端口映射"
        printmsg $CYAN "  3. 查看当前映射状态"
        printmsg $RED "  4. 卸载工具"
        printmsg $NC "  0. 退出"
        echo
        read -p "请选择操作 [0-4]: " choice
        case $choice in
            1) add_mapping_menu ;;
            2) delete_mapping_menu ;;
            3) showstatus; read -p "按Enter键继续..." ;;
            4) uninstall ;;
            0) exit 0 ;;
            *) printmsg $RED "无效选择"; read -p "按Enter键继续..." ;;
        esac
    done
}

main "$@"
