#!/bin/bash
# VPN端口映射工具 (支持 IPv4 & IPv6 + 多种防火墙)
# 作者: PanJX02 
# 版本: 2.1.0
# 日期: 2025-08-07

# --- 配置信息 ---
VERSION="2.1.0"
SCRIPTURL="https://raw.githubusercontent.com/PanJX02/PortMapping/refs/heads/main/vpn.sh"
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

# --- 全局变量 ---
FIREWALL_TYPE=""

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

# 检测防火墙类型
detect_firewall() {
    if command -v ufw &>/dev/null && [[ "$(ufw status)" != "Status: inactive" ]]; then
        FIREWALL_TYPE="ufw"
        printmsg $BLUE "检测到防火墙: UFW (Uncomplicated Firewall)"
    elif systemctl is-active --quiet firewalld; then
        FIREWALL_TYPE="firewalld"
        printmsg $BLUE "检测到防火墙: Firewalld"
    elif command -v iptables &>/dev/null; then
        FIREWALL_TYPE="iptables"
        printmsg $BLUE "使用防火墙: iptables (直接模式)"
    else
        printmsg $RED "错误: 未找到支持的防火墙工具"
        log_action "ERROR: No supported firewall found"
        exit 1
    fi
    log_action "Detected firewall: $FIREWALL_TYPE"
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

# UFW 添加端口映射规则 (优化版 - 直接使用iptables)
add_ufw_mapping() {
    local protocol=$1  # ipv4, ipv6, all
    local service_port=$2
    local start_port=$3
    local end_port=$4
    
    local added=0
    
    printmsg $YELLOW "UFW 不直接支持端口范围映射，使用底层 iptables 规则..."
    
    # 添加IPv4规则 - 直接使用iptables
    if [[ "$protocol" == "ipv4" ]] || [[ "$protocol" == "all" ]]; then
        local rule_id=$(generate_rule_id "ipv4" "$service_port" "$start_port" "$end_port")
        
        # 检查是否需要在UFW规则前插入
        local ufw_line=$(iptables -t nat -L PREROUTING --line-numbers | grep "ufw-before" | head -1 | awk '{print $1}')
        if [[ -n "$ufw_line" ]]; then
            iptables -t nat -I PREROUTING "$ufw_line" -p udp --dport "$start_port":"$end_port" -j DNAT --to-destination ":$service_port" -m comment --comment "$rule_id"
        else
            iptables -t nat -A PREROUTING -p udp --dport "$start_port":"$end_port" -j DNAT --to-destination ":$service_port" -m comment --comment "$rule_id"
        fi
        
        printmsg $GREEN "UFW+iptables IPv4 映射已添加: $start_port-$end_port -> $service_port"
        log_action "Added UFW+iptables IPv4 mapping: $start_port-$end_port -> $service_port"
        added=1
    fi
    
    # 添加IPv6规则 - 直接使用ip6tables
    if [[ "$protocol" == "ipv6" ]] || [[ "$protocol" == "all" ]]; then
        # 确保 IPv6 NAT 相关内核模块已加载
        modprobe ip6_tables 2>/dev/null
        modprobe ip6table_nat 2>/dev/null
        
        local rule_id=$(generate_rule_id "ipv6" "$service_port" "$start_port" "$end_port")
        
        # 检查是否需要在UFW规则前插入
        local ufw_line_v6=$(ip6tables -t nat -L PREROUTING --line-numbers 2>/dev/null | grep "ufw-before" | head -1 | awk '{print $1}')
        if [[ -n "$ufw_line_v6" ]]; then
            ip6tables -t nat -I PREROUTING "$ufw_line_v6" -p udp --dport "$start_port":"$end_port" -j DNAT --to-destination ":$service_port" -m comment --comment "$rule_id"
        else
            ip6tables -t nat -A PREROUTING -p udp --dport "$start_port":"$end_port" -j DNAT --to-destination ":$service_port" -m comment --comment "$rule_id"
        fi
        
        printmsg $GREEN "UFW+ip6tables IPv6 映射已添加: $start_port-$end_port -> $service_port"
        log_action "Added UFW+ip6tables IPv6 mapping: $start_port-$end_port -> $service_port"
        added=1
    fi
    
    # 创建 UFW 配置备份以便手动持久化
    if [[ "$added" -eq 1 ]]; then
        create_ufw_persistent_rules "$protocol" "$service_port" "$start_port" "$end_port" "add"
    fi
    
    return $((1-added))
}

# UFW 删除端口映射规则 (优化版)
delete_ufw_mapping() {
    local protocol=$1
    local service_port=$2
    local start_port=$3
    local end_port=$4
    
    # 删除IPv4规则
    if [[ "$protocol" == "ipv4" ]] || [[ "$protocol" == "all" ]]; then
        local rule_id_v4=$(generate_rule_id "ipv4" "$service_port" "$start_port" "$end_port")
        local rules_v4=$(iptables -t nat -L PREROUTING --line-numbers | grep "$rule_id_v4" | awk '{print $1}' | sort -rn)
        if [[ -n "$rules_v4" ]]; then
            while read -r rule; do 
                iptables -t nat -D PREROUTING "$rule"
            done <<< "$rules_v4"
            printmsg $GREEN "UFW+iptables IPv4 映射已删除: $start_port-$end_port -> $service_port"
            log_action "Deleted UFW+iptables IPv4 mapping: $start_port-$end_port -> $service_port"
        fi
    fi
    
    # 删除IPv6规则
    if [[ "$protocol" == "ipv6" ]] || [[ "$protocol" == "all" ]]; then
        local rule_id_v6=$(generate_rule_id "ipv6" "$service_port" "$start_port" "$end_port")
        local rules_v6=$(ip6tables -t nat -L PREROUTING --line-numbers 2>/dev/null | grep "$rule_id_v6" | awk '{print $1}' | sort -rn)
        if [[ -n "$rules_v6" ]]; then
            while read -r rule; do 
                ip6tables -t nat -D PREROUTING "$rule"
            done <<< "$rules_v6"
            printmsg $GREEN "UFW+ip6tables IPv6 映射已删除: $start_port-$end_port -> $service_port"
            log_action "Deleted UFW+ip6tables IPv6 mapping: $start_port-$end_port -> $service_port"
        fi
    fi
    
    # 清理持久化配置
    create_ufw_persistent_rules "$protocol" "$service_port" "$start_port" "$end_port" "delete"
}

# UFW 持久化规则管理
create_ufw_persistent_rules() {
    local protocol=$1
    local service_port=$2
    local start_port=$3
    local end_port=$4
    local action=$5  # add 或 delete
    
    local ufw_rules_file="$CONFIGDIR/ufw_custom_rules.sh"
    
    if [[ "$action" == "add" ]]; then
        mkdir -p "$CONFIGDIR"
        
        # 创建或更新自定义规则文件
        if [[ ! -f "$ufw_rules_file" ]]; then
            cat > "$ufw_rules_file" << 'EOF'
#!/bin/bash
# UFW 自定义端口映射规则
# 此文件由 VPN 端口映射工具自动生成和管理
# 建议将此脚本添加到系统启动脚本中以确保规则持久化

EOF
            chmod +x "$ufw_rules_file"
        fi
        
        # 添加规则到文件
        local rule_comment="# Mapping: $protocol $service_port $start_port $end_port"
        if ! grep -q "$rule_comment" "$ufw_rules_file"; then
            echo "" >> "$ufw_rules_file"
            echo "$rule_comment" >> "$ufw_rules_file"
            
            if [[ "$protocol" == "ipv4" ]] || [[ "$protocol" == "all" ]]; then
                local rule_id_v4=$(generate_rule_id "ipv4" "$service_port" "$start_port" "$end_port")
                echo "iptables -t nat -A PREROUTING -p udp --dport $start_port:$end_port -j DNAT --to-destination :$service_port -m comment --comment \"$rule_id_v4\"" >> "$ufw_rules_file"
            fi
            
            if [[ "$protocol" == "ipv6" ]] || [[ "$protocol" == "all" ]]; then
                local rule_id_v6=$(generate_rule_id "ipv6" "$service_port" "$start_port" "$end_port")
                echo "modprobe ip6_tables 2>/dev/null" >> "$ufw_rules_file"
                echo "modprobe ip6table_nat 2>/dev/null" >> "$ufw_rules_file"
                echo "ip6tables -t nat -A PREROUTING -p udp --dport $start_port:$end_port -j DNAT --to-destination :$service_port -m comment --comment \"$rule_id_v6\"" >> "$ufw_rules_file"
            fi
        fi
        
        printmsg $BLUE "提示: UFW 模式下的规则已保存到 $ufw_rules_file"
        printmsg $BLUE "建议将此脚本添加到 /etc/rc.local 或 crontab @reboot 以确保重启后生效"
        
    elif [[ "$action" == "delete" ]]; then
        if [[ -f "$ufw_rules_file" ]]; then
            # 从文件中删除对应规则
            local rule_comment="# Mapping: $protocol $service_port $start_port $end_port"
            local temp_file=$(mktemp)
            
            # 删除匹配的注释行和后续的iptables命令
            awk -v comment="$rule_comment" '
                $0 == comment {
                    skip = 1
                    next
                }
                skip && /^(iptables|ip6tables|modprobe)/ {
                    next
                }
                skip && /^$/ {
                    skip = 0
                    next
                }
                !skip {
                    print
                }
            ' "$ufw_rules_file" > "$temp_file"
            
            mv "$temp_file" "$ufw_rules_file"
        fi
    fi
}

# Firewalld 添加端口映射规则
add_firewalld_mapping() {
    local protocol=$1  # ipv4, ipv6, all
    local service_port=$2
    local start_port=$3
    local end_port=$4
    
    local added=0
    
    # 添加IPv4规则
    if [[ "$protocol" == "ipv4" ]] || [[ "$protocol" == "all" ]]; then
        if [[ "$start_port" == "$end_port" ]]; then
            firewall-cmd --permanent --add-rich-rule="rule family='ipv4' forward-port port='$start_port' protocol='udp' to-port='$service_port'"
        else
            firewall-cmd --permanent --add-rich-rule="rule family='ipv4' forward-port port='$start_port-$end_port' protocol='udp' to-port='$service_port'"
        fi
        printmsg $GREEN "Firewalld IPv4 映射已添加: $start_port-$end_port -> $service_port"
        log_action "Added Firewalld IPv4 mapping: $start_port-$end_port -> $service_port"
        added=1
    fi
    
    # 添加IPv6规则
    if [[ "$protocol" == "ipv6" ]] || [[ "$protocol" == "all" ]]; then
        if [[ "$start_port" == "$end_port" ]]; then
            firewall-cmd --permanent --add-rich-rule="rule family='ipv6' forward-port port='$start_port' protocol='udp' to-port='$service_port'"
        else
            firewall-cmd --permanent --add-rich-rule="rule family='ipv6' forward-port port='$start_port-$end_port' protocol='udp' to-port='$service_port'"
        fi
        printmsg $GREEN "Firewalld IPv6 映射已添加: $start_port-$end_port -> $service_port"
        log_action "Added Firewalld IPv6 mapping: $start_port-$end_port -> $service_port"
        added=1
    fi
    
    if [[ "$added" -eq 1 ]]; then
        firewall-cmd --reload
    fi
    
    return $((1-added))
}

# iptables 添加端口映射规则 (保留原有功能)
add_iptables_mapping() {
    local protocol=$1
    local service_port=$2
    local start_port=$3
    local end_port=$4

    local added=0
    # 添加IPv4规则
    if [[ "$protocol" == "ipv4" ]] || [[ "$protocol" == "all" ]]; then
        local rule_id=$(generate_rule_id "ipv4" "$service_port" "$start_port" "$end_port")
        iptables -t nat -A PREROUTING -p udp --dport "$start_port":"$end_port" -j DNAT --to-destination ":$service_port" -m comment --comment "$rule_id"
        printmsg $GREEN "iptables IPv4 映射已添加: $start_port-$end_port -> $service_port"
        log_action "Added iptables IPv4 mapping: $start_port-$end_port -> $service_port"
        added=1
    fi

    # 添加IPv6规则
    if [[ "$protocol" == "ipv6" ]] || [[ "$protocol" == "all" ]]; then
        # 确保 IPv6 NAT 相关内核模块已加载
        modprobe ip6_tables 2>/dev/null
        modprobe ip6table_nat 2>/dev/null
        
        local rule_id=$(generate_rule_id "ipv6" "$service_port" "$start_port" "$end_port")
        ip6tables -t nat -A PREROUTING -p udp --dport "$start_port":"$end_port" -j DNAT --to-destination ":$service_port" -m comment --comment "$rule_id"
        printmsg $GREEN "ip6tables IPv6 映射已添加: $start_port-$end_port -> $service_port"
        log_action "Added ip6tables IPv6 mapping: $start_port-$end_port -> $service_port"
        added=1
    fi

    return $((1-added))
}

# 统一添加端口映射接口
add_single_mapping() {
    local protocol=$1
    local service_port=$2
    local start_port=$3
    local end_port=$4

    if ! check_port_conflict "$protocol" "$service_port" "$start_port" "$end_port"; then
        return 1
    fi

    local success=0
    case "$FIREWALL_TYPE" in
        ufw)
            if add_ufw_mapping "$protocol" "$service_port" "$start_port" "$end_port"; then
                success=1
            fi
            ;;
        firewalld)
            if add_firewalld_mapping "$protocol" "$service_port" "$start_port" "$end_port"; then
                success=1
            fi
            ;;
        iptables)
            if add_iptables_mapping "$protocol" "$service_port" "$start_port" "$end_port"; then
                success=1
                save_netfilter_rules
            fi
            ;;
        *)
            printmsg $RED "错误: 不支持的防火墙类型 '$FIREWALL_TYPE'"
            log_action "ERROR: Unsupported firewall type '$FIREWALL_TYPE'"
            return 1
            ;;
    esac

    if [[ "$success" -eq 1 ]]; then
        mkdir -p "$CONFIGDIR"
        echo "$protocol $service_port $start_port $end_port" >> "$CONFIGFILE"
        return 0
    else
        return 1
    fi
}

