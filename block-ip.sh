#!/bin/sh

# ================= 配置区域 =================
LOG_FILE="/var/log/block-ip.log"
MAX_LOG_SIZE=10485760  # 10MB (单位:字节)
MAX_RETRIES=3
BAN_TIME="24h"

RECORD_DIR="/tmp/block_ip_counts"
PERSIST_FILE="/etc/block-ip.list"
WHITELIST_FILE="/etc/block-ip.whitelist"
INSTALL_PATH="/usr/local/bin/block-ip"
NFT_TABLE="inet filter"
NFT_SET="blacklist"
NFT_SET_V6="blacklist_v6"
NFT_WHITELIST="whitelist"
NFT_WHITELIST_V6="whitelist_v6"

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
# ===========================================

# --- 颜色 ---
C_RESET="\033[0m"
C_GREEN="\033[32m"
C_CYAN="\033[36m"
C_YELLOW="\033[33m"
C_RED="\033[31m"

msg() { printf "%b%s%b\n" "$1" "$2" "$C_RESET"; }
log() {
    rotate_log
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}
check_root() { [ "$(id -u)" -ne 0 ] && msg "$C_RED" "❌ 需 root 权限" && exit 1; }

get_country_name() {
    case "$1" in
        CN) echo "中国" ;;
        US) echo "美国" ;;
        RU) echo "俄罗斯" ;;
        NL) echo "荷兰" ;;
        DE) echo "德国" ;;
        GB) echo "英国" ;;
        FR) echo "法国" ;;
        JP) echo "日本" ;;
        KR) echo "韩国" ;;
        SG) echo "新加坡" ;;
        HK) echo "香港" ;;
        TW) echo "台湾" ;;
        IN) echo "印度" ;;
        BR) echo "巴西" ;;
        CA) echo "加拿大" ;;
        AU) echo "澳大利亚" ;;
        IT) echo "意大利" ;;
        ES) echo "西班牙" ;;
        SE) echo "瑞典" ;;
        PL) echo "波兰" ;;
        UA) echo "乌克兰" ;;
        TR) echo "土耳其" ;;
        ID) echo "印度尼西亚" ;;
        TH) echo "泰国" ;;
        VN) echo "越南" ;;
        MX) echo "墨西哥" ;;
        AR) echo "阿根廷" ;;
        CL) echo "智利" ;;
        RO) echo "罗马尼亚" ;;
        CZ) echo "捷克" ;;
        *) echo "$1" ;;
    esac
}

rotate_log() {
    [ ! -f "$LOG_FILE" ] && return
    LOG_SIZE=$(stat -f%z "$LOG_FILE" 2>/dev/null || stat -c%s "$LOG_FILE" 2>/dev/null || echo 0)
    if [ "$LOG_SIZE" -ge "$MAX_LOG_SIZE" ]; then
        [ -f "${LOG_FILE}.1" ] && rm -f "${LOG_FILE}.1"
        mv "$LOG_FILE" "${LOG_FILE}.1"
        touch "$LOG_FILE" && chmod 666 "$LOG_FILE"
    fi
}

is_ipv6() {
    # 移除CIDR后缀再判断
    IP="${1%%/*}"
    echo "$IP" | grep -q ':'
}

get_ip() {
    if [ -n "$PAM_RHOST" ]; then echo "$PAM_RHOST"
    elif [ -n "$RHOST" ]; then echo "$RHOST"
    else echo ""; fi
}

check_and_install_env() {
    if ! command -v nft >/dev/null 2>&1; then
        . /etc/os-release
        case "$ID" in
            debian|ubuntu|kali) apt-get update && apt-get install -y nftables ;;
            centos|rhel|alma) dnf install -y nftables || yum install -y nftables ;;
            alpine) apk add nftables ;;
            *) return 1 ;;
        esac
    fi
    nft list tables >/dev/null 2>&1 || modprobe nf_tables >/dev/null 2>&1
    [ -x "$(command -v systemctl)" ] && systemctl enable --now nftables >/dev/null 2>&1
    return 0
}

