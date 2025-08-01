#!/bin/bash

# VPN端口映射工具
# 作者: AI Assistant
# 版本: 1.0.1
# 日期: 2025-08-01

# 设置错误处理
set -e
trap 'echo "执行过程中出现错误，请检查日志"; exit 1' ERR

# 配置信息
VERSION="1.0.1"
SCRIPTURL="https://raw.githubusercontent.com/PanJX02/portmapping/refs/heads/main/vpn.sh"
INSTALLDIR="/usr/local/bin"
SCRIPTNAME="vpn"
CONFIGDIR="/etc/vpn"
CONFIGFILE="$CONFIGDIR/portforward.conf"
MAPPINGSFILE="$CONFIGDIR/mappings.json"
IPTABLESRULES="/etc/iptables/rules.v4"
RULECOMMENT="VPNPORTFORWARD"
LOGDIR="/var/log/vpn"
LOGFILE="$LOGDIR/portforward.log"
MAX_MAPPINGS=10  # 最大映射数量限制

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
    printmsg $BLUE "项目地址: https://github.com/PanJX02/portmapping"
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

# 记录日志
logmsg() {
    local level=$1
    local message=$2
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message" >> $LOGFILE
    
    # 如果日志文件过大（超过10MB），则进行轮转
    if [[ -f "$LOGFILE" ]] && [[ $(stat -c%s "$LOGFILE") -gt 10485760 ]]; then
        mv "$LOGFILE" "${LOGFILE}.old"
        touch "$LOGFILE"
        chmod 640 "$LOGFILE"
        logmsg "INFO" "日志文件已轮转"
    fi
}

# 初始化映射文件
init_mappings_file() {
    if [[ ! -f "$MAPPINGSFILE" ]]; then
        echo '[]' > "$MAPPINGSFILE"
        chmod 640 "$MAPPINGSFILE"
    fi
}

# 添加iptables规则
addrules() {
    local service_port=$1
    local start_port=$2
    local end_port=$3
    local allowed_ips=$4
    local mapping_name=$5
    local protocol=${6:-"both"}  # 默认为TCP和UDP
    
    # 生成唯一ID
    local mapping_id="mapping_$(date +%s%N | md5sum | head -c 8)"
    
    # 添加新规则
    if [[ "$protocol" == "tcp" || "$protocol" == "both" ]]; then
        if [[ -n "$allowed_ips" && "$allowed_ips" != "all" ]]; then
            # 对特定IP添加规则
            for ip in $(echo $allowed_ips | tr ',' ' '); do
                iptables -t nat -A PREROUTING -p tcp -s $ip --dport $start_port:$end_port -j DNAT --to-destination :$service_port -m comment --comment "${RULECOMMENT}_${mapping_id}"
            done
        else
            # 对所有IP添加规则
            iptables -t nat -A PREROUTING -p tcp --dport $start_port:$end_port -j DNAT --to-destination :$service_port -m comment --comment "${RULECOMMENT}_${mapping_id}"
        fi
    fi
    
    if [[ "$protocol" == "udp" || "$protocol" == "both" ]]; then
        if [[ -n "$allowed_ips" && "$allowed_ips" != "all" ]]; then
            # 对特定IP添加规则
            for ip in $(echo $allowed_ips | tr ',' ' '); do
                iptables -t nat -A PREROUTING -p udp -s $ip --dport $start_port:$end_port -j DNAT --to-destination :$service_port -m comment --comment "${RULECOMMENT}_${mapping_id}"
            done
        else
            # 对所有IP添加规则
            iptables -t nat -A PREROUTING -p udp --dport $start_port:$end_port -j DNAT --to-destination :$service_port -m comment --comment "${RULECOMMENT}_${mapping_id}"
        fi
    fi
    
    # 保存规则
    if command -v netfilter-persistent &> /dev/null; then
        netfilter-persistent save
    elif command -v iptables-save &> /dev/null; then
        iptables-save > $IPTABLESRULES
    fi
    
    # 保存映射信息到JSON文件
    init_mappings_file
    local temp_file=$(mktemp)
    jq --arg id "$mapping_id" \
       --arg name "${mapping_name:-"映射 $start_port-$end_port -> $service_port"}" \
       --arg service_port "$service_port" \
       --arg start_port "$start_port" \
       --arg end_port "$end_port" \
       --arg allowed_ips "${allowed_ips:-all}" \
       --arg protocol "$protocol" \
       --arg created "$(date '+%Y-%m-%d %H:%M:%S')" \
       '. + [{"id": $id, "name": $name, "service_port": $service_port, "start_port": $start_port, "end_port": $end_port, "allowed_ips": $allowed_ips, "protocol": $protocol, "created": $created}]' \
       "$MAPPINGSFILE" > "$temp_file" && mv "$temp_file" "$MAPPINGSFILE"
    
    # 记录日志
    logmsg "INFO" "添加端口映射: ID=$mapping_id, $start_port-$end_port -> $service_port, 允许IP=${allowed_ips:-all}, 协议=$protocol"
    
    printmsg $GREEN "端口映射已添加: $start_port-$end_port -> $service_port"
    if [[ -n "$allowed_ips" && "$allowed_ips" != "all" ]]; then
        printmsg $GREEN "允许访问的IP: $allowed_ips"
    fi
    printmsg $GREEN "映射ID: $mapping_id"
}