# UFW 删除端口映射规则
delete_ufw_mapping() {
    local protocol=$1
    local service_port=$2
    local start_port=$3
    local end_port=$4
    
    # 删除IPv4和IPv6规则
    if [[ "$protocol" == "ipv4" ]] || [[ "$protocol" == "all" ]]; then
        for port in $(seq "$start_port" "$end_port"); do
            ufw --force delete route allow in on any out on any to any port "$service_port" from any port "$port" proto udp 2>/dev/null || true
        done
        printmsg $GREEN "UFW IPv4 映射已删除: $start_port-$end_port -> $service_port"
        log_action "Deleted UFW IPv4 mapping: $start_port-$end_port -> $service_port"
    fi
    
    if [[ "$protocol" == "ipv6" ]] || [[ "$protocol" == "all" ]]; then
        for port in $(seq "$start_port" "$end_port"); do
            ufw --force delete route allow in on any out on any to any port "$service_port" from any port "$port" proto udp 2>/dev/null || true
        done
        printmsg $GREEN "UFW IPv6 映射已删除: $start_port-$end_port -> $service_port"
        log_action "Deleted UFW IPv6 mapping: $start_port-$end_port -> $service_port"
    fi
}

# Firewalld 删除端口映射规则
delete_firewalld_mapping() {
    local protocol=$1
    local service_port=$2
    local start_port=$3
    local end_port=$4
    
    # 删除IPv4规则
    if [[ "$protocol" == "ipv4" ]] || [[ "$protocol" == "all" ]]; then
        if [[ "$start_port" == "$end_port" ]]; then
            firewall-cmd --permanent --remove-rich-rule="rule family='ipv4' forward-port port='$start_port' protocol='udp' to-port='$service_port'" 2>/dev/null || true
        else
            firewall-cmd --permanent --remove-rich-rule="rule family='ipv4' forward-port port='$start_port-$end_port' protocol='udp' to-port='$service_port'" 2>/dev/null || true
        fi
        printmsg $GREEN "Firewalld IPv4 映射已删除: $start_port-$end_port -> $service_port"
        log_action "Deleted Firewalld IPv4 mapping: $start_port-$end_port -> $service_port"
    fi
    
    # 删除IPv6规则
    if [[ "$protocol" == "ipv6" ]] || [[ "$protocol" == "all" ]]; then
        if [[ "$start_port" == "$end_port" ]]; then
            firewall-cmd --permanent --remove-rich-rule="rule family='ipv6' forward-port port='$start_port' protocol='udp' to-port='$service_port'" 2>/dev/null || true
        else
            firewall-cmd --permanent --remove-rich-rule="rule family='ipv6' forward-port port='$start_port-$end_port' protocol='udp' to-port='$service_port'" 2>/dev/null || true
        fi
        printmsg $GREEN "Firewalld IPv6 映射已删除: $start_port-$end_port -> $service_port"
        log_action "Deleted Firewalld IPv6 mapping: $start_port-$end_port -> $service_port"
    fi
    
    firewall-cmd --reload
}