# --- 封禁 ---
ban_ip() {
    TARGET_IP="$1"
    SAVE_DISK="$2"
    
    # 标准化IP格式：单IP自动添加/32或/128
    case "$TARGET_IP" in
        */*) ELEMENT="$TARGET_IP" ;;  # 已包含CIDR
        *:*) ELEMENT="$TARGET_IP/128" ;;  # IPv6单IP
        *) ELEMENT="$TARGET_IP/32" ;;  # IPv4单IP
    esac
    
    [ -n "$BAN_TIME" ] && ELEMENT="$ELEMENT timeout $BAN_TIME"
    
    # 根据IP类型选择不同的集合
    if is_ipv6 "$TARGET_IP"; then
        SET_NAME="$NFT_SET_V6"
    else
        SET_NAME="$NFT_SET"
    fi
    
    OUT=$(nft add element $NFT_TABLE $SET_NAME "{ $ELEMENT }" 2>&1)
    if echo "$OUT" | grep -q "No such file"; then
        init_nft_rules >/dev/null 2>&1
        nft add element $NFT_TABLE $SET_NAME "{ $ELEMENT }" >/dev/null 2>&1
    fi
    
    # 查询并记录国家信息（仅IPv4且不是CIDR）
    COUNTRY_CODE=""
    BASE_IP="${TARGET_IP%%/*}"
    if [ "$SAVE_DISK" -eq 1 ] && ! is_ipv6 "$BASE_IP" && ! echo "$TARGET_IP" | grep -q '/'; then
        if command -v curl >/dev/null 2>&1; then
            COUNTRY_CODE=$(curl -s --max-time 2 "https://ipinfo.io/$BASE_IP/country" 2>/dev/null | tr -d '\n\r ')
            [ -n "$COUNTRY_CODE" ] && [ ${#COUNTRY_CODE} -ne 2 ] && COUNTRY_CODE=""
        fi
    fi
    
    if [ "$SAVE_DISK" -eq 1 ]; then
        # 检查是否已存在（支持带国家代码的格式）
        if ! grep -qE "^$TARGET_IP(\||$)" "$PERSIST_FILE" 2>/dev/null; then
            if [ -n "$COUNTRY_CODE" ]; then
                echo "$TARGET_IP|$COUNTRY_CODE" >> "$PERSIST_FILE"
                COUNTRY_NAME=$(get_country_name "$COUNTRY_CODE")
                log "[执行封禁] IP=$TARGET_IP 国家=$COUNTRY_NAME 已封禁"
            else
                echo "$TARGET_IP" >> "$PERSIST_FILE"
                log "[执行封禁] IP=$TARGET_IP 已封禁"
            fi
        fi
    elif [ "$SAVE_DISK" -ne 2 ]; then
        log "[执行封禁] IP=$TARGET_IP 已封禁"
    fi
}

init_nft_rules() {
    nft add table $NFT_TABLE 2>/dev/null
    # 创建黑名单集合
    nft add set $NFT_TABLE $NFT_SET "{ type ipv4_addr; flags interval,timeout; }" 2>/dev/null
    nft add set $NFT_TABLE $NFT_SET_V6 "{ type ipv6_addr; flags interval,timeout; }" 2>/dev/null
    # 创建白名单集合（无超时）
    nft add set $NFT_TABLE $NFT_WHITELIST "{ type ipv4_addr; flags interval; }" 2>/dev/null
    nft add set $NFT_TABLE $NFT_WHITELIST_V6 "{ type ipv6_addr; flags interval; }" 2>/dev/null
    nft add chain $NFT_TABLE input "{ type filter hook input priority 0; }" 2>/dev/null
    # 白名单规则（优先级最高，先匹配先返回）
    nft list chain $NFT_TABLE input | grep -q "@$NFT_WHITELIST" || \
    nft insert rule $NFT_TABLE input ip saddr @"$NFT_WHITELIST" accept
    nft list chain $NFT_TABLE input | grep -q "@$NFT_WHITELIST_V6" || \
    nft insert rule $NFT_TABLE input ip6 saddr @"$NFT_WHITELIST_V6" accept
    # 黑名单规则
    nft list chain $NFT_TABLE input | grep -q "@$NFT_SET" || \
    nft insert rule $NFT_TABLE input ip saddr @"$NFT_SET" drop
    nft list chain $NFT_TABLE input | grep -q "@$NFT_SET_V6" || \
    nft insert rule $NFT_TABLE input ip6 saddr @"$NFT_SET_V6" drop
}

# --- 列表与统计 ---
do_list() {
    # 数据获取与清洗
    RAW_V4=$(nft list set $NFT_TABLE $NFT_SET 2>/dev/null)
    RAW_V6=$(nft list set $NFT_TABLE $NFT_SET_V6 2>/dev/null)
    RAW="$RAW_V4
$RAW_V6"
    
    CLEAN_DATA=$(echo "$RAW" | sed 's/,/\n/g' | sed 's/elements = {//g; s/}//g' | \
    awk '{
        for(i=1;i<=NF;i++) {
            if($i=="expires") {
                time=$(i+1); gsub("ms","",time)
                print $1, time
            }
        }
    }')
    
    IP_LIST=$(echo "$CLEAN_DATA" | awk '{print $1}')
    IP_V4_LIST=$(echo "$IP_LIST" | grep -v ':' || true)
    IP_V6_LIST=$(echo "$IP_LIST" | grep ':' || true)
    NFT_COUNT=0
    [ -n "$CLEAN_DATA" ] && NFT_COUNT=$(echo "$CLEAN_DATA" | awk 'NF>0' | wc -l)
    if [ -f "$PERSIST_FILE" ]; then LOCAL_COUNT=$(wc -l < "$PERSIST_FILE"); else LOCAL_COUNT=0; fi

    # 概览
    msg "$C_CYAN" "=== 🛡️  Block-IP 防护概览 ==="
    printf "当前生效: %b%s%b 条  |  本地记录: %b%s%b 条\n" "$C_GREEN" "$NFT_COUNT" "$C_RESET" "$C_YELLOW" "$LOCAL_COUNT" "$C_RESET"
    echo ""

    # 活跃列表（按剩余时间升序，显示最新封禁的5个）
    msg "$C_CYAN" "=== 🔥 活跃封禁列表 (最新 5 条) ==="
    if [ "$NFT_COUNT" -eq 0 ]; then
        echo "(目前没有被封禁的 IP)"
    else
        printf "%b%-45s %-15s%b\n" "$C_YELLOW" "IP 地址" "剩余时间" "$C_RESET"
        echo "--------------------------------------------------------------"
        echo "$CLEAN_DATA" | sort -t' ' -k2 | tail -n 5 | awk '{printf "%-45s %s\n", $1, $2}'
        [ "$NFT_COUNT" -gt 5 ] && echo "... (还有 $((NFT_COUNT - 5)) 条未显示)"
    fi
    echo ""

    # 智能IP段聚合统计
    msg "$C_CYAN" "=== 📊 攻击源聚合统计 (自动识别 IP 段) ==="
    
    if [ "$NFT_COUNT" -gt 0 ]; then
        V6_COUNT=0
        [ -n "$IP_V6_LIST" ] && V6_COUNT=$(echo "$IP_V6_LIST" | awk 'NF>0' | wc -l)
        HAS_OUTPUT=0

        # 收集聚合数据
        TEMP_AGG_FILE="/tmp/block_ip_agg_$$"
        : > "$TEMP_AGG_FILE"
        
        # 收集 /24 聚合
        echo "$IP_V4_LIST" | cut -d. -f1-3 | sort | uniq -c | awk '$1>=2 {split($2,a,"."); printf "%d|%s|24|%s\n", $1, $2, a[1]}' >> "$TEMP_AGG_FILE"
        # 收集 /16 聚合
        echo "$IP_V4_LIST" | cut -d. -f1-2 | sort | uniq -c | awk '$1>=2 {split($2,a,"."); printf "%d|%s|16|%s\n", $1, $2, a[1]}' >> "$TEMP_AGG_FILE"
        # 收集 /8 聚合
        echo "$IP_V4_LIST" | cut -d. -f1 | sort | uniq -c | awk '$1>=2 {printf "%d|%s|8|%s\n", $1, $2, $2}' >> "$TEMP_AGG_FILE"
        
        # 去重: 子段数量等于父段时隐藏父段
        TEMP_FILTER="/tmp/block_ip_filter_$$"
        : > "$TEMP_FILTER"
        
        while IFS='|' read -r count subnet mask a_seg; do
            [ -z "$count" ] && continue
            SKIP=0
            
            case "$mask" in
                8)
                    if grep -E "^$count\|$subnet\.[0-9]+(\.[0-9]+)?\|(16|24)\|" "$TEMP_AGG_FILE" >/dev/null 2>&1; then
                        SKIP=1
                    fi
                    ;;
                16)
                    if grep -E "^$count\|$subnet\.[0-9]+\|24\|" "$TEMP_AGG_FILE" >/dev/null 2>&1; then
                        SKIP=1
                    fi
                    ;;
            esac
            
            [ "$SKIP" -eq 0 ] && echo "$count|$subnet|$mask|$a_seg" >> "$TEMP_FILTER"
        done < "$TEMP_AGG_FILE"
        
        # 按数量降序,然后按A段分组,最后按掩码升序(同组内大段优先)
        SORTED_AGGS=$(sort -t'|' -k1,1rn -k4,4n -k3,3n "$TEMP_FILTER")
        rm -f "$TEMP_AGG_FILE" "$TEMP_FILTER"
        
        # 输出所有聚合并收集已统计的子网
        TEMP_SUBNETS="/tmp/block_ip_subnets_$$"
        : > "$TEMP_SUBNETS"
        
        if [ -n "$SORTED_AGGS" ]; then
            echo "$SORTED_AGGS" | while IFS='|' read -r count subnet mask _; do
                [ -z "$count" ] && continue
                
                # 输出该段
                case "$mask" in
                    8)  printf "  - %-18s %b(%s 个)%b\n" "${subnet}.0.0.0/8" "$C_RED" "$count" "$C_RESET" ;;
                    16) printf "  - %-18s %b(%s 个)%b\n" "${subnet}.0.0/16" "$C_RED" "$count" "$C_RESET" ;;
                    24) printf "  - %-18s %b(%s 个)%b\n" "${subnet}.0/24" "$C_RED" "$count" "$C_RESET" ;;
                esac
                
                echo "$subnet" >> "$TEMP_SUBNETS"
            done
            HAS_OUTPUT=1
        fi
        
        # 统计未被任何段包含的散乱IP
        REMAIN_LIST="$IP_V4_LIST"
        if [ -f "$TEMP_SUBNETS" ] && [ -s "$TEMP_SUBNETS" ]; then
            while IFS= read -r subnet; do
                [ -n "$subnet" ] && REMAIN_LIST=$(echo "$REMAIN_LIST" | grep -v "^$subnet\." || true)
            done < "$TEMP_SUBNETS"
        fi
        rm -f "$TEMP_SUBNETS"
        
        # 散乱IP统计
        REMAIN_COUNT=0
        if [ -n "$REMAIN_LIST" ]; then
            REMAIN_COUNT=$(echo "$REMAIN_LIST" | awk 'NF>0' | wc -l)
        fi
        
        if [ "$HAS_OUTPUT" -eq 1 ]; then
            [ "$REMAIN_COUNT" -gt 0 ] && echo "  - (其他散乱分布 IPv4)  ($REMAIN_COUNT 个)"
        else
            echo "(无数据)"
        fi
        
        # IPv6统计
        if [ "$V6_COUNT" -gt 0 ]; then
            echo "  - (IPv6 地址)          ($V6_COUNT 个)"
        fi
    else
        echo "(无数据)"
    fi

    echo ""
    
    # 国家统计
    msg "$C_CYAN" "=== 🌍 攻击源国家/地区统计 ==="
    
    if [ -f "$COUNTRY_FILE" ] && [ -s "$COUNTRY_FILE" ]; then
        # 直接统计country文件中的国家代码
        cut -d'|' -f2 "$COUNTRY_FILE" | sort | uniq -c | sort -rn | while read -r count code; do
            [ -n "$count" ] && [ -n "$code" ] && {
                COUNTRY_NAME=$(get_country_name "$code")
                printf "  - %-15s %b(%s 个)%b\n" "$COUNTRY_NAME" "$C_RED" "$count" "$C_RESET"
            }
        done
    else
        echo "(暂无国家信息)"
    fi

    echo ""
    
    # 最新日志
    msg "$C_CYAN" "=== 📝 最新拦截日志 (Last 10) ==="
    if [ -f "$LOG_FILE" ]; then tail -n 10 "$LOG_FILE"; else echo "(暂无日志)"; fi
}

do_show() {
    msg "$C_CYAN" "=== 📋 本地持久化封禁列表 ==="
    
    if [ ! -f "$PERSIST_FILE" ] || [ ! -s "$PERSIST_FILE" ]; then
        echo "(暂无持久化记录)"
        return
    fi
    
    TOTAL=$(wc -l < "$PERSIST_FILE")
    IPV4_COUNT=$(grep -c -v ':' "$PERSIST_FILE" 2>/dev/null || echo 0)
    IPV6_COUNT=$(grep -c ':' "$PERSIST_FILE" 2>/dev/null || echo 0)
    
    printf "总计: %b%s%b 条  |  IPv4: %b%s%b 条  |  IPv6: %b%s%b 条\n\n" \
        "$C_GREEN" "$TOTAL" "$C_RESET" \
        "$C_CYAN" "$IPV4_COUNT" "$C_RESET" \
        "$C_YELLOW" "$IPV6_COUNT" "$C_RESET"
    
    printf "%b%-45s%b\n" "$C_YELLOW" "IP 地址" "$C_RESET"
    echo "---------------------------------------------"
    
    awk -F'|' '{printf "%-45s\n", $1}' "$PERSIST_FILE"
    echo ""
    
    msg "$C_CYAN" "📌 文件位置: $PERSIST_FILE"
}

do_vip_add() {
    INPUT="$1"
    # 验证输入格式
    case "$INPUT" in
        */*)  # CIDR格式
            IP="${INPUT%%/*}"
            MASK="${INPUT##*/}"
            if ! echo "$MASK" | grep -qE '^[0-9]+$'; then
                msg "$C_RED" "❌ 无效的CIDR格式: $INPUT"
                exit 1
            fi
            ;;
        *:*|*.*.*.*)  # IPv6或IPv4单IP
            ;;
        *)
            msg "$C_RED" "❌ 无效的IP格式: $INPUT"
            exit 1
            ;;
    esac
    
    # 标准化格式
    case "$INPUT" in
        */*) ELEMENT="$INPUT" ;;  # 已包含CIDR
        *:*) ELEMENT="$INPUT/128" ;;  # IPv6单IP
        *) ELEMENT="$INPUT/32" ;;  # IPv4单IP
    esac
    
    # 添加到nftables白名单
    if is_ipv6 "$INPUT"; then
        SET_NAME="$NFT_WHITELIST_V6"
    else
        SET_NAME="$NFT_WHITELIST"
    fi
    
    OUT=$(nft add element $NFT_TABLE $SET_NAME "{ $ELEMENT }" 2>&1)
    if echo "$OUT" | grep -q "No such file"; then
        init_nft_rules >/dev/null 2>&1
        nft add element $NFT_TABLE $SET_NAME "{ $ELEMENT }" >/dev/null 2>&1
    fi
    
    # 保存到持久化文件
    if ! grep -q "^$INPUT$" "$WHITELIST_FILE" 2>/dev/null; then
        echo "$INPUT" >> "$WHITELIST_FILE"
    fi
    
    log "[白名单添加] IP=$INPUT"
    msg "$C_GREEN" "✅ 已添加到白名单: $INPUT"
}

do_vip_del() {
    INPUT="$1"
    
    # 标准化格式
    case "$INPUT" in
        */*) DEL_ELEMENT="$INPUT" ;;  # 已包含CIDR
        *:*) DEL_ELEMENT="$INPUT/128" ;;  # IPv6单IP
        *) DEL_ELEMENT="$INPUT/32" ;;  # IPv4单IP
    esac
    
    # 从nftables删除
    if is_ipv6 "$INPUT"; then
        nft delete element $NFT_TABLE $NFT_WHITELIST_V6 "{ $DEL_ELEMENT }" >/dev/null 2>&1
    else
        nft delete element $NFT_TABLE $NFT_WHITELIST "{ $DEL_ELEMENT }" >/dev/null 2>&1
    fi
    
    # 从持久化文件删除
    if [ -f "$WHITELIST_FILE" ]; then
        ESCAPED=$(echo "$INPUT" | sed 's/[.[\/]/\\&/g')
        sed -i "/^$ESCAPED$/d" "$WHITELIST_FILE"
    fi
    
    log "[白名单移除] IP=$INPUT"
    msg "$C_GREEN" "✅ 已从白名单移除: $INPUT"
}

