#!/bin/bash
# VPN 端口映射工具 - 安全安装程序 V1.1
# 安装后的命令为 'portmap'

# --- 配置 ---
INSTALL_PATH="/usr/local/bin/portmap"
CONFIG_DIR="/etc/portmap"

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

# 3. 创建主脚本文件
create_main_script() {
    printmsg "正在创建主程序: $INSTALL_PATH" "$YELLOW"
    
    # 使用 Heredoc 将主程序代码写入文件
    # 注意: <<'EOF' 中的单引号至关重要，它能防止此处的变量被立即展开
cat > "$INSTALL_PATH" <<'EOF'
#!/bin/bash
# 端口映射工具 (支持 IPv4 & IPv6, 适配 UFW/Firewalld/iptables)
# 作者: PanJX02 & AI Assistant
# 版本: 3.1.0 (由安装程序生成)

# --- 配置信息 ---
VERSION="3.1.0"
CONFIGDIR="/etc/portmap"
CONFIGFILE="$CONFIGDIR/rules.conf"
LOGFILE="$CONFIGDIR/activity.log"
RULECOMMENT_PREFIX="PORTMAP"
FIREWALL_MANAGER="unknown"

# --- UFW 特定配置 ---
UFW_BEFORE_RULES="/etc/ufw/before.rules"

# --- 日志和颜色 ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# --- 辅助函数 ---
printmsg() { local c=$1; local m=$2; echo -e "${c}${m}${NC}"; }
log_action() { mkdir -p "$(dirname "$LOGFILE")" 2>/dev/null; echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOGFILE"; }
checkroot() { if [[ $EUID -ne 0 ]]; then printmsg $RED "错误: 此脚本需要root权限运行。"; exit 1; fi; }

# --- 防火墙管理核心 ---
detect_firewall_manager() {
    if systemctl is-active --quiet firewalld; then FIREWALL_MANAGER="firewalld";
    elif command -v ufw &>/dev/null && ufw status | grep -q "Status: active"; then FIREWALL_MANAGER="ufw";
    elif command -v iptables &>/dev/null; then FIREWALL_MANAGER="iptables";
    else printmsg $RED "错误: 未找到任何支持的防火墙工具!"; exit 1; fi
}

fw_add_rule() {
    local protocol=$1 service_port=$2 start_port=$3 end_port=$4
    local rule_id=$(generate_rule_id "$protocol" "$service_port" "$start_port" "$end_port")
    case $FIREWALL_MANAGER in
        "firewalld") firewall-cmd --permanent --add-forward-port=port=${start_port}-${end_port}:proto=udp:toport=${service_port} >/dev/null ;;
        "ufw") add_ufw_nat_rule "-A PREROUTING -p udp --dport ${start_port}:${end_port} -j REDIRECT --to-port ${service_port} -m comment --comment \"${rule_id}\"" ;;
        "iptables")
            if [[ "$protocol" == "ipv4" ]] || [[ "$protocol" == "all" ]]; then iptables -t nat -A PREROUTING -p udp --dport "$start_port":"$end_port" -j REDIRECT --to-port "$service_port" -m comment --comment "$rule_id"; fi
            if [[ "$protocol" == "ipv6" ]] || [[ "$protocol" == "all" ]]; then modprobe ip6table_nat &>/dev/null; ip6tables -t nat -A PREROUTING -p udp --dport "$start_port":"$end_port" -j REDIRECT --to-port "$service_port" -m comment --comment "$rule_id"; fi
            ;;
    esac
    return $?
}

