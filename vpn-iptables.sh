#!/bin/bash
# VPN端口映射主脚本 (v3.0 - iptables-persistent 版本)
# 通过直接操作 iptables 并依赖持久化服务来工作
# 作者: PanJX02 (由 AI 协助重构)

# --- 基本配置 ---
INSTALL_DIR="/etc/vpn"
DATA_FILE="$INSTALL_DIR/portforward.rules"
LOG_FILE="$INSTALL_DIR/log/vpn.log"
IPTABLES_SAVE_CMD=""

# --- 颜色定义 ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# --- 函数 ---
log_action() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

print_msg() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

get_public_interfaces() {
    ip -o link show | awk -F': ' '{print $2}' | grep -vE 'lo|docker|veth|br-'
}

validate_ip() {
    [[ $1 =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]] && return 0 || return 1
}

validate_port() {
    (( $1 > 0 && $1 < 65536 )) && return 0 || return 1
}

save_rules() {
    print_msg $YELLOW "正在保存规则使其永久生效..."
    if command -v netfilter-persistent &> /dev/null; then
        netfilter-persistent save >/dev/null
    elif command -v service &> /dev/null && service iptables save &> /dev/null; then
        # CentOS/RHEL
        :
    else
        print_msg $RED "警告: 未找到规则持久化工具 (netfilter-persistent 或 iptables-services)。规则将在重启后丢失。"
        return 1
    fi
    print_msg $GREEN "规则已保存。"
}