do_vip_list() {
    msg "$C_CYAN" "=== 📋 VIP 白名单列表 ==="
    
    if [ ! -f "$WHITELIST_FILE" ] || [ ! -s "$WHITELIST_FILE" ]; then
        echo "(暂无白名单记录)"
        return
    fi
    
    TOTAL=$(wc -l < "$WHITELIST_FILE")
    IPV4_COUNT=$(grep -c -v ':' "$WHITELIST_FILE" 2>/dev/null || echo 0)
    IPV6_COUNT=$(grep -c ':' "$WHITELIST_FILE" 2>/dev/null || echo 0)
    
    printf "总计: %b%s%b 条  |  IPv4: %b%s%b 条  |  IPv6: %b%s%b 条\n\n" \
        "$C_GREEN" "$TOTAL" "$C_RESET" \
        "$C_CYAN" "$IPV4_COUNT" "$C_RESET" \
        "$C_YELLOW" "$IPV6_COUNT" "$C_RESET"
    
    printf "%b%-45s%b\n" "$C_YELLOW" "IP 地址" "$C_RESET"
    echo "---------------------------------------------"
    
    awk '{printf "%-45s\n", $1}' "$WHITELIST_FILE"
    echo ""
    
    msg "$C_CYAN" "📌 文件位置: $WHITELIST_FILE"
}