# iptables 删除端口映射规则 (保留原有功能)
delete_iptables_mapping() {
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
            printmsg $GREEN "iptables IPv4 映射已删除: $start_port-$end_port -> $service_port"
            log_action "Deleted iptables IPv4 mapping: $start_port-$end_port -> $service_port"
        fi
    fi

    # 删除IPv6规则
    if [[ "$protocol" == "ipv6" ]] || [[ "$protocol" == "all" ]]; then
        local rule_id_v6=$(generate_rule_id "ipv6" "$service_port" "$start_port" "$end_port")
        local rules_v6=$(ip6tables -t nat -L PREROUTING --line-numbers 2>/dev/null | grep "$rule_id_v6" | awk '{print $1}' | sort -rn)
        if [[ -n "$rules_v6" ]]; then
            while read -r rule; do ip6tables -t nat -D PREROUTING "$rule"; done <<< "$rules_v6"
            printmsg $GREEN "ip6tables IPv6 映射已删除: $start_port-$end_port -> $service_port"
            log_action "Deleted ip6tables IPv6 mapping: $start_port-$end_port -> $service_port"
        fi
    fi
}

# 统一删除端口映射接口
delete_single_mapping() {
    local protocol=$1
    local service_port=$2
    local start_port=$3
    local end_port=$4

    case "$FIREWALL_TYPE" in
        ufw)
            delete_ufw_mapping "$protocol" "$service_port" "$start_port" "$end_port"
            ;;
        firewalld)
            delete_firewalld_mapping "$protocol" "$service_port" "$start_port" "$end_port"
            ;;
        iptables)
            delete_iptables_mapping "$protocol" "$service_port" "$start_port" "$end_port"
            save_netfilter_rules
            ;;
    esac

    # 从配置文件中删除
    if [[ -f "$CONFIGFILE" ]]; then
        local temp_file=$(mktemp)
        grep -v "^$protocol $service_port $start_port $end_port$" "$CONFIGFILE" > "$temp_file"
        mv "$temp_file" "$CONFIGFILE"
    fi
}