fw_delete_rule() {
    local protocol=$1 service_port=$2 start_port=$3 end_port=$4
    local rule_id=$(generate_rule_id "$protocol" "$service_port" "$start_port" "$end_port")
    case $FIREWALL_MANAGER in
        "firewalld") firewall-cmd --permanent --remove-forward-port=port=${start_port}-${end_port}:proto=udp:toport=${service_port} >/dev/null ;;
        "ufw") delete_ufw_nat_rule "-A PREROUTING -p udp --dport ${start_port}:${end_port} -j REDIRECT --to-port ${service_port} -m comment --comment \"${rule_id}\"" ;;
        "iptables")
            local rule_to_delete
            if [[ "$protocol" == "ipv4" ]] || [[ "$protocol" == "all" ]]; then rule_to_delete=$(iptables -t nat -S PREROUTING | grep -- "$rule_id"); [[ -n "$rule_to_delete" ]] && iptables -t nat -D PREROUTING ${rule_to_delete//-A PREROUTING /}; fi
            if [[ "$protocol" == "ipv6" ]] || [[ "$protocol" == "all" ]]; then rule_to_delete=$(ip6tables -t nat -S PREROUTING 2>/dev/null | grep -- "$rule_id"); [[ -n "$rule_to_delete" ]] && ip6tables -t nat -D PREROUTING ${rule_to_delete//-A PREROUTING /}; fi
            ;;
    esac
    return $?
}

fw_apply_changes() {
    printmsg $YELLOW "正在应用防火墙规则..."
    case $FIREWALL_MANAGER in
        "firewalld") firewall-cmd --reload >/dev/null ;;
        "ufw") ufw reload >/dev/null ;;
        "iptables")
             if command -v netfilter-persistent &> /dev/null; then netfilter-persistent save >/dev/null;
             elif command -v service &>/dev/null && service iptables save &>/dev/null; then :
             else 
                iptables-save > /etc/iptables/rules.v4 2>/dev/null
                ip6tables-save > /etc/iptables/rules.v6 2>/dev/null
             fi
             ;;
    esac
    printmsg $GREEN "防火墙规则已应用。"
}

# === UFW 特定处理函数 ===
add_ufw_nat_rule() {
    local rule_string="$1"
    if ! grep -q "^\s*\*nat" "$UFW_BEFORE_RULES"; then
        cp "$UFW_BEFORE_RULES" "${UFW_BEFORE_RULES}.bak.$(date +%F-%T)"
        sed -i '/^\s*\*filter/i *nat\n:PREROUTING ACCEPT [0:0]\nCOMMIT\n' "$UFW_BEFORE_RULES"
    fi
    if ! grep -qF -- "$rule_string" "$UFW_BEFORE_RULES"; then
        cp "$UFW_BEFORE_RULES" "${UFW_BEFORE_RULES}.bak.$(date +%F-%T)"
        sed -i "/^\s*\*nat/,/^\s*COMMIT/ s/^\s*COMMIT\s*$/${rule_string}\nCOMMIT/" "$UFW_BEFORE_RULES"
    fi
}
delete_ufw_nat_rule() {
    local rule_string="$1"
    if grep -qF -- "$rule_string" "$UFW_BEFORE_RULES"; then
        cp "$UFW_BEFORE_RULES" "${UFW_BEFORE_RULES}.bak.$(date +%F-%T)"
        sed -i "\#${rule_string}#d" "$UFW_BEFORE_RULES"
    fi
}

