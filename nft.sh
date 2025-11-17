#!/bin/bash

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 1. 检查 Root 权限
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}[错误] 请使用 root 权限运行此脚本 (sudo ./setup_firewall.sh)${NC}"
  exit 1
fi

echo -e "${YELLOW}[信息] 正在检查系统环境...${NC}"

# 2. 检测并安装 nftables
if ! command -v nft &> /dev/null; then
    echo -e "${YELLOW}[提示] 未检测到 nftables，尝试自动安装...${NC}"
    if [ -f /etc/debian_version ]; then
        apt-get update && apt-get install -y nftables
    elif [ -f /etc/redhat-release ]; then
        yum install -y nftables
    else
        echo -e "${RED}[错误] 无法识别的操作系统，请手动安装 nftables。${NC}"
        exit 1
    fi
fi

# 3. 验证内核支持
# 尝试加载内核模块 (部分VPS可能需要，如果已经加载则忽略)
modprobe nf_tables 2>/dev/null

if ! nft list ruleset &> /dev/null; then
    echo -e "${RED}[错误] 你的系统内核似乎不支持 nftables，或者权限不足。${NC}"
    echo -e "       请确认这是一台 KVM/Xen 架构的 VPS (OpenVZ 可能不支持)。"
    exit 1
fi

# 4. 确定配置文件路径
# Debian/Ubuntu 通常在 /etc/nftables.conf
# CentOS/RHEL 通常在 /etc/sysconfig/nftables.conf
if [ -f /etc/debian_version ]; then
    CONF_PATH="/etc/nftables.conf"
elif [ -f /etc/redhat-release ]; then
    CONF_PATH="/etc/sysconfig/nftables.conf"
else
    # 默认回退路径
    CONF_PATH="/etc/nftables.conf"
fi

echo -e "${GREEN}[成功] 检测到 nftables 支持。配置文件路径: ${CONF_PATH}${NC}"

# 5. 备份原有配置
if [ -f "$CONF_PATH" ]; then
    cp "$CONF_PATH" "${CONF_PATH}.bak.$(date +%Y%m%d%H%M%S)"
    echo -e "${YELLOW}[提示] 已备份原有配置为 ${CONF_PATH}.bak...${NC}"
fi

# 6. 写入配置
cat > "$CONF_PATH" <<EOF
#!/usr/sbin/nft -f

flush ruleset

table inet security_firewall {
    # 动态黑名单 (封禁 60 分钟)
    set blackhole_v4 { type ipv4_addr; flags dynamic, timeout; timeout 60m; }
    set blackhole_v6 { type ipv6_addr; flags dynamic, timeout; timeout 60m; }

    chain input {
        # 默认策略: 允许所有 (白名单模式请改为 drop)
        type filter hook input priority 0; policy accept;

        # 1. 快速放行 (回环 + 已连接)
        iif "lo" accept
        ct state established,related accept

        # 2. 垃圾清理 (无效包 + 黑名单)
        ct state invalid drop
        ip saddr @blackhole_v4 drop
        ip6 saddr @blackhole_v6 drop

        # 3. SYN flood 防护 (阈值 500/s, 突发 200)
        # 保护系统内存，防止大规模 SYN 攻击导致死机
        tcp flags syn limit rate over 500/second burst 200 packets drop

        # 4. ICMP/Ping 限速 (阈值 50/s, 突发 50)
        ip protocol icmp limit rate over 50/second burst 50 packets drop
        meta l4proto icmpv6 limit rate over 50/second burst 50 packets drop

        # 5. SSH 防爆破 (5次/分, 允许瞬间突发5次)
        # 超过限制 -> 加入黑名单 -> 丢弃
        # 注意：请确保你的 SSH 端口是 22, 如果不是, 请修改下方的 dport
        tcp dport 22 ct state new meter flood_v4 { ip saddr timeout 60s limit rate over 5/minute burst 5 packets } \\
            add @blackhole_v4 { ip saddr } drop

        tcp dport 22 ct state new meter flood_v6 { ip6 saddr timeout 60s limit rate over 5/minute burst 5 packets } \\
            add @blackhole_v6 { ip6 saddr } drop
    }
}
EOF

# 7. 应用并启用服务
echo -e "${YELLOW}[信息] 正在应用规则...${NC}"
if nft -f "$CONF_PATH"; then
    echo -e "${GREEN}[成功] 规则语法正确并已加载！${NC}"
    
    # 设置开机自启
    systemctl enable nftables &> /dev/null
    systemctl restart nftables
    
    echo -e "${GREEN}[完成] nftables 服务已重启并设置开机自启。${NC}"
    echo -e "${GREEN}---------------------------------------------${NC}"
    echo -e "当前 SSH 防护状态："
    echo -e "  - IPv4/IPv6 双栈支持: ${GREEN}YES${NC}"
    echo -e "  - SSH 爆破阈值: ${GREEN}5次/分 (突发5次)${NC}"
    echo -e "  - 封禁时长: ${GREEN}60分钟${NC}"
    echo -e "  - SYN/ICMP 防护: ${GREEN}已开启${NC}"
    echo -e "${GREEN}---------------------------------------------${NC}"
else
    echo -e "${RED}[错误] 规则加载失败！请检查配置文件。已还原自动备份。${NC}"
    # 尝试还原
    LATEST_BACKUP=$(ls -t ${CONF_PATH}.bak.* 2>/dev/null | head -n1)
    if [ -n "$LATEST_BACKUP" ]; then
        cp "$LATEST_BACKUP" "$CONF_PATH"
        echo -e "${YELLOW}[信息] 已还原配置文件。${NC}"
    fi
    exit 1
fi