# 删除特定映射规则
delete_mapping() {
    local mapping_id=$1
    
    # 查找并删除规则
    while read -r rule; do
        if [[ -n "$rule" ]]; then
            iptables -t nat -D $rule
        fi
    done < <(iptables -t nat -L PREROUTING --line-numbers | grep "${RULECOMMENT}_${mapping_id}" | awk '{print $1}' | sort -nr)
    
    # 保存规则
    if command -v netfilter-persistent &> /dev/null; then
        netfilter-persistent save
    elif command -v iptables-save &> /dev/null; then
        iptables-save > $IPTABLESRULES
    fi
    
    # 从JSON文件中删除映射
    init_mappings_file
    local temp_file=$(mktemp)
    jq --arg id "$mapping_id" 'map(select(.id != $id))' "$MAPPINGSFILE" > "$temp_file" && mv "$temp_file" "$MAPPINGSFILE"
    
    # 记录日志
    logmsg "INFO" "删除端口映射: ID=$mapping_id"
    
    printmsg $GREEN "端口映射 $mapping_id 已删除"
}

# 删除所有iptables规则
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
    echo '[]' > "$MAPPINGSFILE"
    
    # 记录日志
    logmsg "INFO" "删除所有端口映射"
    
    printmsg $GREEN "所有端口映射已删除"
}

# 显示当前状态
showstatus() {
    printmsg $BLUE "当前端口映射状态:"
    
    init_mappings_file
    local mappings_count=$(jq 'length' "$MAPPINGSFILE")
    
    if [[ "$mappings_count" -gt 0 ]]; then
        printmsg $GREEN "当前有 $mappings_count 个活动的端口映射:"
        echo
        
        # 显示所有映射
        local i=0
        while [[ $i -lt $mappings_count ]]; do
            local id=$(jq -r .[$i].id "$MAPPINGSFILE")
            local name=$(jq -r .[$i].name "$MAPPINGSFILE")
            local service_port=$(jq -r .[$i].service_port "$MAPPINGSFILE")
            local start_port=$(jq -r .[$i].start_port "$MAPPINGSFILE")
            local end_port=$(jq -r .[$i].end_port "$MAPPINGSFILE")
            local allowed_ips=$(jq -r .[$i].allowed_ips "$MAPPINGSFILE")
            local protocol=$(jq -r .[$i].protocol "$MAPPINGSFILE")
            local created=$(jq -r .[$i].created "$MAPPINGSFILE")
            
            printmsg $BLUE "映射 #$((i+1)):"
            printmsg $GREEN "  ID: $id"
            printmsg $GREEN "  名称: $name"
            printmsg $GREEN "  端口映射: $start_port-$end_port -> $service_port"
            printmsg $GREEN "  协议: $protocol"
            printmsg $GREEN "  允许的IP: $allowed_ips"
            printmsg $GREEN "  创建时间: $created"
            echo
            
            i=$((i+1))
        done
        
        # 显示iptables规则
        printmsg $BLUE "iptables规则:"
        iptables -t nat -L PREROUTING | grep "$RULECOMMENT"
    else
        printmsg $YELLOW "没有活动的端口映射"
    fi
    
    # 显示系统信息
    printmsg $BLUE "\n系统信息:"
    printmsg $GREEN "  操作系统: $(cat /etc/*release | grep -E "^NAME=" | cut -d= -f2 | tr -d '"')"
    printmsg $GREEN "  内核版本: $(uname -r)"
    printmsg $GREEN "  iptables版本: $(iptables --version)"
    printmsg $GREEN "  脚本版本: $VERSION"
}