# --- 其他核心功能 ---
generate_rule_id() { local p=$1 s=$2 b=$3 e=$4; [[ "$FIREWALL_MANAGER" != "iptables" ]] && p="udp"; echo "${RULECOMMENT_PREFIX}_${p}_${s}_${b}_${e}"; }
read_all_mappings() { [[ ! -f "$CONFIGFILE" ]] || grep -Ev '^[[:space:]]*#|^[[:space:]]*$' "$CONFIGFILE"; }
check_port_conflict() {
    local new_protocol=$1 new_service=$2 new_start=$3 new_end=$4
    local mappings; readarray -t mappings <<< "$(read_all_mappings)"
    for mapping in "${mappings[@]}"; do
        [[ -z "$mapping" ]] && continue; local proto svc_port start_port end_port
        read proto svc_port start_port end_port <<< "$mapping"
        if [[ "$new_start" -le "$end_port" ]] && [[ "$new_end" -ge "$start_port" ]]; then printmsg $RED "错误: 范围 $new_start-$new_end 与现有映射 $start_port-$end_port 冲突。"; return 1; fi
        if [[ "$new_service" -eq "$svc_port" ]]; then printmsg $RED "错误: 服务端口 $new_service 已被使用。"; return 1; fi
    done
    return 0
}
add_single_mapping() {
    local protocol=$1 service_port=$2 start_port=$3 end_port=$4
    [[ "$FIREWALL_MANAGER" != "iptables" ]] && protocol="udp"
    if ! check_port_conflict "$protocol" "$service_port" "$start_port" "$end_port"; then return 1; fi
    if fw_add_rule "$protocol" "$service_port" "$start_port" "$end_port"; then
        mkdir -p "$CONFIGDIR"; echo "$protocol $service_port $start_port $end_port" >> "$CONFIGFILE"
        return 0
    else printmsg $RED "错误: 添加防火墙规则失败。"; return 1; fi
}
delete_single_mapping() {
    local protocol=$1 service_port=$2 start_port=$3 end_port=$4
    [[ "$FIREWALL_MANAGER" != "iptables" ]] && protocol="udp"
    if fw_delete_rule "$protocol" "$service_port" "$start_port" "$end_port"; then
        if [[ -f "$CONFIGFILE" ]]; then
            local temp_file; temp_file=$(mktemp)
            grep -v "^$protocol $service_port $start_port $end_port$" "$CONFIGFILE" > "$temp_file" && mv "$temp_file" "$CONFIGFILE"
        fi
        return 0
    else printmsg $RED "错误: 删除防火墙规则失败。"; return 1; fi
}
delete_all_mappings() {
    local mappings; readarray -t mappings <<< "$(read_all_mappings)"
    [[ ${#mappings[@]} -eq 0 || -z "${mappings[0]}" ]] && { printmsg $YELLOW "没有配置需要删除。"; return; }
    printmsg $YELLOW "正在删除所有已配置的端口映射..."; log_action "Deleting all mappings"
    for mapping in "${mappings[@]}"; do delete_single_mapping $mapping; done
    > "$CONFIGFILE"; fw_apply_changes
}

# --- 菜单和用户交互 ---
add_mapping_menu() {
    clear; printmsg $BLUE "===== 添加端口映射 (防火墙: $FIREWALL_MANAGER) ====="
    read -p "服务端口 (目标端口): " service_port
    read -p "起始端口: " start_port
    read -p "结束端口: " end_port
    for port in $service_port $start_port $end_port; do
        if ! [[ "$port" =~ ^[0-9]+$ ]] || [[ "$port" -lt 1 ]] || [[ "$port" -gt 65535 ]]; then
            printmsg $RED "错误: 端口 '$port' 无效。"; read -p "按回车继续..."; return
        fi
    done
    if [[ "$start_port" -gt "$end_port" ]]; then
        printmsg $RED "错误: 起始端口不能大于结束端口"; read -p "按回车继续..."; return
    fi
     if [ "$service_port" -ge "$start_port" ] && [ "$service_port" -le "$end_port" ]; then
         printmsg $RED "错误：服务端口不能在连接端口范围内！"; read -p "按回车继续..."; return
    fi
    local protocol="udp"
    if [[ "$FIREWALL_MANAGER" == "iptables" ]]; then
        read -p "选择协议: 1.IPv4 2.IPv6 3.两者(all) [默认 3]: " choice
        case $choice in 1) protocol="ipv4";; 2) protocol="ipv6";; *) protocol="all";; esac
    fi
    if add_single_mapping "$protocol" "$service_port" "$start_port" "$end_port"; then
        log_action "Added mapping: $protocol $service_port $start_port-$end_port"
        printmsg $GREEN "映射已配置，正在应用更改..."; fw_apply_changes
    else printmsg $RED "映射添加失败。"; fi
    read -p "按Enter键继续..."
}
delete_mapping_menu() {
    while true; do
        clear; printmsg $BLUE "===== 管理端口映射 (防火墙: $FIREWALL_MANAGER) ====="
        local mappings; readarray -t mappings <<< "$(read_all_mappings)"
        if [[ ${#mappings[@]} -eq 0 || -z "${mappings[0]}" ]]; then printmsg $YELLOW "当前没有活动的端口映射"; read -p "按Enter键返回..."; return; fi
        printmsg $YELLOW "当前的端口映射:"; local i=1
        for mapping in "${mappings[@]}"; do
            read proto svc_port start_port end_port <<< "$mapping"
            printf "  %-3s %-7s %-20s -> %-5s (UDP)\n" "$i." "[$proto]" "$start_port-$end_port" "$svc_port"; ((i++))
        done
        echo; printmsg $YELLOW "选择: 1-$((${#mappings[@]}))删除指定, 'a'删除所有, '0'返回"; read -p "请选择: " choice
        case $choice in
            0) return ;;
            a|A) read -p "$(printmsg $RED '警告: 确定要删除所有映射吗? [y/N]: ')" confirm
                 if [[ "$confirm" =~ ^[Yy]$ ]]; then delete_all_mappings; printmsg $GREEN "所有端口映射已删除"; fi
                 read -p "按Enter键继续..." ;;
            *)
                if [[ "$choice" =~ ^[0-9]+$ && "$choice" -ge 1 && "$choice" -le "${#mappings[@]}" ]]; then
                    local sel_map="${mappings[$((choice-1))]}"; read proto svc_port start_port end_port <<< "$sel_map"
                    read -p "$(printmsg $YELLOW "确认删除: [$proto] $start_port-$end_port -> $svc_port? [y/N]: ")" confirm
                    if [[ "$confirm" =~ ^[Yy]$ ]]; then
                        log_action "Deleting mapping: $proto $svc_port $start_port-$end_port"
                        delete_single_mapping "$proto" "$svc_port" "$start_port" "$end_port" && fw_apply_changes
                    fi
                else printmsg $RED "无效选择"; fi; read -p "按Enter键继续..." ;;
        esac
    done
}
showstatus() {
    printmsg $BLUE "===== 当前端口映射状态 ====="; printmsg $GREEN "检测到防火墙管理器: $FIREWALL_MANAGER"; echo
    local mappings; readarray -t mappings <<< "$(read_all_mappings)"
    if [[ ${#mappings[@]} -eq 0 || -z "${mappings[0]}" ]]; then printmsg $YELLOW "✗ 当前没有配置的端口映射"; return; fi
    printmsg $GREEN "✓ 已配置的映射 (共 ${#mappings[@]} 条):"; local i=1
    for mapping in "${mappings[@]}"; do
        read proto svc_port start_port end_port <<< "$mapping"
        printf "  %-3s 协议: %-7s 端口范围: %-20s -> 服务端口: %-5s\n" "$i." "$proto" "$start_port-$end_port" "$svc_port"; ((i++))
    done; echo
    printmsg $YELLOW "注意: 这是配置文件的记录, 请使用防火墙原生命令确认实时规则。"
}
uninstall() {
    read -p "$(printmsg $RED '警告: 此操作将删除所有映射规则并移除脚本! 确定吗? [y/N]: ')" confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then printmsg $YELLOW "卸载已取消。"; return; fi
    printmsg $YELLOW "正在卸载..."; log_action "Uninstalling..."
    delete_all_mappings
    printmsg $YELLOW "正在删除配置文件和日志目录..."; rm -rf "$CONFIGDIR"
    printmsg $YELLOW "正在删除脚本: $(command -v "$0")"; rm -f "$(command -v "$0")"
    printmsg $GREEN "卸载完成。"
}
showmenu() {
    while true; do
        clear; echo "端口映射工具 v$VERSION"; printmsg $BLUE "=============================================="
        printmsg $YELLOW "防火墙管理器: $FIREWALL_MANAGER"
        printmsg $GREEN "  1. 添加端口映射"; printmsg $YELLOW "  2. 管理/删除端口映射"
        printmsg $CYAN "  3. 查看当前映射状态"; printmsg $RED "  4. 卸载工具"; printmsg $NC "  0. 退出"
        echo; read -p "请选择操作 [0-4]: " choice
        case $choice in
            1) add_mapping_menu ;; 2) delete_mapping_menu ;; 3) showstatus; read -p "按Enter键继续..." ;;
            4) uninstall; exit 0 ;; 0) exit 0 ;; *) printmsg $RED "无效选择"; read -p "按Enter键继续..." ;;
        esac
    done
}

# --- 程序入口 ---
main() {
    checkroot
    mkdir -p "$CONFIGDIR"
    detect_firewall_manager
    log_action "Script started, detected firewall: $FIREWALL_MANAGER"
    showmenu
    log_action "Script exited."
}

main "$@"
EOF
    # EOF 之前不能有任何空格

    # 赋予执行权限
    chmod +x "$INSTALL_PATH"
}

# --- 主安装流程 ---
main() {
    check_root
    
    if [ -f "$INSTALL_PATH" ]; then
        printmsg "检测到已安装版本。如果需要重新安装，请先运行 'sudo $(basename $INSTALL_PATH)' 并选择卸载。" "$YELLOW"
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