do_add() {
    INPUT="$1"
    # 验证输入格式
    case "$INPUT" in
        */*)
            # CIDR 格式验证
            IP="${INPUT%%/*}"
            MASK="${INPUT##*/}"
            if ! echo "$MASK" | grep -qE '^[0-9]+$'; then
                msg "$C_RED" "❌ 无效的CIDR格式: $INPUT"
                exit 1
            fi
            ;;
        *:*|*.*.*.*)
            # IPv6 或 IPv4 单IP
            ;;
        *)
            msg "$C_RED" "❌ 无效的IP格式: $INPUT"
            exit 1
            ;;
    esac
    
    ban_ip "$INPUT" 1
    msg "$C_GREEN" "✅ 已封禁: $INPUT"
}
do_del() {
    INPUT="$1"
    
    # 标准化IP格式：单IP自动添加/32或/128
    case "$INPUT" in
        */*) DEL_ELEMENT="$INPUT" ;;  # 已包含CIDR
        *:*) DEL_ELEMENT="$INPUT/128" ;;  # IPv6单IP
        *) DEL_ELEMENT="$INPUT/32" ;;  # IPv4单IP
    esac
    
    if is_ipv6 "$INPUT"; then
        nft delete element $NFT_TABLE $NFT_SET_V6 "{ $DEL_ELEMENT }" >/dev/null 2>&1
    else
        nft delete element $NFT_TABLE $NFT_SET "{ $DEL_ELEMENT }" >/dev/null 2>&1
    fi
    
    # 从持久化文件删除（支持带国家代码的格式）
    if [ -f "$PERSIST_FILE" ]; then
        # 转义特殊字符用于sed
        ESCAPED=$(echo "$INPUT" | sed 's/[.[\/]/\\&/g')
        sed -i "/^$ESCAPED\(|.*\)\?$/d" "$PERSIST_FILE"
    fi
    
    log "[手动解封] IP=$INPUT"
    msg "$C_GREEN" "✅ 已解封: $INPUT"
}
do_restore() {
    check_and_install_env; init_nft_rules
    
    # 恢复黑名单
    if [ -f "$PERSIST_FILE" ]; then
        count=0
        while IFS='|' read -r ip _; do [ -n "$ip" ] && ban_ip "$ip" 2 && count=$((count+1)); done < "$PERSIST_FILE"
        log "[系统恢复] 已从磁盘恢复 $count 个黑名单 IP"
        msg "$C_GREEN" "✅ 已从磁盘恢复 $count 个黑名单 IP"
    fi
    
    # 恢复白名单
    if [ -f "$WHITELIST_FILE" ]; then
        wcount=0
        while IFS= read -r ip; do
            if [ -n "$ip" ]; then
                case "$ip" in
                    */*) ELEMENT="$ip" ;;
                    *:*) ELEMENT="$ip/128" ;;
                    *) ELEMENT="$ip/32" ;;
                esac
                
                if is_ipv6 "$ip"; then
                    nft add element $NFT_TABLE $NFT_WHITELIST_V6 "{ $ELEMENT }" 2>/dev/null && wcount=$((wcount+1))
                else
                    nft add element $NFT_TABLE $NFT_WHITELIST "{ $ELEMENT }" 2>/dev/null && wcount=$((wcount+1))
                fi
            fi
        done < "$WHITELIST_FILE"
        log "[系统恢复] 已从磁盘恢复 $wcount 个白名单 IP"
        msg "$C_GREEN" "✅ 已从磁盘恢复 $wcount 个白名单 IP"
    fi
}

