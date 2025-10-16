#!/bin/bash
# tcp调优脚本 v25.10.11
# 用法:
#   ./tcp.sh 1   启用调优
#   ./tcp.sh 0   还原配置
#   ./tcp.sh 2   对比优化前后的参数

BACKUP_FILE="/var/backups/tcp_backup_adaptive.conf"
TUNE_FILE="/etc/sysctl.d/tcp_bbr_adaptive.conf"

# 检查是否以 root 权限运行
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "✗ 错误: 此脚本需要 root 权限运行"
        echo "  请使用: sudo $0"
        exit 1
    fi
}

# 确保备份目录存在
ensure_backup_dir() {
    local backup_dir
    backup_dir=$(dirname "$BACKUP_FILE")
    if [ ! -d "$backup_dir" ]; then
        mkdir -p "$backup_dir" 2>/dev/null || {
            echo "✗ 无法创建备份目录: $backup_dir"
            exit 1
        }
    fi
}

PARAMS=(
    "net.core.default_qdisc"
    "net.ipv4.tcp_congestion_control"
    "net.core.rmem_max"
    "net.core.wmem_max"
    "net.ipv4.tcp_rmem"
    "net.ipv4.tcp_wmem"
)

get_sys_info() {
    MEM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    MEM_BYTES=$((MEM_KB * 1024))
    echo "内存: $((MEM_BYTES/1024/1024)) MB, CPU: $(nproc) 核"
}

