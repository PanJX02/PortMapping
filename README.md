# Hysteria2端口跳跃工具

[![版本](https://img.shields.io/badge/版本-1.0.2-blue.svg)](https://github.com/PanJX02/PortMapping)
[![许可证](https://img.shields.io/badge/许可证-MIT-green.svg)](https://github.com/PanJX02/PortMapping/blob/main/LICENSE)

## 项目简介

Hysteria2端口跳跃工具是专为V2bX和PPanel-node设计的Hysteria2节点端口跳跃解决方案。它允许您为Hysteria2节点配置端口跳跃功能，通过将多个外部端口映射到Hysteria2服务端口，实现客户端自动端口切换，有效应对网络封锁和QoS限制。本工具特别优化了对V2bX面板和PPanel-node的支持，提供一键配置端口跳跃范围的功能。

## 系统要求

- Linux操作系统（已测试：Ubuntu、Debian、CentOS、RHEL、Fedora、Arch Linux）
- Root权限
- 基本工具：bash、wget、iptables、curl、jq

## 安装方法

### 自动安装（推荐）

```bash
wget -N https://raw.githubusercontent.com/PanJX02/PortMapping/refs/heads/main/install.sh && sudo bash install.sh
```

### 更新安装脚本

如果您已经安装过本工具，可以使用以下命令更新安装脚本：

```bash
# 更新安装脚本并重新运行
wget -N https://raw.githubusercontent.com/PanJX02/PortMapping/refs/heads/main/install.sh && sudo bash install.sh
```

`-N` 参数会自动检查远程文件是否更新，只有当有新版本时才会下载覆盖本地文件。

### 手动安装

1. 下载主脚本：

```bash
sudo wget -O /usr/local/bin/vpn https://raw.githubusercontent.com/PanJX02/PortMapping/refs/heads/main/vpn.sh
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

1. 为Hysteria2节点添加端口跳跃
2. 删除特定Hysteria2端口跳跃配置
3. 取消所有端口跳跃配置
4. 查看当前Hysteria2端口跳跃状态
5. 查看流量统计
6. 检查更新
7. 查看日志
8. 显示版本信息
9. 卸载Hysteria2端口跳跃工具
0. 退出

### 命令行参数

```bash
# 为Hysteria2节点添加端口跳跃（将外部10000-20000端口映射到Hysteria2的443端口）
sudo vpn 443 10000 20000

# 为V2bX/PPanel-node的Hysteria2节点配置端口跳跃
sudo vpn 443 10000 20000

# 取消所有Hysteria2端口跳跃配置
sudo vpn off

# 查看当前Hysteria2端口跳跃状态
sudo vpn status

# 查看日志
sudo vpn log

# 检查更新
sudo vpn update

# 显示版本信息
sudo vpn version

# 显示帮助信息
sudo vpn help

# 卸载Hysteria2端口跳跃工具
sudo vpn uninstall
```

## 功能特点

- **Hysteria2优化**：专为Hysteria2协议优化的端口跳跃配置
- **V2bX兼容**：完美支持V2bX面板的Hysteria2节点配置
- **PPanel-node支持**：特别适配PPanel-node的端口跳跃需求
- **一键端口跳跃**：快速配置多个端口映射到Hysteria2服务
- **UDP协议优化**：针对Hysteria2的UDP传输进行特殊优化
- **端口范围灵活**：支持任意端口范围的跳跃配置
- **实时监控**：查看端口跳跃状态和流量使用情况
- **自动配置备份**：每次修改前自动备份现有配置
- **防封锁机制**：通过端口跳跃有效应对网络封锁
- **多系统支持**：兼容主流Linux发行版

## 常见问题

### Hysteria2端口跳跃不生效

1. 检查iptables服务是否正在运行：
   ```bash
   sudo systemctl status iptables
   ```

2. 检查防火墙是否允许相关端口：
   ```bash
   sudo iptables -L -n
   ```

3. 确认Hysteria2服务正在监听正确端口：
   ```bash
   sudo netstat -tulnp | grep hysteria
   ```

4. 查看日志文件获取详细信息：
   ```bash
   sudo cat /var/log/vpn/portforward.log
   ```

### V2bX/PPanel-node集成问题

1. 确保在面板中配置的Hysteria2端口与工具映射的目标端口一致
2. 检查面板生成的客户端配置是否包含正确的端口跳跃范围
3. 验证客户端是否能够连接到跳跃端口范围内的任意端口

### 更新失败

1. 检查网络连接
2. 确保GitHub可访问
3. 尝试手动更新：
   ```bash
   sudo wget -O /usr/local/bin/vpn https://raw.githubusercontent.com/PanJX02/PortMapping/refs/heads/main/vpn.sh
   sudo chmod +x /usr/local/bin/vpn
   ```

## 许可证

本项目采用MIT许可证。详情请参阅[LICENSE](https://github.com/PanJX02/port_mapping/blob/main/LICENSE)文件。

## 项目地址

[https://github.com/PanJX02/PortMapping](https://github.com/PanJX02/PortMapping)