# 显示交互式菜单
showmenu() {
    while true; do
        clear
        showversion
        echo
        printmsg $BLUE "===== VPN端口映射工具菜单 ====="
        echo
        printmsg $GREEN "1. 添加新的端口映射"
        printmsg $GREEN "2. 删除特定端口映射"
        printmsg $GREEN "3. 取消所有端口映射"
        printmsg $GREEN "4. 查看当前映射状态"
        printmsg $GREEN "5. 查看流量统计"
        printmsg $GREEN "6. 检查更新"
        printmsg $GREEN "7. 查看日志"
        printmsg $GREEN "8. 显示版本信息"
        printmsg $GREEN "9. 卸载VPN端口映射工具"
        printmsg $GREEN "0. 退出"
        echo
        read -p "请选择操作 [0-9]: " choice
        
        case $choice in
            1)
                echo
                read -p "请输入映射名称 (可选): " mapping_name
                read -p "请输入服务端口: " service_port
                read -p "请输入起始端口: " start_port
                read -p "请输入结束端口: " end_port
                read -p "请选择协议 [tcp/udp/both] (默认both): " protocol
                protocol=${protocol:-"both"}
                read -p "请输入允许访问的IP地址 (多个IP用逗号分隔，留空表示允许所有IP): " allowed_ips
                
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
                
                if [[ "$protocol" != "tcp" && "$protocol" != "udp" && "$protocol" != "both" ]]; then
                    printmsg $RED "错误: 协议必须是tcp、udp或both"
                    read -p "按Enter键继续..."
                    continue
                fi
                
                # 检查映射数量限制
                init_mappings_file
                local mappings_count=$(jq 'length' "$MAPPINGSFILE")
                if [[ "$mappings_count" -ge $MAX_MAPPINGS ]]; then
                    printmsg $RED "错误: 已达到最大映射数量限制 ($MAX_MAPPINGS)"
                    printmsg $YELLOW "请先删除一些现有映射再添加新映射"
                    read -p "按Enter键继续..."
                    continue
                fi
                
                addrules "$service_port" "$start_port" "$end_port" "$allowed_ips" "$mapping_name" "$protocol"
                read -p "按Enter键继续..."
                ;;
            2)
                echo
                init_mappings_file
                local mappings_count=$(jq 'length' "$MAPPINGSFILE")
                
                if [[ "$mappings_count" -eq 0 ]]; then
                    printmsg $YELLOW "没有活动的端口映射"
                    read -p "按Enter键继续..."
                    continue
                fi
                
                printmsg $BLUE "当前活动的端口映射:"
                echo
                
                # 显示所有映射
                local i=0
                while [[ $i -lt $mappings_count ]]; do
                    local id=$(jq -r .[$i].id "$MAPPINGSFILE")
                    local name=$(jq -r .[$i].name "$MAPPINGSFILE")
                    local service_port=$(jq -r .[$i].service_port "$MAPPINGSFILE")
                    local start_port=$(jq -r .[$i].start_port "$MAPPINGSFILE")
                    local end_port=$(jq -r .[$i].end_port "$MAPPINGSFILE")
                    
                    printmsg $GREEN "$((i+1)). $name ($start_port-$end_port -> $service_port) [ID: $id]"
                    
                    i=$((i+1))
                done
                
                echo
                read -p "请输入要删除的映射编号 [1-$mappings_count] (输入0取消): " del_choice
                
                if [[ "$del_choice" =~ ^[0-9]+$ ]] && [[ "$del_choice" -ge 1 ]] && [[ "$del_choice" -le $mappings_count ]]; then
                    local mapping_id=$(jq -r .[$(($del_choice-1))].id "$MAPPINGSFILE")
                    delete_mapping "$mapping_id"
                elif [[ "$del_choice" != "0" ]]; then
                    printmsg $RED "无效选择"
                fi
                
                read -p "按Enter键继续..."
                ;;
            3)
                deleterules
                read -p "按Enter键继续..."
                ;;
            4)
                showstatus
                read -p "按Enter键继续..."
                ;;
            5)
                printmsg $BLUE "端口映射流量统计:"
                echo
                
                init_mappings_file
                local mappings_count=$(jq 'length' "$MAPPINGSFILE")
                
                if [[ "$mappings_count" -eq 0 ]]; then
                    printmsg $YELLOW "没有活动的端口映射"
                    read -p "按Enter键继续..."
                    continue
                fi
                
                # 显示所有映射的流量统计
                local i=0
                while [[ $i -lt $mappings_count ]]; do
                    local id=$(jq -r .[$i].id "$MAPPINGSFILE")
                    local name=$(jq -r .[$i].name "$MAPPINGSFILE")
                    local service_port=$(jq -r .[$i].service_port "$MAPPINGSFILE")
                    local start_port=$(jq -r .[$i].start_port "$MAPPINGSFILE")
                    local end_port=$(jq -r .[$i].end_port "$MAPPINGSFILE")
                    
                    printmsg $GREEN "$name ($start_port-$end_port -> $service_port):"
                    
                    # 获取TCP流量统计
                    local tcp_packets=$(iptables -t nat -L PREROUTING -v | grep "${RULECOMMENT}_${id}" | grep "tcp" | awk '{sum+=$1} END {print sum}')
                    local tcp_bytes=$(iptables -t nat -L PREROUTING -v | grep "${RULECOMMENT}_${id}" | grep "tcp" | awk '{sum+=$2} END {print sum}')
                    
                    # 获取UDP流量统计
                    local udp_packets=$(iptables -t nat -L PREROUTING -v | grep "${RULECOMMENT}_${id}" | grep "udp" | awk '{sum+=$1} END {print sum}')
                    local udp_bytes=$(iptables -t nat -L PREROUTING -v | grep "${RULECOMMENT}_${id}" | grep "udp" | awk '{sum+=$2} END {print sum}')
                    
                    # 显示流量统计
                    printmsg $BLUE "  TCP: ${tcp_packets:-0} 个数据包, ${tcp_bytes:-0} 字节"
                    printmsg $BLUE "  UDP: ${udp_packets:-0} 个数据包, ${udp_bytes:-0} 字节"
                    echo
                    
                    i=$((i+1))
                done
                
                read -p "按Enter键继续..."
                ;;
            6)
                checkupdate
                read -p "按Enter键继续..."
                ;;
            7)
                if [[ -f "$LOGFILE" ]]; then
                    printmsg $BLUE "最近的日志记录 (最后20行):"
                    echo
                    tail -n 20 "$LOGFILE"
                    echo
                    read -p "查看更多日志? [y/N]: " more_logs
                    if [[ "$more_logs" =~ ^[Yy]$ ]]; then
                        less "$LOGFILE"
                    fi
                else
                    printmsg $YELLOW "日志文件不存在"
                fi
                read -p "按Enter键继续..."
                ;;
            8)
                showversion
                read -p "按Enter键继续..."
                ;;
            9)
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
    
    # 记录卸载日志
    logmsg "INFO" "开始卸载VPN端口映射工具"
    
    # 删除所有端口映射规则
    printmsg $YELLOW "删除所有端口映射规则..."
    deleterules
    
    # 删除cron任务
    printmsg $YELLOW "删除自动更新任务..."
    (crontab -l 2>/dev/null | grep -v "$SCRIPTNAME update --cron") | crontab -
    
    # 备份配置文件
    if [[ -f "$MAPPINGSFILE" ]]; then
        printmsg $YELLOW "备份映射配置..."
        cp "$MAPPINGSFILE" "${MAPPINGSFILE}.backup.$(date +%Y%m%d%H%M%S)"
        printmsg $GREEN "配置已备份到 ${MAPPINGSFILE}.backup.$(date +%Y%m%d%H%M%S)"
    fi
    
    # 删除配置文件和目录
    printmsg $YELLOW "删除配置文件和目录..."
    if [[ -d "$CONFIGDIR" ]]; then
        rm -rf "$CONFIGDIR"
    fi
    
    # 保留日志文件
    printmsg $YELLOW "保留日志文件在 $LOGDIR"
    
    # 删除主脚本文件
    printmsg $YELLOW "删除主脚本文件..."
    if [[ -f "$INSTALLDIR/$SCRIPTNAME" ]]; then
        rm -f "$INSTALLDIR/$SCRIPTNAME"
    fi
    
    # 记录卸载完成日志
    logmsg "INFO" "VPN端口映射工具卸载完成"
    
    printmsg $GREEN "VPN端口映射工具已成功卸载!"
    printmsg $BLUE "如需重新安装，请运行: wget -N https://raw.githubusercontent.com/PanJX02/portmapping/refs/heads/main/install.sh && bash install.sh"
}

