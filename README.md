# UDP端口映射工具 - 适用于V2bX/PPanel-node的Hysteria2节点

[![版本](https://img.shields.io/badge/版本-1.1.0-blue.svg)](https://github.com/PanJX02/PortMapping)
[![许可证](https://img.shields.io/badge/许可证-MIT-green.svg)](https://github.com/PanJX02/PortMapping/blob/main/LICENSE)

## 项目简介

这是一个简单易用的Linux服务器端口转发工具，专为UDP协议服务（如Hysteria2）设计。它允许您将服务器上的一个或多个UDP端口范围映射到指定的服务端口，实现端口跳跃功能。特别适合为V2bX面板和PPanel-node的Hysteria2节点配置端口跳跃，通过简单的命令行界面，您可以快速配置和管理端口映射规则，支持主流Ubuntu和Debian，并提供自动持久化功能。

## 系统要求

- Linux操作系统（已测试：Ubuntu、Debian）
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

1. 添加/修改端口映射
2. 取消所有端口映射
3. 查看当前映射状态
4. 检查更新
5. 显示版本信息
6. 卸载VPN端口映射工具
0. 退出

### 命令行参数

```bash
# 为Hysteria2节点添加端口跳跃（将外部10000-20000端口映射到Hysteria2的443端口）
sudo vpn 443 10000 20000

# 为V2bX/PPanel-node的Hysteria2节点配置端口跳跃
sudo vpn 443 10000 20000

# 取消所有端口映射
sudo vpn off

# 查看当前映射状态
sudo vpn status

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

- **UDP协议专用**：专为Hysteria2的UDP传输优化，仅支持UDP协议
- **V2bX/PPanel-node适用**：特别适合为V2bX面板和PPanel-node的Hysteria2节点配置端口跳跃
- **端口跳跃**：支持将端口范围映射到单个Hysteria2服务端口
- **一键配置**：通过简单命令快速设置端口跳跃规则
- **状态监控**：实时查看当前端口映射配置和状态
- **自动持久化**：规则自动保存，重启后依然生效
- **多系统支持**：兼容Ubuntu、Debian、CentOS、RHEL、Fedora、Arch Linux
- **交互式菜单**：提供友好的命令行界面
- **配置备份**：自动备份现有配置到/etc/vpn目录
- **日志记录**：详细记录所有操作和状态变化

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

3. 确认服务正在监听正确端口：
   ```bash
   sudo netstat -tulnp | grep <服务端口>
   ```

4. 查看日志文件获取详细信息：
   ```bash
   sudo cat /var/log/vpn/portforward.log
   ```

### 更新失败

1. 检查网络连接
2. 确保GitHub可访问
3. 尝试手动更新：
   ```bash
   sudo wget -O /usr/local/bin/vpn https://raw.githubusercontent.com/PanJX02/PortMapping/refs/heads/main/vpn.sh
   sudo chmod +x /usr/local/bin/vpn
   ```

## 许可证

本项目采用MIT许可证。详情请参阅[LICENSE](https://github.com/PanJX02/PortMapping/blob/main/LICENSE)文件。