add_rule() {
    print_msg $YELLOW "--- 添加新的端口映射规则 ---"

    # 选择公网网卡
    print_msg $BLUE "1. 请选择公网网卡:"
    readarray -t interfaces < <(get_public_interfaces)
    if [ ${#interfaces[@]} -eq 0 ]; then
        print_msg $RED "错误: 未找到合适的公网网卡。"
        return 1
    fi
    select public_iface in "${interfaces[@]}"; do
        if [[ -n "$public_iface" ]]; then
            break
        else
            print_msg $RED "无效选择，请重试。"
        fi
    done
    
    # 输入公网端口
    read -rp "$(echo -e ${BLUE}"2. 请输入公网端口 (1-65535): "${NC})" public_port
    while ! validate_port "$public_port"; do
        read -rp "$(echo -e ${RED}"无效端口，请重新输入 (1-65535): "${NC})" public_port
    done

    # 输入私网IP
    read -rp "$(echo -e ${BLUE}"3. 请输入目标设备私网IP (如 10.0.0.2): "${NC})" private_ip
    while ! validate_ip "$private_ip"; do
        read -rp "$(echo -e ${RED}"无效IP地址，请重新输入: "${NC})" private_ip
    done

    # 输入私网端口
    read -rp "$(echo -e ${BLUE}"4. 请输入目标设备私网端口 (默认同公网端口): "${NC})" private_port
    private_port=${private_port:-$public_port}
    while ! validate_port "$private_port"; do
        read -rp "$(echo -e ${RED}"无效端口，请重新输入 (1-65535): "${NC})" private_port
    done

    # 选择协议
    read -rp "$(echo -e ${BLUE}"5. 请选择协议 (tcp/udp/all, 默认 all): "${NC})" protocol
    protocol=$(echo "${protocol:-all}" | tr '[:upper:]' '[:lower:]')

    add_protocol_rule() {
        local proto=$1
        iptables -t nat -A PREROUTING -i "${public_iface}" -p "${proto}" --dport "${public_port}" -j DNAT --to-destination "${private_ip}:${private_port}"
        iptables -t nat -A POSTROUTING -s "${private_ip}/32" -d "${private_ip}/32" -p "${proto}" --dport "${private_port}" -j MASQUERADE
        iptables -A FORWARD -i "${public_iface}" -d "${private_ip}" -p "${proto}" --dport "${private_port}" -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT
        iptables -A FORWARD -o "${public_iface}" -s "${private_ip}" -j ACCEPT
        echo "${public_port};${proto};${private_ip};${private_port};${public_iface}" >> "$DATA_FILE"
    }

    if [[ "$protocol" == "all" ]]; then
        add_protocol_rule "tcp"
        add_protocol_rule "udp"
    elif [[ "$protocol" == "tcp" ]] || [[ "$protocol" == "udp" ]]; then
        add_protocol_rule "$protocol"
    else
        print_msg $RED "协议无效！操作已取消。"
        return 1
    fi
    
    log_action "ADD rule: ${public_iface}:${public_port} -> ${private_ip}:${private_port} proto ${protocol}"
    print_msg $GREEN "iptables 规则已添加成功！"
    save_rules
}

delete_rule() {
    if [ ! -s "$DATA_FILE" ]; then
        print_msg $YELLOW "当前没有任何端口映射规则。"
        return
    fi
    
    print_msg $YELLOW "--- 删除现有端口映射规则 ---"
    print_msg $BLUE "以下是当前活动的规则:"
    awk -F';' '{ printf "  %s%d) %-4s %-15s:%-5s -> %-15s:%-5s%s\n", "'"$BLUE"'", NR, $2, $5, $1, $3, $4, "'"$NC"'" }' "$DATA_FILE"
    
    read -rp "$(echo -e ${BLUE}"请输入要删除的规则编号 (或输入 'q' 退出): "${NC})" choice
    if [[ "$choice" == "q" ]]; then
        print_msg $YELLOW "操作已取消。"
        return
    fi
    
    local total_lines=$(wc -l < "$DATA_FILE")
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "$total_lines" ]; then
        print_msg $RED "无效的编号。"
        return 1
    fi

    local line_to_delete=$(sed -n "${choice}p" "$DATA_FILE")
    IFS=';' read -r public_port proto private_ip private_port public_iface <<< "$line_to_delete"
    
    # 删除规则
    iptables -t nat -D PREROUTING -i "${public_iface}" -p "${proto}" --dport "${public_port}" -j DNAT --to-destination "${private_ip}:${private_port}"
    iptables -t nat -D POSTROUTING -s "${private_ip}/32" -d "${private_ip}/32" -p "${proto}" --dport "${private_port}" -j MASQUERADE
    iptables -D FORWARD -i "${public_iface}" -d "${private_ip}" -p "${proto}" --dport "${private_port}" -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT
    iptables -D FORWARD -o "${public_iface}" -s "${private_ip}" -j ACCEPT

    sed -i "${choice}d" "$DATA_FILE"
    log_action "DELETE rule: ${line_to_delete}"
    print_msg $GREEN "iptables 规则已成功删除！"
    save_rules
}

list_rules() {
    print_msg $YELLOW "--- 当前端口映射规则 (来自数据文件) ---"
    if [ ! -s "$DATA_FILE" ]; then
        print_msg $BLUE "没有任何活动的端口映射规则。"
    else
        echo -e "${BLUE}  #  Proto  Public IFace:Port  ->  Private IP:Port${NC}"
        echo -e "${BLUE}-------------------------------------------------------${NC}"
        awk -F';' '{ printf "  %-2d %-6s %-15s:%-5s -> %-15s:%-5s\n", NR, toupper($2), $5, $1, $3, $4 }' "$DATA_FILE"
        echo -e "${BLUE}-------------------------------------------------------${NC}"
    fi

    print_msg $YELLOW "\n--- 当前活动的 iptables NAT & FORWARD 规则 (实时) ---"
    iptables -t nat -L PREROUTING -n -v --line-numbers | grep DNAT
    iptables -L FORWARD -n -v --line-numbers | grep ACCEPT
}

show_help() {
    echo "VPN 端口映射工具 (iptables 模式)"
    echo "用法: sudo vpn [命令]"
    echo ""
    echo "命令:"
    echo "  <无命令>  - 显示交互式菜单"
    echo "  add       - 添加一条新的映射规则"
    echo "  delete    - 删除一条现有的映射规则"
    echo "  status    - 列出所有映射规则"
    echo "  help      - 显示此帮助信息"
    echo ""
}

show_menu() {
    while true; do
        clear
        echo -e "${GREEN}===========================================${NC}"
        echo -e "${GREEN}  VPN 端口映射管理 (iptables 模式)  ${NC}"
        echo -e "${GREEN}===========================================${NC}"
        list_rules
        echo ""
        echo -e "${BLUE}请选择操作:${NC}"
        echo "  1) 添加规则"
        echo "  2) 删除规则"
        echo "  3) 刷新状态"
        echo "  q) 退出"
        
        read -rp "$(echo -e ${BLUE}"请输入选项 [1-3, q]: "${NC})" choice
        case $choice in
            1) add_rule ;;
            2) delete_rule ;;
            3) ;; # 刷新就是重新循环
            q|Q) echo "退出。"; exit 0 ;;
            *) print_msg $RED "无效选项!" ;;
        esac
        
        if [ "$choice" != "3" ]; then
          read -n 1 -s -r -p "按任意键返回菜单..."
        fi
    done
}

# --- 主程序入口 ---
if [[ $EUID -ne 0 ]]; then
   print_msg $RED "此脚本必须以 root 权限运行。请使用 'sudo vpn'"
   exit 1
fi

case "$1" in
    add) add_rule ;;
    delete|del) delete_rule ;;
    status|list) list_rules ;;
    help) show_help ;;
    *) show_menu ;;
esac
