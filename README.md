# VPN端口映射工具

[![版本](https://img.shields.io/badge/版本-1.0.1-blue.svg)](https://github.com/PanJX02/port_mapping)
[![许可证](https://img.shields.io/badge/许可证-MIT-green.svg)](https://github.com/PanJX02/port_mapping/blob/main/LICENSE)

## 项目简介

VPN端口映射工具是一个简单易用的Linux服务器端口转发解决方案，专为VPN环境设计。它允许您将服务器上的一个或多个端口范围映射到指定的服务端口，支持TCP和UDP协议，并提供IP限制、流量统计和日志记录等功能。

## 系统要求

- Linux操作系统（已测试：Ubuntu、Debian、CentOS、RHEL、Fedora、Arch Linux）
- Root权限
- 基本工具：bash、wget、iptables、curl、jq

## 安装方法

### 自动安装（推荐）

```bash
wget -N https://raw.githubusercontent.com/PanJX02/PortMappingPortMapping/refs/heads/main/install.sh && sudo bash install.sh
```

### 手动安装

1. 下载主脚本：

```bash
sudo wget -O /usr/local/bin/vpn https://raw.githubusercontent.com/PanJX02/PortMappingPortMapping/refs/heads/main/vpn.sh
sudo chmod +x /usr/local/bin/vpn
```

2. 创建配置目录：

```bash
sudo mkdir -p /etc/vpn
sudo mkdir -p /var/log/vpn
```

3. 安装依赖：

```bash
# Debian/Ubuntu
sudo apt-get update
sudo apt-get install -y wget iptables iptables-persistent curl jq

# CentOS/RHEL/Fedora
sudo yum install -y wget iptables iptables-services curl jq

# Arch Linux
sudo pacman -Sy --noconfirm wget iptables curl jq
```

## 使用方法

### 交互式菜单

运行以下命令启动交互式菜单：

```bash
sudo vpn
```

菜单选项包括：

1. 添加新的端口映射
2. 删除特定端口映射
3. 取消所有端口映射
4. 查看当前映射状态
5. 查看流量统计
6. 检查更新
7. 查看日志
8. 显示版本信息
9. 卸载VPN端口映射工具
0. 退出

### 命令行参数

```bash
# 添加端口映射（将外部10000-20000端口映射到内部8080端口）
sudo vpn 8080 10000 20000

# 添加带IP限制的端口映射
sudo vpn 8080 10000 20000 192.168.1.100,192.168.1.101

# 取消所有端口映射
sudo vpn off

# 查看当前映射状态
sudo vpn status

# 查看日志
sudo vpn log

# 检查更新
sudo vpn update

# 显示版本信息
sudo vpn version

# 显示帮助信息
sudo vpn help

# 卸载工具
sudo vpn uninstall
```

## 功能特点

- **多组端口映射**：支持同时配置多个不同的端口映射规则
- **协议选择**：支持TCP、UDP或两者同时映射
- **IP限制**：可以限制只允许特定IP地址访问映射端口
- **流量统计**：查看每个映射的流量使用情况
- **日志记录**：详细记录所有操作和状态变化
- **自动更新**：每周自动检查更新
- **交互式菜单**：简单易用的命令行界面
- **命令行参数**：支持通过命令行直接操作
- **配置备份**：自动备份现有配置
- **多系统支持**：兼容多种Linux发行版

## 常见问题

### 端口映射不生效

1. 检查iptables服务是否正在运行：
   ```bash
   sudo systemctl status iptables
   ```

2. 检查防火墙是否允许相关端口：
   ```bash
   sudo iptables -L -n
   ```

3. 查看日志文件获取详细信息：
   ```bash
   sudo cat /var/log/vpn/portforward.log
   ```

### 更新失败

1. 检查网络连接
2. 确保GitHub可访问
3. 尝试手动更新：
   ```bash
   sudo wget -O /usr/local/bin/vpn https://raw.githubusercontent.com/PanJX02/PortMappingPortMapping/refs/heads/main/vpn.sh
   sudo chmod +x /usr/local/bin/vpn
   ```

## 许可证

本项目采用MIT许可证。详情请参阅[LICENSE](https://github.com/PanJX02/port_mapping/blob/main/LICENSE)文件。

## 项目地址

[https://github.com/PanJX02/port_mapping](https://github.com/PanJX02/port_mapping)