# 检查依赖
check_dependencies() {
    local missing_deps=0
    
    # 检查必要的命令
    for cmd in iptables jq curl; do
        if ! command -v $cmd &> /dev/null; then
            printmsg $RED "错误: 缺少必要的依赖: $cmd"
            missing_deps=1
        fi
    done
    
    if [[ $missing_deps -eq 1 ]]; then
        printmsg $YELLOW "请安装缺少的依赖后再运行此脚本"
        printmsg $YELLOW "Debian/Ubuntu: apt-get install iptables jq curl"
        printmsg $YELLOW "CentOS/RHEL: yum install iptables jq curl"
        printmsg $YELLOW "Arch Linux: pacman -S iptables jq curl"
        exit 1
    fi
}

# 初始化环境
initialize() {
    # 确保配置目录存在
    mkdir -p "$CONFIGDIR"
    
    # 确保日志目录存在
    mkdir -p "$LOGDIR"
    
    # 如果日志文件不存在，创建它
    if [[ ! -f "$LOGFILE" ]]; then
        touch "$LOGFILE"
        chmod 640 "$LOGFILE"
    fi
    
    # 初始化映射文件
    init_mappings_file
    
    # 记录启动日志
    logmsg "INFO" "VPN端口映射工具 v$VERSION 启动"
}

# 主程序
main() {
    # 检查root权限
    checkroot
    
    # 检查依赖
    check_dependencies
    
    # 初始化环境
    initialize
    
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
                "log")
                    if [[ -f "$LOGFILE" ]]; then
                        less "$LOGFILE"
                    else
                        printmsg $YELLOW "日志文件不存在"
                    fi
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
                "--cron")
                    # 静默模式，用于cron任务
                    checkupdate > /dev/null
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
        4)
            # 带IP限制的端口映射
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
            
            addrules "$1" "$2" "$3" "$4"
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