do_install() {
    check_root
    CURRENT=$(readlink -f "$0" 2>/dev/null || echo "$0")
    if [ "$CURRENT" != "$INSTALL_PATH" ]; then cp "$0" "$INSTALL_PATH" && chmod +x "$INSTALL_PATH"; fi
    mkdir -p "$RECORD_DIR" && chmod 700 "$RECORD_DIR"
    touch "$PERSIST_FILE" && chmod 600 "$PERSIST_FILE"
    touch "$LOG_FILE" && chmod 666 "$LOG_FILE"
    check_and_install_env; init_nft_rules; do_restore
    PAM_FILE="/etc/pam.d/sshd"
    sed -i "\|$INSTALL_PATH|d" "$PAM_FILE"
    sed -i "1s|^|auth optional pam_exec.so quiet $INSTALL_PATH check\n|" "$PAM_FILE"
    echo "session optional pam_exec.so quiet $INSTALL_PATH clean" >> "$PAM_FILE"
    cat > "/etc/systemd/system/block-ip.service" <<EOF
[Unit]
Description=Block-IP Service
After=network.target nftables.service
[Service]
Type=oneshot
ExecStart=$INSTALL_PATH restore
RemainAfterExit=yes
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload; systemctl enable block-ip.service
    msg "$C_GREEN" "✅ 安装完成！输入 block-ip list 查看效果。"
}