# 删除所有端口映射
delete_all_mappings() {
    local mappings
    readarray -t mappings <<< "$(read_all_mappings)"
    
    for mapping in "${mappings[@]}"; do
        if [[ -z "$mapping" ]]; then continue; fi
        local proto svc_port start_port end_port
        read proto svc_port start_port end_port <<< "$mapping"
        delete_single_mapping "$proto" "$svc_port" "$start_port" "$end_port"
    done
    
    # 清空配置文件
    if [[ -f "$CONFIGFILE" ]]; then > "$CONFIGFILE"; fi
    
    log_action "Deleted ALL port mappings (IPv4 & IPv6) and cleared configuration file"
}

# 保存iptables/ip6tables规则 (仅用于iptables模式)
save_netfilter_rules() {
    if [[ "$FIREWALL_TYPE" != "iptables" ]]; then
        return 0
    fi
    
    if command -v netfilter-persistent &> /dev/null; then
        netfilter-persistent save >/dev/null 2>&1
        log_action "Saved rules using netfilter-persistent"
    else
        if command -v iptables-save &> /dev/null; then
            mkdir -p "$(dirname "$IPTABLESRULES")"
            iptables-save > "$IPTABLESRULES"
            log_action "Saved IPv4 rules to $IPTABLESRULES"
        else
            log_action "WARNING: iptables-save command not found. IPv4 rules not saved."
        fi
        if command -v ip6tables-save &> /dev/null; then
            mkdir -p "$(dirname "$IP6TABLESRULES")"
            ip6tables-save > "$IP6TABLESRULES"
            log_action "Saved IPv6 rules to $IP6TABLESRULES"
        else
            log_action "WARNING: ip6tables-save command not found. IPv6 rules not saved."
        fi
    fi
}