ask_network_info() {
    # 读取并验证带宽输入
    while true; do
        read -p "最大带宽 (Mbps): " BW
        if [[ "$BW" =~ ^[0-9]+(\.[0-9]+)?$ ]] && (( $(echo "$BW > 0" | bc -l) )); then
            break
        else
            echo "✗ 无效输入，请输入正数 (例如: 100 或 1000)"
        fi
    done
    
    # 读取并验证 RTT 输入
    while true; do
        read -p "平均延迟 RTT (ms): " RTT
        if [[ "$RTT" =~ ^[0-9]+(\.[0-9]+)?$ ]] && (( $(echo "$RTT > 0" | bc -l) )); then
            break
        else
            echo "✗ 无效输入，请输入正数 (例如: 10 或 50)"
        fi
    done
    
    BW_BITS=$((BW * 1000000))
    RTT_SEC=$(awk "BEGIN {print $RTT/1000}")
    BDP_BITS=$(awk "BEGIN {print $BW_BITS * $RTT_SEC}")
    BDP_BYTES=$(awk "BEGIN {print int($BDP_BITS/8)}")
    MIN_BUF=$((4*1024*1024))
    MAX_BUF_LIMIT=$((MEM_BYTES/8))
    if [ $BDP_BYTES -lt $MIN_BUF ]; then
        BUF=$MIN_BUF
    elif [ $BDP_BYTES -gt $MAX_BUF_LIMIT ]; then
        BUF=$MAX_BUF_LIMIT
    else
        BUF=$BDP_BYTES
    fi
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "计算结果:"
    echo "  带宽延迟积 (BDP): $(numfmt --to=iec-i --suffix=B $BDP_BYTES)"
    echo "  缓冲区上限: $(numfmt --to=iec-i --suffix=B $BUF)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

check_bbr() {
    if ! sysctl net.ipv4.tcp_available_congestion_control 2>/dev/null | grep -qw bbr; then
        echo "⚠️ 未检测到 BBR 支持，尝试加载 tcp_bbr 模块..."
        if modprobe tcp_bbr 2>/dev/null; then
            echo "✓ tcp_bbr 模块加载成功"
            # 添加到开机自动加载
            if [ ! -f /etc/modules-load.d/tcp_bbr.conf ]; then
                echo "tcp_bbr" > /etc/modules-load.d/tcp_bbr.conf
                echo "✓ 已设置 BBR 模块开机自动加载"
            fi
        else
            echo "✗ 内核不支持 BBR，无法加载模块"
            echo "  请确认内核版本 >= 4.9 或更新内核"
            exit 1
        fi
    else
        echo "✓ BBR 支持已启用"
    fi
}

apply_tune() {
    check_root
    ensure_backup_dir
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "         系统信息检测"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    get_sys_info
    echo ""
    check_bbr
    echo ""
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "         网络参数配置"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    ask_network_info
    echo ""
    
    if [ ! -f "$BACKUP_FILE" ]; then
        echo "📋 备份当前参数到 $BACKUP_FILE"
        for p in "${PARAMS[@]}"; do
            echo "$p = $(sysctl -n $p)" >> "$BACKUP_FILE"
        done
        echo "✓ 备份完成"
    else
        echo "ℹ️  检测到已存在备份文件，跳过备份"
    fi
    
    echo ""
    echo "📝 生成配置文件: $TUNE_FILE"
    cat > "$TUNE_FILE" <<EOF
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.core.rmem_max = $BUF
net.core.wmem_max = $BUF
net.ipv4.tcp_rmem = 4096 87380 $BUF
net.ipv4.tcp_wmem = 4096 65536 $BUF
EOF
    
    echo "⚙️  应用配置..."
    if sysctl -p "$TUNE_FILE" >/dev/null 2>&1; then
        echo "✓ 配置应用成功"
    else
        echo "✗ 配置应用失败"
        exit 1
    fi
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "         当前参数"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    for p in "${PARAMS[@]}"; do
        printf "%-35s %s\n" "$p" "$(sysctl -n $p)"
    done
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

restore_tune() {
    check_root
    
    if [ ! -f "$BACKUP_FILE" ]; then
        echo "✗ 未找到备份文件: $BACKUP_FILE"
        echo "  无法还原配置"
        exit 1
    fi
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "         还原配置"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    [ -f "$TUNE_FILE" ] && rm -f "$TUNE_FILE" && echo "✓ 已删除调优配置文件"
    
    echo "⚙️  还原系统参数..."
    while IFS= read -r line; do
        key=$(echo "$line" | awk -F= '{print $1}' | xargs)
        value=$(echo "$line" | awk -F= '{print $2}' | xargs)
        if [ -n "$key" ] && [ -n "$value" ]; then
            if sysctl -w "$key=$value" >/dev/null 2>&1; then
                echo "  ✓ $key"
            else
                echo "  ✗ $key (失败)"
            fi
        fi
    done < "$BACKUP_FILE"
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "         当前参数"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    for p in "${PARAMS[@]}"; do
        printf "%-35s %s\n" "$p" "$(sysctl -n $p)"
    done
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    read -p "是否删除备份文件? (y/N): " del_backup
    if [[ "$del_backup" =~ ^[Yy]$ ]]; then
        rm -f "$BACKUP_FILE"
        echo "✓ 已删除备份文件"
    else
        echo "ℹ️  保留备份文件: $BACKUP_FILE"
    fi
}

compare_params() {
    if [ ! -f "$BACKUP_FILE" ]; then
        echo "✗ 未找到备份文件: $BACKUP_FILE"
        echo "  无法对比参数"
        exit 1
    fi
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    printf "%-35s %-25s %-25s\n" "参数" "优化前" "优化后"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    for p in "${PARAMS[@]}"; do
        old=$(grep "^$p" "$BACKUP_FILE" | awk -F= '{print $2}' | xargs)
        new=$(sysctl -n $p 2>/dev/null || echo "N/A")
        printf "%-35s %-25s %-25s\n" "$p" "$old" "$new"
    done
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

if [ -z "$1" ]; then
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "       TCP 调优脚本 v25.10.11"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "请选择操作："
    echo "  1 - 启用 BBR 调优"
    echo "  0 - 还原默认配置"
    echo "  2 - 对比优化前后参数"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    read -p "请输入选项 (1/0/2): " choice
    case "$choice" in
        1) apply_tune ;;
        0) restore_tune ;;
        2) compare_params ;;
        *) echo "✗ 无效选项" ; exit 1 ;;
    esac
else
    case "$1" in
        1) apply_tune ;;
        0) restore_tune ;;
        2) compare_params ;;
        *) echo "用法: $0 {1|0|2} 
    1 = 启用调优 
    0 = 还原配置 
    2 = 对比优化前后的参数" ; exit 1 ;;
    esac
fi
