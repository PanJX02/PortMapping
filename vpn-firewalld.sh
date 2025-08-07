#!/bin/bash
# VPN端口映射主脚本 (v4.0 - Firewalld 版本)
# 通过 firewall-cmd 实现端口转发
# 作者: PanJX02 (由 AI 协助重构)

# --- 基本配置 ---
INSTALL_DIR="/etc/vpn"
DATA_FILE="$INSTALL_DIR/portforward.rules"
LOG_FILE="$INSTALL_DIR/log/vpn.log"

# --- 颜色定义 ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# --- 函数 (与UFW版本类似，但核心命令不同) ---
log_action() { echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"; }
print_msg() { echo -e "${1}${2}${NC}"; }
validate_ip() { [[ $1 =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; }
validate_port() { (( $1 > 0 && $1 < 65536 )); }

reload_firewall() {
    print_msg $YELLOW "正在重载 Firewalld 以应用更改..."
    if firewall-cmd --reload >/dev/null 2>&1; then
        print_msg $GREEN "Firewalld 重载成功！"
    else
        print_msg $RED "Firewalld 重载失败，请检查配置。"
    fi
}

add_rule() {
    print_msg $YELLOW "--- 添加新的端口映射规则 (Firewalld) ---"
    # Firewalld转发通常不需指定接口，它基于区域
    
    read -rp "$(echo -e ${BLUE}"1. 请输入公网端口 (1-65535): "${NC})" public_port
    while ! validate_port "$public_port"; do
        read -rp "$(echo -e ${RED}"无效端口，请重新输入: "${NC})" public_port
    done

    read -rp "$(echo -e ${BLUE}"2. 请输入目标设备私网IP (如 10.0.0.2): "${NC})" private_ip
    while ! validate_ip "$private_ip"; do
        read -rp "$(echo -e ${RED}"无效IP地址，请重新输入: "${NC})" private_ip
    done

    read -rp "$(echo -e ${BLUE}"3. 请输入目标设备私网端口 (默认同公网端口): "${NC})" private_port
    private_port=${private_port:-$public_port}
    while ! validate_port "$private_port"; do
        read -rp "$(echo -e ${RED}"无效端口，请重新输入: "${NC})" private_port
    done

    read -rp "$(echo -e ${BLUE}"4. 请选择协议 (tcp/udp/all, 默认 all): "${NC})" protocol
    protocol=$(echo "${protocol:-all}" | tr '[:upper:]' '[:lower:]')

    add_protocol_rule() {
        local proto=$1
        print_msg $YELLOW "  -> 添加 ${proto} 规则..."
        firewall-cmd --permanent --add-forward-port=port=${public_port}:proto=${proto}:toport=${private_port}:toaddr=${private_ip} >/dev/null
        # 数据文件不关心接口，用 'firewalld' 代替
        echo "${public_port};${proto};${private_ip};${private_port};firewalld" >> "$DATA_FILE"
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
    
    log_action "ADD rule: port ${public_port} -> ${private_ip}:${private_port} proto ${protocol}"
    reload_firewall
    print_msg $GREEN "规则添加成功并已持久化。"
}

delete_rule() {
    if [ ! -s "$DATA_FILE" ]; then
        print_msg $YELLOW "当前没有任何端口映射规则。"
        return
    fi

    print_msg $YELLOW "--- 删除现有端口映射规则 (Firewalld) ---"
    awk -F';' '{ printf "  %s%d) %-4s Public Port:%-5s -> %-15s:%-5s%s\n", "'"$BLUE"'", NR, toupper($2), $1, $3, $4, "'"$NC"'" }' "$DATA_FILE"
    
    read -rp "$(echo -e ${BLUE}"请输入要删除的规则编号 (或输入 'q' 退出): "${NC})" choice
    # ... (输入验证逻辑) ...

    local line_to_delete=$(sed -n "${choice}p" "$DATA_FILE")
    IFS=';' read -r public_port proto private_ip private_port _ <<< "$line_to_delete"

    print_msg $YELLOW "  -> 删除 ${proto} 规则..."
    firewall-cmd --permanent --remove-forward-port=port=${public_port}:proto=${proto}:toport=${private_port}:toaddr=${private_ip} >/dev/null

    sed -i "${choice}d" "$DATA_FILE"
    log_action "DELETE rule: ${line_to_delete}"
    reload_firewall
    print_msg $GREEN "规则删除成功。"
}

list_rules() {
    print_msg $YELLOW "--- 当前端口映射规则 (来自数据文件) ---"
    if [ ! -s "$DATA_FILE" ]; then
        print_msg $BLUE "没有任何活动的端口映射规则。"
    else
        echo -e "${BLUE}  #  Proto  Public Port  ->  Private IP:Port${NC}"
        echo -e "${BLUE}-------------------------------------------------${NC}"
        awk -F';' '{ printf "  %-2d %-6s %-12s -> %-15s:%-5s\n", NR, toupper($2), $1, $3, $4 }' "$DATA_FILE"
        echo -e "${BLUE}-------------------------------------------------${NC}"
    fi

    print_msg $YELLOW "\n--- 当前活动的 Firewalld 转发规则 (实时) ---"
    firewall-cmd --list-forward-ports
}

# --- 主程序入口 (与UFW/iptables版本结构相同) ---
# ... (包含 show_help, show_menu, 和 case "$1" in ... esac 的逻辑)
show_menu() {
    while true; do
        clear
        echo -e "${GREEN}===========================================${NC}"
        echo -e "${GREEN}  VPN 端口映射管理 (Firewalld 模式)  ${NC}"
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
            3) ;;
            q|Q) echo "退出。"; exit 0 ;;
            *) print_msg $RED "无效选项!" ;;
        esac
        [ "$choice" != "3" ] && read -n 1 -s -r -p "按任意键返回菜单..."
    done
}

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