do_uninstall() {
    check_root
    msg "$C_YELLOW" "⚠️  开始卸载 Block-IP..."
    
    # 停止并禁用服务
    if [ -f "/etc/systemd/system/block-ip.service" ]; then
        systemctl stop block-ip.service 2>/dev/null
        systemctl disable block-ip.service 2>/dev/null
        rm -f "/etc/systemd/system/block-ip.service"
        systemctl daemon-reload
        msg "$C_GREEN" "  ✓ 已移除 systemd 服务"
    fi
    
    # 清除 nftables 规则
    nft delete rule $NFT_TABLE input ip saddr @"$NFT_SET" drop 2>/dev/null
    nft delete rule $NFT_TABLE input ip6 saddr @"$NFT_SET_V6" drop 2>/dev/null
    nft delete rule $NFT_TABLE input ip saddr @"$NFT_WHITELIST" accept 2>/dev/null
    nft delete rule $NFT_TABLE input ip6 saddr @"$NFT_WHITELIST_V6" accept 2>/dev/null
    nft delete set $NFT_TABLE $NFT_SET 2>/dev/null
    nft delete set $NFT_TABLE $NFT_SET_V6 2>/dev/null
    nft delete set $NFT_TABLE $NFT_WHITELIST 2>/dev/null
    nft delete set $NFT_TABLE $NFT_WHITELIST_V6 2>/dev/null
    msg "$C_GREEN" "  ✓ 已清除防火墙规则"
    
    # 移除 PAM 配置
    PAM_FILE="/etc/pam.d/sshd"
    if [ -f "$PAM_FILE" ]; then
        sed -i "\|$INSTALL_PATH|d" "$PAM_FILE"
        msg "$C_GREEN" "  ✓ 已移除 PAM 钩子"
    fi
    
    # 删除文件 (可选保留日志和封禁列表)
    printf "是否删除封禁列表和日志? [y/N] "
    read -r REPLY
    if [ "$REPLY" = "y" ] || [ "$REPLY" = "Y" ]; then
        rm -f "$PERSIST_FILE" "$LOG_FILE" "${LOG_FILE}.1"
        msg "$C_GREEN" "  ✓ 已删除数据文件"
    else
        msg "$C_CYAN" "  ↳ 保留: $PERSIST_FILE, $LOG_FILE"
    fi
    
    rm -rf "$RECORD_DIR"
    rm -f "$INSTALL_PATH"
    msg "$C_GREEN" "  ✓ 已删除程序文件"
    
    msg "$C_GREEN" "\n✅ 卸载完成！"
}