# --- 菜单和用户交互 ---

# 添加端口映射菜单
add_mapping_menu() {
    clear
    printmsg $BLUE "===== 添加端口映射 ====="
    printmsg $CYAN "当前防火墙: $FIREWALL_TYPE"
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
        printmsg $CYAN "当前防火墙: $FIREWALL_TYPE"
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
    printmsg $CYAN "防火墙类型: $FIREWALL_TYPE"
    echo
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
    
    # 仅在iptables模式下显示规则统计
    if [[ "$FIREWALL_TYPE" == "iptables" ]]; then
        local rule_count_v4=$(iptables -t nat -L PREROUTING -n 2>/dev/null | grep -c "$RULECOMMENT_PREFIX" || echo 0)
        local rule_count_v6=$(ip6tables -t nat -L PREROUTING -n 2>/dev/null | grep -c "$RULECOMMENT_PREFIX" || echo 0)
        printmsg $BLUE "iptables 规则: $rule_count_v4 条IPv4规则, $rule_count_v6 条IPv6规则"
        
        local config_count_v4=$(grep -c -E '^(ipv4|all) ' "$CONFIGFILE" 2>/dev/null || echo 0)
        local config_count_v6=$(grep -c -E '^(ipv6|all) ' "$CONFIGFILE" 2>/dev/null || echo 0)
        
        if [[ "$rule_count_v4" -ne "$config_count_v4" ]] || [[ "$rule_count_v6" -ne "$config_count_v6" ]]; then
            printmsg $YELLOW "警告: 防火墙规则数量与配置不匹配，建议使用菜单重新应用规则。"
            log_action "WARNING: Rule/config mismatch. v4 ($rule_count_v4/$config_count_v4), v6 ($rule_count_v6/$config_count_v6)"
        fi
    else
        printmsg $BLUE "防火墙规则由 $FIREWALL_TYPE 管理"
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

    # 删除符号链接
    if [[ -L "/usr/local/bin/vpn" ]]; then
        rm -f "/usr/local/bin/vpn"
        printmsg $YELLOW "已删除 vpn 命令符号链接"
    fi

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

# 检查更新
checkupdate() {
    printmsg $YELLOW "正在检查更新..."
    log_action "Checking for updates..."
    
    local temp_script="/tmp/vpn_new_$.sh"
    if wget -q -O "$temp_script" "$SCRIPTURL" 2>/dev/null; then
        local current_version=$(grep '^VERSION=' "$0" | cut -d'"' -f2)
        local remote_version=$(grep '^VERSION=' "$temp_script" | cut -d'"' -f2)
        
        if [[ "$current_version" != "$remote_version" ]]; then
            printmsg $GREEN "发现新版本: $remote_version (当前版本: $current_version)"
            read -p "是否立即更新? [y/N]: " update_confirm
            if [[ "$update_confirm" =~ ^[Yy]$ ]]; then
                printmsg $BLUE "正在更新..."
                cp "$temp_script" "$INSTALLDIR/$SCRIPTNAME"
                chmod +x "$INSTALLDIR/$SCRIPTNAME"
                rm -f "$temp_script"
                printmsg $GREEN "更新完成！请重新运行 vpn 命令。"
                log_action "Updated to version $remote_version"
                exit 0
            fi
        else
            printmsg $GREEN "当前已是最新版本: $current_version"
        fi
        rm -f "$temp_script"
    else
        printmsg $RED "无法检查更新，请检查网络连接"
        log_action "Update check failed - network issue"
    fi
}

# 显示帮助
showhelp() {
    echo "VPN端口映射工具 v$VERSION (支持IPv4/IPv6 + 多种防火墙)"
    echo "支持的防火墙: UFW, Firewalld, iptables"
    echo
    echo "用法: $0 [无参数进入交互式菜单]"
    echo
    echo "功能说明:"
    echo "- 自动检测并适配当前系统的防火墙类型"
    echo "- 支持 IPv4, IPv6 或同时配置两种协议"
    echo "- 支持端口范围映射到单个服务端口"
    echo "- 配置持久化，重启后自动恢复"
    echo
    echo "示例场景:"
    echo "- 游戏服务器端口映射"
    echo "- VPN 流量转发"
    echo "- 负载均衡端口分发"
    echo
    echo "项目地址: https://github.com/PanJX02/PortMapping"
}

# 交互式主菜单
showmenu() {
    while true; do
        clear
        echo "VPN端口映射工具 v$VERSION (支持IPv4/IPv6 + 多种防火墙)"
        printmsg $BLUE "=========================================="
        printmsg $CYAN "当前防火墙: $FIREWALL_TYPE"
        printmsg $BLUE "=========================================="
        printmsg $GREEN "1. 添加端口映射"
        printmsg $YELLOW "2. 管理/删除端口映射"
        printmsg $CYAN "3. 查看当前映射状态"
        printmsg $PURPLE "4. 检查更新"
        printmsg $BLUE "5. 显示帮助"
        printmsg $RED "6. 卸载工具"
        printmsg $NC "0. 退出"
        echo
        read -p "请选择操作 [0-6]: " choice
        case $choice in
            1) add_mapping_menu ;;
            2) delete_mapping_menu ;;
            3) showstatus; read -p "按Enter键继续..." ;;
            4) checkupdate; read -p "按Enter键继续..." ;;
            5) showhelp; read -p "按Enter键继续..." ;;
            6)
                printmsg $RED "警告: 此操作将完全卸载工具!"
                read -p "确定要继续吗? [y/N]: " confirm
                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    uninstall
                    exit 0
                fi
                ;;
            0) 
                printmsg $BLUE "感谢使用！"
                exit 0 
                ;;
            *) 
                printmsg $RED "无效选择"
                read -p "按Enter键继续..." 
                ;;
        esac
    done
}

# 主程序
main() {
    log_action "Script started - VPN Port Mapping Tool v$VERSION"
    checkroot
    detect_firewall
    initconfig
    showmenu
}

# 执行主程序
main "$@"