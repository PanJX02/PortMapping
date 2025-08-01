#!/bin/bash

# VPN端口映射测试脚本
# 作者: AI Assistant
# 版本: 1.0.0
# 日期: 2025-08-01

# 设置错误处理
set -e
trap 'echo "测试过程中出现错误，请检查日志"; exit 1' ERR

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 打印带颜色的消息
print_msg() {
    local color=$1
    local message=$2
    echo -e "${color}[$(date '+%Y-%m-%d %H:%M:%S')] ${message}${NC}"
}

# 检查root权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_msg $RED "错误: 此脚本必须以root权限运行"
        print_msg $YELLOW "请使用: sudo $0"
        exit 1
    fi
    print_msg $GREEN "Root权限检查通过"
}

# 检查vpn脚本是否已安装
check_vpn_installed() {
    if [[ ! -f "/usr/local/bin/vpn" ]]; then
        print_msg $RED "错误: VPN端口映射工具未安装"
        print_msg $YELLOW "请先运行安装脚本: sudo bash install.sh"
        exit 1
    fi
    print_msg $GREEN "VPN端口映射工具已安装"
}

# 测试基本功能
test_basic_functions() {
    print_msg $YELLOW "测试基本功能..."
    
    # 测试版本显示
    print_msg $BLUE "测试版本显示:"
    /usr/local/bin/vpn version
    
    # 测试帮助显示
    print_msg $BLUE "测试帮助显示:"
    /usr/local/bin/vpn help | head -n 5
    
    # 测试状态显示
    print_msg $BLUE "测试状态显示:"
    /usr/local/bin/vpn status
    
    print_msg $GREEN "基本功能测试完成"
}

# 测试端口映射功能
test_port_mapping() {
    print_msg $YELLOW "测试端口映射功能..."
    
    # 测试添加映射
    local test_service_port=8080
    local test_start_port=10000
    local test_end_port=10010
    
    print_msg $BLUE "添加测试映射: $test_start_port-$test_end_port -> $test_service_port"
    /usr/local/bin/vpn $test_service_port $test_start_port $test_end_port
    
    # 验证映射是否添加成功
    print_msg $BLUE "验证映射状态:"
    /usr/local/bin/vpn status
    
    # 测试删除映射
    print_msg $BLUE "删除测试映射"
    /usr/local/bin/vpn off
    
    # 验证映射是否删除成功
    print_msg $BLUE "验证映射已删除:"
    /usr/local/bin/vpn status
    
    print_msg $GREEN "端口映射功能测试完成"
}

# 测试IP限制功能
test_ip_restriction() {
    print_msg $YELLOW "测试IP限制功能..."
    
    # 测试添加带IP限制的映射
    local test_service_port=8080
    local test_start_port=10000
    local test_end_port=10010
    local test_allowed_ip="192.168.1.100,192.168.1.101"
    
    print_msg $BLUE "添加带IP限制的测试映射: $test_start_port-$test_end_port -> $test_service_port (允许IP: $test_allowed_ip)"
    /usr/local/bin/vpn $test_service_port $test_start_port $test_end_port $test_allowed_ip
    
    # 验证映射是否添加成功
    print_msg $BLUE "验证映射状态:"
    /usr/local/bin/vpn status
    
    # 测试删除映射
    print_msg $BLUE "删除测试映射"
    /usr/local/bin/vpn off
    
    # 验证映射是否删除成功
    print_msg $BLUE "验证映射已删除:"
    /usr/local/bin/vpn status
    
    print_msg $GREEN "IP限制功能测试完成"
}

# 测试日志功能
test_logging() {
    print_msg $YELLOW "测试日志功能..."
    
    # 检查日志文件是否存在
    if [[ -f "/var/log/vpn/portforward.log" ]]; then
        print_msg $BLUE "日志文件存在，显示最后10行:"
        tail -n 10 /var/log/vpn/portforward.log
    else
        print_msg $RED "日志文件不存在"
    fi
    
    print_msg $GREEN "日志功能测试完成"
}

# 主函数
main() {
    print_msg $GREEN "开始VPN端口映射工具测试..."
    
    check_root
    check_vpn_installed
    test_basic_functions
    test_port_mapping
    test_ip_restriction
    test_logging
    
    print_msg $GREEN "所有测试完成!"
}

# 执行主函数
main