do_check() {
    THE_IP=$(get_ip)
    [ -z "$THE_IP" ] && return
    
    # 检查白名单
    if [ -f "$WHITELIST_FILE" ]; then
        while IFS= read -r wip; do
            [ -z "$wip" ] && continue
            # 单IP精确匹配
            if [ "$THE_IP" = "$wip" ]; then
                log "[白名单放行] IP=$THE_IP"
                return
            fi
            # CIDR匹配（通过nftables集合）
            case "$wip" in
                */*)
                    PREFIX="${wip%%/*}"
                    MASK="${wip##*/}"
                    # 简化匹配：/8匹配第一段，/16匹配前两段，/24匹配前三段
                    case "$MASK" in
                        8)
                            A="${PREFIX%%.*.*.*}"
                            if echo "$THE_IP" | grep -q "^$A\."; then
                                log "[白名单放行] IP=$THE_IP 匹配白名单 $wip"
                                return
                            fi
                            ;;
                        16)
                            AB="${PREFIX%.*.*}"
                            if echo "$THE_IP" | grep -q "^$AB\."; then
                                log "[白名单放行] IP=$THE_IP 匹配白名单 $wip"
                                return
                            fi
                            ;;
                        24)
                            ABC="${PREFIX%.*}"
                            if echo "$THE_IP" | grep -q "^$ABC\."; then
                                log "[白名单放行] IP=$THE_IP 匹配白名单 $wip"
                                return
                            fi
                            ;;
                    esac
                    ;;
            esac
        done < "$WHITELIST_FILE"
    fi
    
    [ ! -d "$RECORD_DIR" ] && mkdir -p "$RECORD_DIR" && chmod 700 "$RECORD_DIR"
    IP_FILE="$RECORD_DIR/$THE_IP"
    COUNT=0
    [ -f "$IP_FILE" ] && COUNT=$(cat "$IP_FILE")
    COUNT=$((COUNT + 1))
    log "[验证失败] IP=$THE_IP (第 $COUNT/$MAX_RETRIES 次)"
    if [ "$COUNT" -ge "$MAX_RETRIES" ]; then ban_ip "$THE_IP" 1; rm -f "$IP_FILE"; else echo "$COUNT" > "$IP_FILE"; fi
}

