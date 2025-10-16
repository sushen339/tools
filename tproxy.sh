#!/bin/sh

# TPROXY 透明代理脚本 for OpenWrt with NFTables
# 功能: IPv4/v6, DNS劫持(可选), IP分流, 本机代理
# 版本: 1.1.2 (2025-06-16)
# 维护: su

# --- [ 用户配置区: 请根据您的环境修改此区域 ] ---

# --- 功能开关 ---
# 是否开启DNS劫持功能. "true":开启, "false":关闭
ENABLE_DNS_HIJACKING="false"

# --- 核心设置 ---
# TPROXY 代理服务监听的 TCP/UDP 端口
PROXY_PORT=7893
# Adguard 或其他 DNS 软件的监听端口
ADGUARDHOME_DNS_PORT=553
# 代理软件的 DNS 监听端口 (仅在开启劫持时有效)
PROXY_DNS_PORT=1053

# --- 系统集成设置 ---
# LAN 接口名称
LAN_IF="br-lan"
# 运行代理软件的用户名 (用于豁免代理自身流量，防止死循环)
PROXY_USER="root"
# 存放 .nft 自定义规则文件的目录
NFT_CUSTOM_PATH="/etc/nikki/nftables"
# 您正在使用的 nftables 表名
NFT_TABLE="nikki"

# --- IP 集合名称 (需与 .nft 文件中定义的名称完全一致) ---
NFT_SET_RESERVED_V4="reserved_ip"
NFT_SET_RESERVED_V6="reserved_ip6"
NFT_SET_BYPASS_V4="china_ip"
NFT_SET_BYPASS_V6="china_ip6"

# --- 高级设置 ---
# 防火墙标记 (fwmark) 和策略路由表 ID
PROXY_MARK=0xff
ROUTE_TABLE=100

# 锁文件路径 (防止重复运行)
LOCK_FILE="/var/run/tproxy.lock"


# --- [ 核心逻辑区: 通常无需修改 ] ---

check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        printf "错误: 此脚本需要以 root 权限运行。\n" >&2
        exit 1
    fi
}

# 检查是否已有实例运行
check_lock() {
    if [ -f "$LOCK_FILE" ]; then
        # 检查服务是否真正在运行（通过防火墙表存在性判断）
        if nft list table inet "$NFT_TABLE" >/dev/null 2>&1; then
            printf "错误: TPROXY 服务已在运行中\n" >&2
            printf "如需重新启动，请使用: %s restart\n" "$0" >&2
            printf "如需强制启动，请先停止服务: %s stop\n" "$0" >&2
            exit 1
        else
            # 清理失效的锁文件
            printf "  -> 清理失效的锁文件...\n"
            rm -f "$LOCK_FILE"
        fi
    fi
}

# 创建锁文件
create_lock() {
    # 确保锁文件目录存在
    local lock_dir=$(dirname "$LOCK_FILE")
    [ ! -d "$lock_dir" ] && mkdir -p "$lock_dir" 2>/dev/null
    
    # 写入启动时间戳而不是PID，因为脚本执行完后进程会结束
    date '+%Y-%m-%d %H:%M:%S' > "$LOCK_FILE"
    if [ $? -ne 0 ]; then
        printf "警告: 无法创建锁文件 %s\n" "$LOCK_FILE" >&2
    else
        printf "  -> 锁文件已创建: %s\n" "$LOCK_FILE"
    fi
}

# 清理锁文件
remove_lock() {
    if [ -f "$LOCK_FILE" ]; then
        rm -f "$LOCK_FILE"
        printf "  -> 锁文件已清理: %s\n" "$LOCK_FILE"
    fi
}