do_clean() {
    THE_IP=$(get_ip)
    if [ -n "$THE_IP" ] && [ -f "$RECORD_DIR/$THE_IP" ]; then
        log "[登录成功] IP=$THE_IP (计数已重置)"
        rm -f "$RECORD_DIR/$THE_IP"
    fi
}

show_help() {
    echo "Block-IP v16.2 (IPv6 + CIDR + Whitelist)"
    echo "--------------------------------------"
    echo "使用方法:"
    echo "  block-ip list           查看实时统计/活跃列表/日志"
    echo "  block-ip show           显示本地持久化封禁列表"
    echo "  block-ip add <IP>       手动封禁 IP (支持IPv4/IPv6/CIDR)"
    echo "                          示例: 1.1.1.1 或 1.1.1.0/24 或 2001:db8::/32"
    echo "  block-ip del <IP>       手动解封 IP (支持IPv4/IPv6/CIDR)"
    echo "  block-ip vip add <IP>   添加IP到白名单 (支持IPv4/IPv6/CIDR)"
    echo "  block-ip vip del <IP>   从白名单移除IP"
    echo "  block-ip vip list       显示白名单列表"
    echo "  block-ip restore        从持久化文件恢复黑白名单"
    echo "  block-ip install        安装/重装服务"
    echo "  block-ip uninstall      卸载服务"
    echo "--------------------------------------"
}

case "$1" in
    check)     do_check ;;   
    clean)     do_clean ;;   
    list)      do_list ;;
    show)      do_show ;;
    vip)
        case "$2" in
            add)  do_vip_add "$3" ;;
            del)  do_vip_del "$3" ;;
            list) do_vip_list ;;
            *)    msg "$C_RED" "用法: block-ip vip {add|del|list} <IP>"; exit 1 ;;
        esac
        ;;
    add)       do_add "$2" ;;
    del)       do_del "$2" ;;
    restore)   do_restore ;;
    install)   do_install ;;
    uninstall) do_uninstall ;;
    "")        show_help; exit 1 ;;
    *)         if [ -n "$RHOST" ] || [ -n "$PAM_RHOST" ]; then do_check; exit 0; fi
               show_help; exit 1 ;;
esac