load_user_nft_files() {
    if [ ! -d "$NFT_CUSTOM_PATH" ]; then
        printf "错误: 找不到目录 %s\n" "$NFT_CUSTOM_PATH" >&2
        exit 1
    fi
    printf "  -> 正在从 %s 加载自定义规则...\n" "$NFT_CUSTOM_PATH"
    
    # 检查是否存在 .nft 文件
    file_count=$(find "$NFT_CUSTOM_PATH" -name "*.nft" -type f | wc -l)
    if [ "$file_count" -eq 0 ]; then
        printf "警告: 目录 %s 中没有找到 .nft 文件\n" "$NFT_CUSTOM_PATH" >&2
        return 0
    fi
    
    for file in "$NFT_CUSTOM_PATH"/*.nft; do
        if [ -f "$file" ]; then
            printf "     - 加载 %s\n" "$(basename "$file")"
            if ! nft -f "$file"; then
                printf "错误: 加载 %s 时发生错误！\n" "$file" >&2
                exit 1
            fi
        fi
    done
}

do_start() {
    printf "▶️  启动透明代理服务...\n"
    check_lock
    
    # 先清理可能存在的残留规则，但不删除锁文件
    printf "  -> 清理可能存在的残留规则...\n"
    ip -4 rule del fwmark $PROXY_MARK lookup $ROUTE_TABLE 2>/dev/null || true
    ip -6 rule del fwmark $PROXY_MARK lookup $ROUTE_TABLE 2>/dev/null || true
    ip -4 route flush table $ROUTE_TABLE 2>/dev/null
    ip -6 route flush table $ROUTE_TABLE 2>/dev/null
    nft delete table inet $NFT_TABLE 2>/dev/null || true
    
    # 创建锁文件
    create_lock
    
    # 设置异常退出时自动清理锁文件
    trap 'remove_lock; exit' INT TERM

    # 1. 设置策略路由
    printf "  -> 正在设置策略路由...\n"
    ip -4 rule add fwmark $PROXY_MARK lookup $ROUTE_TABLE
    ip -6 rule add fwmark $PROXY_MARK lookup $ROUTE_TABLE
    ip -4 route add local default dev lo table $ROUTE_TABLE
    ip -6 route add local default dev lo table $ROUTE_TABLE

    # 2. 加载并配置 nftables
    printf "  -> 正在加载并配置 nftables...\n"

    nft add table inet $NFT_TABLE
    if [ $? -ne 0 ]; then
        printf "错误: 创建 nftables 表 '%s' 失败。请检查是否已有同名表或nftables服务是否正常。\n" "$NFT_TABLE" >&2
        exit 1
    fi

    # 加载 IP Set 文件
    load_user_nft_files

    nft add chain inet $NFT_TABLE mangle_prerouting { type filter hook prerouting priority -150\; }; nft flush chain inet $NFT_TABLE mangle_prerouting
    nft add chain inet $NFT_TABLE mangle_output { type route hook output priority -150\; }; nft flush chain inet $NFT_TABLE mangle_output
    for chain in tproxy_lan_v4 tproxy_lan_v6 tproxy_loc_v4 tproxy_loc_v6; do
        nft add chain inet $NFT_TABLE "$chain"; nft flush chain inet $NFT_TABLE "$chain"
    done

    # 3. 应用规则
    printf "  -> 正在应用核心防火墙规则...\n"
    # 规则 A: DNS 劫持 (可选)
    if [ "$ENABLE_DNS_HIJACKING" = "true" ]; then
        printf "     - DNS 劫持已开启。\n"
        nft add chain inet $NFT_TABLE dns_redirect { type nat hook prerouting priority -100\; }; nft flush chain inet $NFT_TABLE dns_redirect
        nft add rule inet $NFT_TABLE dns_redirect iifname $LAN_IF meta l4proto {tcp, udp} th dport 53 redirect to :$PROXY_DNS_PORT
    else
        printf "     - DNS 劫持已关闭。\n"
    fi

    # 规则 B: 处理本机发出流量 (在 OUTPUT 链中仅作标记)
    nft add rule inet $NFT_TABLE mangle_output meta nfproto ipv4 jump tproxy_loc_v4
    nft add rule inet $NFT_TABLE mangle_output meta nfproto ipv6 jump tproxy_loc_v6
    nft add rule inet $NFT_TABLE tproxy_loc_v4 skuid $PROXY_USER return # 关键: 豁免代理程序自身，防止死循环
    nft add rule inet $NFT_TABLE tproxy_loc_v4 ip daddr @$NFT_SET_RESERVED_V4 return
    nft add rule inet $NFT_TABLE tproxy_loc_v4 ip daddr @$NFT_SET_BYPASS_V4 return
    # 不处理 DNS 流量
    nft add rule inet $NFT_TABLE tproxy_loc_v4 meta l4proto {tcp, udp} th dport {53, $ADGUARDHOME_DNS_PORT, $PROXY_DNS_PORT} return
    nft add rule inet $NFT_TABLE tproxy_loc_v4 meta l4proto {tcp, udp} meta mark set $PROXY_MARK
    nft add rule inet $NFT_TABLE tproxy_loc_v6 skuid $PROXY_USER return
    nft add rule inet $NFT_TABLE tproxy_loc_v6 ip6 daddr @$NFT_SET_RESERVED_V6 return
    nft add rule inet $NFT_TABLE tproxy_loc_v6 ip6 daddr @$NFT_SET_BYPASS_V6 return
    # 不处理 DNS 流量
    nft add rule inet $NFT_TABLE tproxy_loc_v6 meta l4proto {tcp, udp} th dport {53, $ADGUARDHOME_DNS_PORT, $PROXY_DNS_PORT} return
    nft add rule inet $NFT_TABLE tproxy_loc_v6 meta l4proto {tcp, udp} meta mark set $PROXY_MARK

    # 规则 C: 处理局域网及本机回环流量 (在 PREROUTING 链中执行 TPROXY)
    nft add rule inet $NFT_TABLE mangle_prerouting iifname $LAN_IF meta nfproto ipv4 meta l4proto {tcp, udp} jump tproxy_lan_v4
    nft add rule inet $NFT_TABLE mangle_prerouting iifname $LAN_IF meta nfproto ipv6 meta l4proto {tcp, udp} jump tproxy_lan_v6
    nft add rule inet $NFT_TABLE mangle_prerouting iifname "lo" meta nfproto ipv4 meta l4proto {tcp, udp} meta mark $PROXY_MARK jump tproxy_lan_v4
    nft add rule inet $NFT_TABLE mangle_prerouting iifname "lo" meta nfproto ipv6 meta l4proto {tcp, udp} meta mark $PROXY_MARK jump tproxy_lan_v6
    
    nft add rule inet $NFT_TABLE tproxy_lan_v4 ip daddr @$NFT_SET_RESERVED_V4 return
    nft add rule inet $NFT_TABLE tproxy_lan_v4 ip daddr @$NFT_SET_BYPASS_V4 return
    # 不处理 DNS 流量
    nft add rule inet $NFT_TABLE tproxy_lan_v4 meta l4proto {tcp, udp} th dport {53, $ADGUARDHOME_DNS_PORT, $PROXY_DNS_PORT} return
    nft add rule inet $NFT_TABLE tproxy_lan_v4 meta l4proto {tcp, udp} meta mark set $PROXY_MARK tproxy to :$PROXY_PORT
    nft add rule inet $NFT_TABLE tproxy_lan_v6 ip6 daddr @$NFT_SET_RESERVED_V6 return
    nft add rule inet $NFT_TABLE tproxy_lan_v6 ip6 daddr @$NFT_SET_BYPASS_V6 return
    # 不处理 DNS 流量
    nft add rule inet $NFT_TABLE tproxy_lan_v6 meta l4proto {tcp, udp} th dport {53, $ADGUARDHOME_DNS_PORT, $PROXY_DNS_PORT} return
    nft add rule inet $NFT_TABLE tproxy_lan_v6 meta l4proto {tcp, udp} meta mark set $PROXY_MARK tproxy to :$PROXY_PORT

    printf "✅ 透明代理服务已成功启动。\n"
    
    # 清除陷阱，正常启动时保持锁文件
    trap - INT TERM
}

do_stop() {
    printf "⏹️  停止透明代理服务...\n"
    
    # 清理策略路由
    ip -4 rule del fwmark $PROXY_MARK lookup $ROUTE_TABLE 2>/dev/null || true
    ip -6 rule del fwmark $PROXY_MARK lookup $ROUTE_TABLE 2>/dev/null || true
    # 清理自定义路由表内容
    ip -4 route flush table $ROUTE_TABLE 2>/dev/null
    ip -6 route flush table $ROUTE_TABLE 2>/dev/null
    # 删除 nft 路由表
    printf "  -> 正在清理防火墙表 '%s'...\n" "$NFT_TABLE"
    nft delete table inet $NFT_TABLE 2>/dev/null || true
    
    # 清理锁文件
    remove_lock
    
    printf "🛑 透明代理服务已完全停止。\n"
}

do_status() {
    ICON_OK="✅"
    ICON_FAIL="❌"
    ICON_INFO="ℹ️"
    ICON_OFF="⚪️"

    printf "--- TPROXY 服务状态检查 ---\n"

    # 检查锁文件状态
    if [ -f "$LOCK_FILE" ]; then
        local start_time=$(cat "$LOCK_FILE" 2>/dev/null)
        if [ -n "$start_time" ]; then
            printf "锁文件状态: %s 存在 (启动时间: %s)\n" "$ICON_OK" "$start_time"
        else
            printf "锁文件状态: %s 存在但无效\n" "$ICON_FAIL"
        fi
    else
        printf "锁文件状态: %s 不存在\n" "$ICON_OFF"
    fi

    if ! nft list table inet "$NFT_TABLE" >/dev/null 2>&1; then
        printf "总状态: %s 未激活 (找不到防火墙表 '%s')\n" "$ICON_OFF" "$NFT_TABLE"
        exit 0
    fi

    if ip rule show | grep -q "fwmark $PROXY_MARK lookup $ROUTE_TABLE"; then
        printf "总状态: %s 激活\n" "$ICON_OK"
    else
        printf "总状态: %s 部分激活 (防火墙规则存在，但策略路由缺失)\n" "$ICON_FAIL"
    fi

    printf "\n[+] IP 路由与规则:\n"
    if ip rule show | grep -q "fwmark $PROXY_MARK"; then
        printf "  %s 策略路由:\n" "$ICON_INFO"
        ip rule show | grep "fwmark $PROXY_MARK" | sed 's/^/    -> /'
    else
        printf "  %s 策略路由: %s 缺失!\n" "$ICON_FAIL" "$ICON_FAIL"
    fi
    printf "  %s 自定义路由表 (ID: %s):\n" "$ICON_INFO" "$ROUTE_TABLE"
    ip route show table "$ROUTE_TABLE" | sed 's/^/    -> /'

    printf "\n[+] NFTables 规则状态 (主表: %s)\n" "$NFT_TABLE"

    if [ "$ENABLE_DNS_HIJACKING" = "true" ]; then
        if nft list chain inet "$NFT_TABLE" "dns_redirect" >/dev/null 2>&1; then
            printf "  %s DNS 劫持: 已激活 (转发至端口 %s)\n" "$ICON_OK" "$PROXY_DNS_PORT"
        else
            printf "  %s DNS 劫持: 激活失败\n" "$ICON_FAIL"
        fi
    else
        printf "  %s DNS 劫持: 已禁用\n" "$ICON_OFF"
    fi

    if nft list chain inet "$NFT_TABLE" "tproxy_lan_v4" >/dev/null 2>&1; then
        printf "  %s TPROXY 代理: 已激活 (监听端口 %s)\n" "$ICON_OK" "$PROXY_PORT"
    else
        printf "  %s TPROXY 代理: 激活失败\n" "$ICON_FAIL"
    fi

    printf "  %s IP 列表加载状态:\n" "$ICON_INFO"
    if nft list set inet "$NFT_TABLE" "$NFT_SET_RESERVED_V4" >/dev/null 2>&1; then
        printf "    - %s: %s\n" "$NFT_SET_RESERVED_V4" "$ICON_OK 本地 IPv4 已直连"
    else
        printf "    - %s: %s\n" "$NFT_SET_RESERVED_V4" "$ICON_FAIL 未加载"
    fi
    if nft list set inet "$NFT_TABLE" "$NFT_SET_RESERVED_V6" >/dev/null 2>&1; then
        printf "    - %s: %s\n" "$NFT_SET_RESERVED_V6" "$ICON_OK 本地 IPv6 已直连"
    else
        printf "    - %s: %s\n" "$NFT_SET_RESERVED_V6" "$ICON_FAIL 未加载"
    fi
    if nft list set inet "$NFT_TABLE" "$NFT_SET_BYPASS_V4" >/dev/null 2>&1; then
        printf "    - %s: %s\n" "$NFT_SET_BYPASS_V4" "$ICON_OK 国内 IPv4 已直连"
    else
        printf "    - %s: %s\n" "$NFT_SET_BYPASS_V4" "$ICON_FAIL 未加载"
    fi
    if nft list set inet "$NFT_TABLE" "$NFT_SET_BYPASS_V6" >/dev/null 2>&1; then
        printf "    - %s: %s\n" "$NFT_SET_BYPASS_V6" "$ICON_OK 国内 IPv6 已直连"
    else
        printf "    - %s: %s\n" "$NFT_SET_BYPASS_V6" "$ICON_FAIL 未加载"
    fi

    printf -- "--------------------------------\n"
}

# --- 脚本主入口 ---
check_root

case "$1" in
    start)
        do_start
        ;;
    stop)
        do_stop
        ;;
    restart)
        printf "🔄 重启透明代理服务...\n"
        do_stop
        sleep 1
        do_start
        ;;
    status)
        do_status
        ;;
    *)
        printf "用法: %s {start|stop|restart|status}\n" "$0"
        printf "  start   - 启动透明代理服务\n"
        printf "  stop    - 停止透明代理服务\n"
        printf "  restart - 重启透明代理服务\n"
        printf "  status  - 查看服务状态\n"
        exit 1
        ;;
esac

exit 0
