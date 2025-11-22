#!/bin/bash
# Xray 一键安装与管理脚本
# 路径: /etc/xray
# 支持: Debian/Ubuntu/CentOS, Alpine, OpenWrt
# 功能: 服务端安装, 多协议配置, 配置修改, 分享链接

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 路径定义
XRAY_DIR="/etc/xray"
XRAY_BIN="$XRAY_DIR/xray"
CONFIG_FILE="$XRAY_DIR/config.json"
GEOIP_FILE="$XRAY_DIR/geoip.dat"
GEOSITE_FILE="$XRAY_DIR/geosite.dat"
API_SERVER="127.0.0.1:10085"

# 检查 Root 权限
if [ "$(id -u)" != "0" ]; then
    echo -e "${RED}错误: 必须使用 root 权限运行此脚本${NC}"
    exit 1
fi

# 系统检测
detect_system() {
    if [ -f /etc/alpine-release ]; then
        SYSTEM_TYPE="Alpine"
        PKG_MANAGER="apk"
    elif command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
        SYSTEM_TYPE="Systemd" # Debian, Ubuntu, CentOS
        if command -v apt-get >/dev/null 2>&1; then
            PKG_MANAGER="apt"
        elif command -v yum >/dev/null 2>&1; then
            PKG_MANAGER="yum"
        else
            PKG_MANAGER="unknown"
        fi
    elif [ -f /etc/openwrt_release ]; then
        SYSTEM_TYPE="OpenWrt"
        PKG_MANAGER="opkg"
    else
        SYSTEM_TYPE="Generic" # 无服务管理器 (WSL, Docker 等)
        if command -v apt-get >/dev/null 2>&1; then
            PKG_MANAGER="apt"
        elif command -v apk >/dev/null 2>&1; then
            PKG_MANAGER="apk"
        else
            PKG_MANAGER="unknown"
        fi
    fi

    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64) XRAY_ARCH="64" ;;
        aarch64) XRAY_ARCH="arm64-v8a" ;;
        armv7l) XRAY_ARCH="arm32-v7a" ;;
        *) echo -e "${RED}不支持的架构: $ARCH${NC}"; exit 1 ;;
    esac
}

# 安装依赖
install_dependencies() {
    # 预检查依赖，避免重复安装
    if command -v curl >/dev/null 2>&1 && \
       command -v unzip >/dev/null 2>&1 && \
       command -v jq >/dev/null 2>&1; then
        return 0
    fi

    echo -e "${BLUE}正在安装必要依赖...${NC}"
    case "$PKG_MANAGER" in
        apt)
            apt-get update
            apt-get install -y curl unzip jq
            ;;
        yum)
            yum install -y curl unzip jq
            ;;
        apk)
            apk add curl unzip jq
            ;;
        opkg)
            opkg update
            opkg install curl unzip jq
            ;;
        *)
            echo -e "${YELLOW}无法自动安装依赖，请确保已安装: curl, unzip, jq${NC}"
            ;;
    esac
}

# 获取 UUID
get_uuid() {
    cat /proc/sys/kernel/random/uuid
}

# 获取随机端口
get_random_port() {
    shuf -i 10000-65000 -n 1
}

# 安装 Xray
install_xray() {
    install_dependencies
    
    echo -e "${BLUE}正在获取 Xray 最新版本...${NC}"
    LATEST_VERSION=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases/latest | jq -r .tag_name)
    if [ -z "$LATEST_VERSION" ] || [ "$LATEST_VERSION" == "null" ]; then
        echo -e "${RED}获取版本失败，请检查网络连接${NC}"
        exit 1
    fi

    # 检查当前版本
    if [ -f "$XRAY_BIN" ]; then
        CURRENT_VERSION=$($XRAY_BIN version | head -n 1 | awk '{print $2}')
        # 移除 v 前缀
        LATEST_V_NUM=${LATEST_VERSION#v}
        CURRENT_V_NUM=${CURRENT_VERSION#v}
        
        if [ "$LATEST_V_NUM" == "$CURRENT_V_NUM" ]; then
            echo -e "${GREEN}当前已是最新版本 ($CURRENT_VERSION)${NC}"
            return 0
        fi
        echo -e "${YELLOW}发现新版本: $CURRENT_VERSION -> $LATEST_VERSION${NC}"
    else
        echo -e "${GREEN}准备安装版本: $LATEST_VERSION${NC}"
    fi

    mkdir -p "$XRAY_DIR"

    DOWNLOAD_URL="https://github.com/XTLS/Xray-core/releases/download/${LATEST_VERSION}/Xray-linux-${XRAY_ARCH}.zip"
    echo -e "${BLUE}正在下载 Xray...${NC}"
    curl -L -o /tmp/xray.zip "$DOWNLOAD_URL"

    echo -e "${BLUE}正在解压...${NC}"
    unzip -o /tmp/xray.zip -d /tmp/xray_extract
    mv /tmp/xray_extract/xray "$XRAY_BIN"
    mv /tmp/xray_extract/geoip.dat "$GEOIP_FILE"
    mv /tmp/xray_extract/geosite.dat "$GEOSITE_FILE"
    
    chmod +x "$XRAY_BIN"
    ln -sf "$XRAY_BIN" /usr/bin/xray
    
    rm -rf /tmp/xray.zip /tmp/xray_extract
    echo -e "${GREEN}Xray 安装完成${NC}"
}

# 配置服务
setup_service() {
    if [ "$SYSTEM_TYPE" == "Generic" ]; then
        echo -e "${YELLOW}未检测到 Systemd/OpenRC/Procd，将使用后台进程运行。${NC}"
        return
    fi

    echo -e "${BLUE}正在配置系统服务...${NC}"
    if [ "$SYSTEM_TYPE" == "Systemd" ]; then
        cat > /etc/systemd/system/xray.service <<EOF
[Unit]
Description=Xray Service
Documentation=https://github.com/xtls
After=network.target nss-lookup.target

[Service]
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=$XRAY_BIN run -c $CONFIG_FILE
Restart=on-failure
RestartPreventExitStatus=23
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable xray
    elif [ "$SYSTEM_TYPE" == "Alpine" ]; then
        cat > /etc/init.d/xray <<EOF
#!/sbin/openrc-run

name="xray"
command="$XRAY_BIN"
command_args="run -c $CONFIG_FILE"
command_background=true
pidfile="/run/xray.pid"

depend() {
    need net
    use dns
}
EOF
        chmod +x /etc/init.d/xray
        rc-update add xray default
    elif [ "$SYSTEM_TYPE" == "OpenWrt" ]; then
        cat > /etc/init.d/xray <<EOF
#!/bin/sh /etc/rc.common

START=99
USE_PROCD=1

start_service() {
    procd_open_instance
    procd_set_param command "$XRAY_BIN" run -c "$CONFIG_FILE"
    procd_set_param respawn
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_close_instance
}
EOF
        chmod +x /etc/init.d/xray
        /etc/init.d/xray enable
    fi
}

# 生成配置
configure_xray() {
    if [ -f "$CONFIG_FILE" ]; then
        echo -e "${YELLOW}检测到配置文件已存在。${NC}"
        read -p "是否重新配置? [y/N]: " RECONFIG
        if [[ ! "$RECONFIG" =~ ^[Yy]$ ]]; then
            echo -e "${GREEN}保留现有配置。${NC}"
            return
        fi
    fi

    echo -e "${YELLOW}请选择配置模式:${NC}"
    echo "1. 快速配置 (VLESS + Reality + Vision) [推荐]"
    echo "2. 手动配置"
    read -p "请选择 [1-2] (默认1): " MODE
    MODE=${MODE:-1}

    UUID=$(get_uuid)
    PORT=$(get_random_port)

    if [ "$MODE" == "1" ]; then
        # Reality 配置
        KEYS=$($XRAY_BIN x25519)
        if [ -z "$KEYS" ]; then
            echo -e "${RED}错误: 无法生成密钥，Xray 可能未正确安装或无法运行。${NC}"
            return
        fi
        
        # 解析密钥 (新版本格式: Password 即为 Public Key)
        PRIVATE_KEY=$(echo "$KEYS" | grep "PrivateKey:" | awk -F ':' '{print $NF}' | tr -d '[:space:]')
        PUBLIC_KEY=$(echo "$KEYS" | grep "Password:" | awk -F ':' '{print $NF}' | tr -d '[:space:]')

        # 检查密钥是否有效
        if [ -z "$PRIVATE_KEY" ] || [ -z "$PUBLIC_KEY" ]; then
            echo -e "${RED}错误: 无法解析密钥。${NC}"
            echo -e "${YELLOW}调试信息 - 原始输出:${NC}"
            echo "$KEYS"
            return
        fi

        # 使用系统 UUID 截取生成 ShortId
        SHORT_ID=$(cat /proc/sys/kernel/random/uuid | tr -d '-' | head -c 8)
        
        # 默认 SNI
        SNI="www.microsoft.com"
        
        cat > "$CONFIG_FILE" <<EOF
{
  "log": {
    "access": "/etc/xray/access.log",
    "error": "/etc/xray/error.log",
    "loglevel": "warning"
  },
  "api": {
    "tag": "api",
    "listen": "127.0.0.1:10085",
    "services": [
      "HandlerService",
      "LoggerService",
      "StatsService",
      "RoutingService",
      "ReflectionService"
    ]
  },
  "inbounds": [
    {
      "tag": "vless-reality",
      "port": $PORT,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$UUID",
            "flow": "xtls-rprx-vision",
            "email": "root@xray"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "fingerprint": "chrome",
          "dest": "$SNI:443",
          "xver": 0,
          "serverNames": [
            "$SNI"
          ],
          "privateKey": "$PRIVATE_KEY",
          "shortIds": [
            "$SHORT_ID"
          ]
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": [
          "http",
          "tls",
          "quic"
        ]
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "tag": "block"
    }
  ],
  "policy": {
    "levels": {
      "0": {
        "handshake": 10,
        "connIdle": 100,
        "uplinkOnly": 2,
        "downlinkOnly": 5,
        "statsUserUplink": true,
        "statsUserDownlink": true,
        "bufferSize": 4
      }
    },
    "system": {
      "statsInboundUplink": true,
      "statsInboundDownlink": true,
      "statsOutboundUplink": true,
      "statsOutboundDownlink": true
    }
  },
  "routing": {
    "domainStrategy": "AsIs",
    "rules": [
      {
        "type": "field",
        "ip": [
          "geoip:private"
        ],
        "outboundTag": "block"
      }
    ]
  },
  "stats": {}
}
EOF
        echo -e "${GREEN}配置已生成 (VLESS-Reality-Vision)${NC}"
        echo -e "端口: $PORT"
        echo -e "UUID: $UUID"
        echo -e "SNI: $SNI"
        echo -e "Public Key: $PUBLIC_KEY"
        echo -e "Short ID: $SHORT_ID"
        
    else
        # 手动配置基础框架 (简化版，仅支持 VLESS/VMess TCP)
        echo "1. VLESS"
        echo "2. VMess"
        read -p "选择协议 [1-2]: " PROTO_CHOICE
        
        read -p "请输入端口 (默认随机): " INPUT_PORT
        if [ ! -z "$INPUT_PORT" ]; then PORT=$INPUT_PORT; fi

        if [ "$PROTO_CHOICE" == "2" ]; then
            # VMess TCP
            cat > "$CONFIG_FILE" <<EOF
{
  "log": {
    "access": "/etc/xray/access.log",
    "error": "/etc/xray/error.log",
    "loglevel": "warning"
  },
  "api": {
    "tag": "api",
    "listen": "127.0.0.1:10085",
    "services": [
      "HandlerService",
      "LoggerService",
      "StatsService",
      "RoutingService",
      "ReflectionService"
    ]
  },
  "inbounds": [
    {
      "tag": "vmess-tcp",
      "port": $PORT,
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "$UUID",
            "email": "root@xray"
          }
        ]
      },
      "streamSettings": {
        "network": "tcp"
      },
      "sniffing": {
        "enabled": true,
        "destOverride": [
          "http",
          "tls",
          "quic"
        ]
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "tag": "block"
    }
  ],
  "policy": {
    "levels": {
      "0": {
        "handshake": 10,
        "connIdle": 100,
        "uplinkOnly": 2,
        "downlinkOnly": 5,
        "statsUserUplink": true,
        "statsUserDownlink": true,
        "bufferSize": 4
      }
    },
    "system": {
      "statsInboundUplink": true,
      "statsInboundDownlink": true,
      "statsOutboundUplink": true,
      "statsOutboundDownlink": true
    }
  },
  "routing": {
    "domainStrategy": "AsIs",
    "rules": [
      {
        "type": "field",
        "ip": [
          "geoip:private"
        ],
        "outboundTag": "block"
      }
    ]
  },
  "stats": {}
}
EOF
            echo -e "${GREEN}配置已生成 (VMess-TCP)${NC}"
        else
            # VLESS TCP
            cat > "$CONFIG_FILE" <<EOF
{
  "log": {
    "access": "/etc/xray/access.log",
    "error": "/etc/xray/error.log",
    "loglevel": "warning"
  },
  "api": {
    "tag": "api",
    "listen": "127.0.0.1:10085",
    "services": [
      "HandlerService",
      "LoggerService",
      "StatsService",
      "RoutingService",
      "ReflectionService"
    ]
  },
  "inbounds": [
    {
      "tag": "vless-tcp",
      "port": $PORT,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$UUID",
            "email": "root@xray"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp"
      },
      "sniffing": {
        "enabled": true,
        "destOverride": [
          "http",
          "tls",
          "quic"
        ]
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "tag": "block"
    }
  ],
  "policy": {
    "levels": {
      "0": {
        "handshake": 10,
        "connIdle": 100,
        "uplinkOnly": 2,
        "downlinkOnly": 5,
        "statsUserUplink": true,
        "statsUserDownlink": true,
        "bufferSize": 4
      }
    },
    "system": {
      "statsInboundUplink": true,
      "statsInboundDownlink": true,
      "statsOutboundUplink": true,
      "statsOutboundDownlink": true
    }
  },
  "routing": {
    "domainStrategy": "AsIs",
    "rules": [
      {
        "type": "field",
        "ip": [
          "geoip:private"
        ],
        "outboundTag": "block"
      }
    ]
  },
  "stats": {}
}
EOF
            echo -e "${GREEN}配置已生成 (VLESS-TCP)${NC}"
        fi
    fi
}

# 检查 API 可用性
check_api() {
    $XRAY_BIN api statssys -s "$API_SERVER" >/dev/null 2>&1
    return $?
}

# 重启日志 (API)
restart_logger() {
    if ! check_api; then
        echo -e "${RED}API 服务未运行${NC}"
        return 1
    fi
    $XRAY_BIN api restartlogger -s "$API_SERVER"
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}日志服务已重启${NC}"
    else
        echo -e "${RED}日志服务重启失败${NC}"
    fi
}

# 查看日志菜单
view_log_menu() {
    while true; do
        echo -e "${YELLOW}日志管理${NC}"
        echo "1. 查看访问日志 (Access Log)"
        echo "2. 查看错误日志 (Error Log)"
        echo "3. 重启日志服务 (Reopen Logs)"
        echo "0. 返回上级"
        read -p "请选择: " LOG_CHOICE
        
        case "$LOG_CHOICE" in
            1)
                ACCESS_LOG=$(jq -r .log.access "$CONFIG_FILE")
                if [ -f "$ACCESS_LOG" ]; then
                    echo -e "${GREEN}正在查看访问日志 (Ctrl+C 退出)...${NC}"
                    tail -f "$ACCESS_LOG"
                else
                    echo -e "${RED}访问日志文件不存在: $ACCESS_LOG${NC}"
                fi
                ;;
            2)
                ERROR_LOG=$(jq -r .log.error "$CONFIG_FILE")
                if [ -f "$ERROR_LOG" ]; then
                    echo -e "${GREEN}正在查看错误日志 (Ctrl+C 退出)...${NC}"
                    tail -f "$ERROR_LOG"
                else
                    echo -e "${RED}错误日志文件不存在: $ERROR_LOG${NC}"
                fi
                ;;
            3)
                restart_logger
                read -n 1 -s -r -p "按任意键继续..."
                ;;
            0)
                break
                ;;
            *)
                echo "无效选择"
                ;;
        esac
    done
}

# 重载入站 (使用 API)
reload_inbound() {
    local INDEX=$1
    local OLD_TAG=$2
    
    # 检查 API 状态
    if ! check_api; then
        # API 不可用，回退到重启
        restart_service
        return
    fi

    # 获取当前 Tag (如果未提供旧 Tag，则假设 Tag 未变，从文件读取)
    if [ -z "$OLD_TAG" ]; then
        OLD_TAG=$(jq -r ".inbounds[$INDEX].tag" "$CONFIG_FILE")
    fi
    
    # 提取新入站配置
    local TMP_JSON=$(mktemp)
    jq "{inbounds: [.inbounds[$INDEX]]}" "$CONFIG_FILE" > "$TMP_JSON"
    
    # 移除旧入站
    "$XRAY_BIN" api rmi -s "$API_SERVER" "$OLD_TAG" >/dev/null 2>&1
    
    # 添加新入站
    if "$XRAY_BIN" api adi -s "$API_SERVER" "$TMP_JSON" >/dev/null 2>&1; then
        echo -e "${GREEN}配置已热更新 (API)${NC}"
    else
        echo -e "${RED}热更新失败，尝试重启服务...${NC}"
        restart_service
    fi
    
    rm -f "$TMP_JSON"
}

# 修改配置
modify_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${RED}配置文件不存在!${NC}"
        return
    fi

    echo -e "${BLUE}=== 入站列表 ===${NC}"
    # 获取入站数量
    INBOUND_COUNT=$(jq '.inbounds | length' "$CONFIG_FILE")
    
    if [ "$INBOUND_COUNT" -eq 0 ]; then
        echo -e "${RED}未找到入站配置${NC}"
        return
    fi

    # 映射显示索引到真实索引
    declare -a REAL_INDICES
    local DISPLAY_INDEX=1

    # 列出所有入站
    for ((i=0; i<INBOUND_COUNT; i++)); do
        TAG=$(jq -r ".inbounds[$i].tag // empty" "$CONFIG_FILE")
        
        # 跳过 API 入站
        if [ "$TAG" == "api" ]; then
            continue
        fi
        
        REAL_INDICES[$DISPLAY_INDEX]=$i
        
        PROTO=$(jq -r ".inbounds[$i].protocol" "$CONFIG_FILE")
        PORT=$(jq -r ".inbounds[$i].port" "$CONFIG_FILE")
        
        # 构造协议显示字符串
        PROTO_DISPLAY=$(echo "$PROTO" | tr '[:lower:]' '[:upper:]')
        if [ "$PROTO" == "vless" ]; then
            SECURITY=$(jq -r ".inbounds[$i].streamSettings.security" "$CONFIG_FILE")
            FLOW=$(jq -r ".inbounds[$i].settings.clients[0].flow" "$CONFIG_FILE")
            if [ "$SECURITY" == "reality" ]; then
                PROTO_DISPLAY="${PROTO_DISPLAY}-Reality"
            fi
            if [[ "$FLOW" == *"vision"* ]]; then
                PROTO_DISPLAY="${PROTO_DISPLAY}-Vision"
            fi
        elif [ "$PROTO" == "vmess" ]; then
             NET=$(jq -r ".inbounds[$i].streamSettings.network" "$CONFIG_FILE")
             PROTO_DISPLAY="${PROTO_DISPLAY}-${NET}"
        fi

        if [ "$TAG" == "empty" ] || [ -z "$TAG" ]; then
            REMARK="无备注"
        else
            REMARK="$TAG"
        fi
        
        echo -e "${GREEN}${DISPLAY_INDEX}.${NC} 备注: ${YELLOW}$REMARK${NC} | 协议: ${YELLOW}$PROTO_DISPLAY${NC} | 端口: ${YELLOW}$PORT${NC}"
        ((DISPLAY_INDEX++))
    done
    
    MAX_CHOICE=$((DISPLAY_INDEX-1))
    echo "0. 返回"
    echo "------------------------"
    read -p "请选择要修改的入站编号 [1-$MAX_CHOICE] (0 返回): " CHOICE

    if [ "$CHOICE" == "0" ]; then
        return
    fi

    # 验证输入
    if ! [[ "$CHOICE" =~ ^[0-9]+$ ]] || [ "$CHOICE" -lt 1 ] || [ "$CHOICE" -gt "$MAX_CHOICE" ]; then
        echo -e "${RED}无效的选择${NC}"
        return
    fi
    
    INDEX=${REAL_INDICES[$CHOICE]}

    # 获取选中入站的详细信息
    PROTOCOL=$(jq -r ".inbounds[$INDEX].protocol" "$CONFIG_FILE")
    SECURITY=$(jq -r ".inbounds[$INDEX].streamSettings.security // \"none\"" "$CONFIG_FILE")
    OLD_TAG=$(jq -r ".inbounds[$INDEX].tag // empty" "$CONFIG_FILE")
    if [ "$OLD_TAG" == "empty" ]; then OLD_TAG=""; fi
    
    echo -e "${BLUE}=== 修改入站 #$CHOICE ($PROTOCOL) ===${NC}"
    echo "1. 修改端口"
    echo "2. 修改备注"
    
    # 根据协议显示选项
    if [[ "$PROTOCOL" == "vless" || "$PROTOCOL" == "vmess" ]]; then
        echo "3. 修改 UUID"
    fi
    
    if [[ "$SECURITY" == "reality" ]]; then
        echo "4. 修改 Reality 目标网站 (SNI)"
        echo "5. 修改 Reality 私钥 (PrivateKey)"
        echo "6. 修改 Reality ShortId"
    fi
    
    echo "9. 重新生成完整配置"
    echo "0. 返回"
    read -p "请选择修改项: " OPT

    case "$OPT" in
        1)
            read -p "请输入新端口: " NEW_PORT
            if [[ "$NEW_PORT" =~ ^[0-9]+$ ]]; then
                tmp=$(mktemp)
                jq --argjson idx "$INDEX" --argjson port "$NEW_PORT" '.inbounds[$idx].port = $port' "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
                echo -e "${GREEN}端口已修改为 $NEW_PORT${NC}"
                reload_inbound "$INDEX" "$OLD_TAG"
            else
                echo -e "${RED}无效端口${NC}"
            fi
            ;;
        2)
            read -p "请输入新备注: " NEW_TAG
            if [ ! -z "$NEW_TAG" ]; then
                tmp=$(mktemp)
                jq --argjson idx "$INDEX" --arg tag "$NEW_TAG" '.inbounds[$idx].tag = $tag' "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
                echo -e "${GREEN}备注已修改为 $NEW_TAG${NC}"
                reload_inbound "$INDEX" "$OLD_TAG"
            fi
            ;;
        3)
            if [[ "$PROTOCOL" == "vless" || "$PROTOCOL" == "vmess" ]]; then
                NEW_UUID=$(get_uuid)
                echo -e "新 UUID: $NEW_UUID"
                tmp=$(mktemp)
                jq --argjson idx "$INDEX" --arg uuid "$NEW_UUID" '.inbounds[$idx].settings.clients[0].id = $uuid' "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
                echo -e "${GREEN}UUID 已更新${NC}"
                reload_inbound "$INDEX" "$OLD_TAG"
            fi
            ;;
        4)
            if [[ "$SECURITY" == "reality" ]]; then
                read -p "请输入新的 SNI (例如 www.microsoft.com): " NEW_SNI
                if [ ! -z "$NEW_SNI" ]; then
                    tmp=$(mktemp)
                    # 更新 dest (SNI:443) 和 serverNames
                    jq --argjson idx "$INDEX" --arg sni "$NEW_SNI" \
                       '.inbounds[$idx].streamSettings.realitySettings.serverNames = [$sni] | .inbounds[$idx].streamSettings.realitySettings.dest = ($sni + ":443")' \
                       "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
                    echo -e "${GREEN}SNI 已更新为 $NEW_SNI${NC}"
                    reload_inbound "$INDEX" "$OLD_TAG"
                fi
            fi
            ;;
        5)
            if [[ "$SECURITY" == "reality" ]]; then
                echo "正在生成新密钥对..."
                KEYS=$($XRAY_BIN x25519)
                NEW_PRIVATE_KEY=$(echo "$KEYS" | grep "PrivateKey:" | awk -F ':' '{print $NF}' | tr -d '[:space:]')
                NEW_PUBLIC_KEY=$(echo "$KEYS" | grep "Password:" | awk -F ':' '{print $NF}' | tr -d '[:space:]')
                
                if [ ! -z "$NEW_PRIVATE_KEY" ]; then
                    tmp=$(mktemp)
                    jq --argjson idx "$INDEX" --arg key "$NEW_PRIVATE_KEY" '.inbounds[$idx].streamSettings.realitySettings.privateKey = $key' "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
                    echo -e "${GREEN}PrivateKey 已更新${NC}"
                    echo -e "新的 Public Key (Password): ${YELLOW}$NEW_PUBLIC_KEY${NC} (请更新客户端)"
                    reload_inbound "$INDEX" "$OLD_TAG"
                else
                    echo -e "${RED}生成密钥失败${NC}"
                fi
            fi
            ;;
        6)
            if [[ "$SECURITY" == "reality" ]]; then
                NEW_SHORT_ID=$(cat /proc/sys/kernel/random/uuid | tr -d '-' | head -c 8)
                echo -e "新 ShortId: $NEW_SHORT_ID"
                tmp=$(mktemp)
                jq --argjson idx "$INDEX" --arg sid "$NEW_SHORT_ID" '.inbounds[$idx].streamSettings.realitySettings.shortIds = [$sid]' "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
                echo -e "${GREEN}ShortId 已更新${NC}"
                reload_inbound "$INDEX" "$OLD_TAG"
            fi
            ;;
        9)
            configure_xray
            restart_service
            ;;
        *)
            return
            ;;
    esac
}



# 服务操作
start_service() {
    # 启动前检查配置有效性
    if [ -f "$XRAY_BIN" ] && [ -f "$CONFIG_FILE" ]; then
        if ! "$XRAY_BIN" run -test -c "$CONFIG_FILE" >/dev/null 2>&1; then
            echo -e "${RED}错误: 配置文件无效，无法启动服务。${NC}"
            echo -e "${YELLOW}请尝试在菜单中选择 '2. 修改配置' -> '3. 重新生成完整配置'${NC}"
            "$XRAY_BIN" run -test -c "$CONFIG_FILE" # 输出具体错误
            return 1
        fi
    fi

    if [ "$SYSTEM_TYPE" == "Systemd" ]; then
        systemctl start xray
    elif [ "$SYSTEM_TYPE" == "Alpine" ] || [ "$SYSTEM_TYPE" == "OpenWrt" ]; then
        /etc/init.d/xray start
    elif [ "$SYSTEM_TYPE" == "Generic" ]; then
        if pgrep -f "$XRAY_BIN" >/dev/null; then
            echo -e "${YELLOW}Xray 已经在运行中${NC}"
        else
            nohup "$XRAY_BIN" run -c "$CONFIG_FILE" >/dev/null 2>&1 &
            echo -e "${GREEN}Xray 已在后台启动${NC}"
        fi
    fi
    
    # 检查是否启动成功
    sleep 1
    if pgrep -f "$XRAY_BIN" >/dev/null; then
        echo -e "${GREEN}服务状态: 运行中${NC}"
    else
        echo -e "${RED}服务启动失败，请检查日志${NC}"
    fi
}

stop_service() {
    if [ "$SYSTEM_TYPE" == "Systemd" ]; then
        systemctl stop xray
    elif [ "$SYSTEM_TYPE" == "Alpine" ] || [ "$SYSTEM_TYPE" == "OpenWrt" ]; then
        /etc/init.d/xray stop
    elif [ "$SYSTEM_TYPE" == "Generic" ]; then
        pkill -f "$XRAY_BIN"
        echo -e "${GREEN}Xray 进程已停止${NC}"
    fi
}

restart_service() {
    stop_service
    sleep 1
    start_service
}

# 查看链接
view_link() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${RED}配置文件不存在${NC}"
        return
    fi
    
    IP=$(curl -s4 ifconfig.me)
    INBOUND_COUNT=$(jq '.inbounds | length' "$CONFIG_FILE")
    
    echo -e "${BLUE}=== 连接信息 ===${NC}"
    echo -e "地址 (IP): $IP"

    for ((i=0; i<INBOUND_COUNT; i++)); do
        TAG=$(jq -r ".inbounds[$i].tag // empty" "$CONFIG_FILE")
        
        # 跳过 API 入站
        if [ "$TAG" == "api" ]; then
            continue
        fi

        PORT=$(jq -r ".inbounds[$i].port" "$CONFIG_FILE")
        UUID=$(jq -r ".inbounds[$i].settings.clients[0].id" "$CONFIG_FILE")
        PROTOCOL=$(jq -r ".inbounds[$i].protocol" "$CONFIG_FILE")
        
        # Determine remark name
        if [ -z "$TAG" ] || [ "$TAG" == "empty" ]; then
            # Default remark
            if [ "$PROTOCOL" == "vless" ]; then
                SECURITY=$(jq -r ".inbounds[$i].streamSettings.security" "$CONFIG_FILE")
                if [ "$SECURITY" == "reality" ]; then
                    REMARK="Xray-Reality"
                else
                    REMARK="Xray-VLESS"
                fi
            else
                REMARK="Xray-$PROTOCOL"
            fi
        else
            REMARK="$TAG"
        fi
        
        echo -e "\n${GREEN}--- 入站 #$((i+1)) ($PROTOCOL) ---${NC}"
        echo -e "端口: $PORT"
        echo -e "UUID: $UUID"
        echo -e "备注: $REMARK"

        if [ "$PROTOCOL" == "vless" ]; then
            SECURITY=$(jq -r ".inbounds[$i].streamSettings.security" "$CONFIG_FILE")
            if [ "$SECURITY" == "reality" ]; then
                PBK=$(jq -r ".inbounds[$i].streamSettings.realitySettings.privateKey" "$CONFIG_FILE" | xargs -I {} $XRAY_BIN x25519 -i {} | grep "Password:" | awk -F ':' '{print $NF}' | tr -d '[:space:]')
                SNI=$(jq -r ".inbounds[$i].streamSettings.realitySettings.serverNames[0]" "$CONFIG_FILE")
                SID=$(jq -r ".inbounds[$i].streamSettings.realitySettings.shortIds[0]" "$CONFIG_FILE")
                FLOW=$(jq -r ".inbounds[$i].settings.clients[0].flow" "$CONFIG_FILE")
                
                LINK="vless://$UUID@$IP:$PORT?security=reality&encryption=none&pbk=$PBK&headerType=none&fp=chrome&type=tcp&flow=$FLOW&sni=$SNI&sid=$SID#$REMARK"
                echo -e "${YELLOW}分享链接:${NC}"
                echo -e "$LINK"
            else
                echo -e "${YELLOW}分享链接:${NC}"
                echo -e "vless://$UUID@$IP:$PORT?encryption=none&security=none&type=tcp#$REMARK"
            fi
        elif [ "$PROTOCOL" == "vmess" ]; then
            VMESS_JSON="{\"v\":\"2\",\"ps\":\"$REMARK\",\"add\":\"$IP\",\"port\":\"$PORT\",\"id\":\"$UUID\",\"aid\":\"0\",\"scy\":\"auto\",\"net\":\"tcp\",\"type\":\"none\",\"host\":\"\",\"path\":\"\",\"tls\":\"\"}"
            VMESS_B64=$(echo -n "$VMESS_JSON" | base64 | tr -d '\n')
            echo -e "${YELLOW}分享链接:${NC}"
            echo -e "vmess://$VMESS_B64"
        fi
    done
}

# 格式化字节数
format_bytes() {
    echo "$1" | awk '{ split( "B KB MB GB TB" , v ); s=1; while( $1>1024 ){ $1/=1024; s++ } printf "%.2f %s", $1, v[s] }'
}

# 查看统计
view_stats() {
    if ! check_api; then
        echo -e "${RED}API 服务未运行或端口未监听${NC}"
        read -n 1 -s -r -p "按任意键返回..."
        return
    fi
    
    while true; do
        clear
        echo -e "${BLUE}=== 流量统计 ===${NC}"
        
        # 获取系统统计
        SYS_STATS=$("$XRAY_BIN" api statssys -s "$API_SERVER")
        UPTIME=$(echo "$SYS_STATS" | jq -r .Uptime)
        # 简单的 uptime 格式化
        UPTIME_H=$(awk -v s="$UPTIME" 'BEGIN {printf "%d天 %02d:%02d:%02d", s/86400, (s%86400)/3600, (s%3600)/60, s%60}')
        
        echo -e "运行时间: ${GREEN}$UPTIME_H${NC}"
        echo "------------------------"
        
        STATS_JSON=$("$XRAY_BIN" api statsquery -s "$API_SERVER" "")
        
        echo -e "${YELLOW}--- 入站流量 ---${NC}"
        printf "%-20s %-15s %-15s\n" "Tag" "上行 (Uplink)" "下行 (Downlink)"
        
        # 提取所有入站 Tag
        TAGS=$(echo "$STATS_JSON" | jq -r '.stat[] | select(.name | startswith("inbound>>>")) | .name | split(">>>")[1]' | sort | uniq)
        
        if [ -z "$TAGS" ]; then
            echo "暂无数据"
        else
            for TAG in $TAGS; do
                if [ "$TAG" == "api" ]; then continue; fi
                
                UP=$(echo "$STATS_JSON" | jq -r ".stat[] | select(.name == \"inbound>>>$TAG>>>traffic>>>uplink\") | .value // 0")
                DOWN=$(echo "$STATS_JSON" | jq -r ".stat[] | select(.name == \"inbound>>>$TAG>>>traffic>>>downlink\") | .value // 0")
                
                UP_H=$(format_bytes "$UP")
                DOWN_H=$(format_bytes "$DOWN")
                
                printf "%-20s %-15s %-15s\n" "$TAG" "$UP_H" "$DOWN_H"
            done
        fi
        
        echo "------------------------"
        echo "r. 重置统计数据"
        echo "0. 返回主菜单"
        read -p "请选择: " OP
        
        case "$OP" in
            r|R)
                "$XRAY_BIN" api statsquery -s "$API_SERVER" "" true >/dev/null
                echo -e "${GREEN}统计已重置${NC}"
                sleep 1
                ;;
            0)
                return
                ;;
            *)
                ;;
        esac
    done
}

# 添加新入站
add_inbound() {
    echo -e "${YELLOW}添加新入站配置${NC}"
    echo "1. VLESS + Reality + Vision [推荐]"
    echo "2. VMess + TCP"
    echo "3. VLESS + TCP"
    read -p "请选择 [1-3] (默认1): " TYPE
    TYPE=${TYPE:-1}

    UUID=$(get_uuid)
    PORT=$(get_random_port)
    TAG="inbound-$(date +%s)"

    if [ "$TYPE" == "1" ]; then
        # Reality Logic
        KEYS=$($XRAY_BIN x25519)
        PRIVATE_KEY=$(echo "$KEYS" | grep "PrivateKey:" | awk -F ':' '{print $NF}' | tr -d '[:space:]')
        PUBLIC_KEY=$(echo "$KEYS" | grep "Password:" | awk -F ':' '{print $NF}' | tr -d '[:space:]')
        SHORT_ID=$(cat /proc/sys/kernel/random/uuid | tr -d '-' | head -c 8)
        SNI="www.microsoft.com"
        
        INBOUND_JSON=$(cat <<EOF
{
  "tag": "$TAG",
  "port": $PORT,
  "protocol": "vless",
  "settings": {
    "clients": [
      {
        "id": "$UUID",
        "flow": "xtls-rprx-vision",
        "email": "user@xray"
      }
    ],
    "decryption": "none"
  },
  "streamSettings": {
    "network": "tcp",
    "security": "reality",
    "realitySettings": {
      "show": false,
      "fingerprint": "chrome",
      "dest": "$SNI:443",
      "xver": 0,
      "serverNames": ["$SNI"],
      "privateKey": "$PRIVATE_KEY",
      "shortIds": ["$SHORT_ID"]
    }
  },
  "sniffing": {
    "enabled": true,
    "destOverride": ["http", "tls", "quic"]
  }
}
EOF
)
    elif [ "$TYPE" == "2" ]; then
        # VMess TCP
        INBOUND_JSON=$(cat <<EOF
{
  "tag": "$TAG",
  "port": $PORT,
  "protocol": "vmess",
  "settings": {
    "clients": [
      {
        "id": "$UUID",
        "alterId": 0
      }
    ]
  },
  "streamSettings": {
    "network": "tcp"
  },
  "sniffing": {
    "enabled": true,
    "destOverride": ["http", "tls", "quic"]
  }
}
EOF
)
    elif [ "$TYPE" == "3" ]; then
        # VLESS TCP
        INBOUND_JSON=$(cat <<EOF
{
  "tag": "$TAG",
  "port": $PORT,
  "protocol": "vless",
  "settings": {
    "clients": [
      {
        "id": "$UUID"
      }
    ],
    "decryption": "none"
  },
  "streamSettings": {
    "network": "tcp"
  },
  "sniffing": {
    "enabled": true,
    "destOverride": ["http", "tls", "quic"]
  }
}
EOF
)
    fi

    # Add via API
    echo "{ \"inbounds\": [ $INBOUND_JSON ] }" | $XRAY_BIN api adi -s "$API_SERVER"
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}入站添加成功 (API)${NC}"
        # Update config.json
        tmp=$(mktemp)
        jq --argjson new "$INBOUND_JSON" '.inbounds += [$new]' "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
        echo -e "${GREEN}配置文件已更新${NC}"
        
        echo -e "端口: $PORT"
        echo -e "UUID: $UUID"
        if [ "$TYPE" == "1" ]; then
             echo -e "Public Key: $PUBLIC_KEY"
             echo -e "Short ID: $SHORT_ID"
        fi
    else
        echo -e "${RED}添加失败 (API)${NC}"
    fi
}

# 删除入站
delete_inbound() {
    echo -e "${YELLOW}删除入站配置${NC}"
    COUNT=$(jq '.inbounds | length' "$CONFIG_FILE")
    if [ "$COUNT" -eq 0 ]; then
        echo "没有入站配置"
        return
    fi

    echo "现有入站:"
    jq -r '.inbounds[] | "\(.tag) (Port: \(.port), Protocol: \(.protocol))"' "$CONFIG_FILE" | nl -w2 -s". "

    read -p "请输入要删除的序号 (0 取消): " IDX
    if [ "$IDX" == "0" ] || [ -z "$IDX" ]; then return; fi

    IDX=$((IDX-1))
    TAG=$(jq -r ".inbounds[$IDX].tag" "$CONFIG_FILE")
    
    if [ "$TAG" == "null" ]; then
        echo "无效序号"
        return
    fi

    $XRAY_BIN api rmi -s "$API_SERVER" "$TAG"
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}删除成功 (API)${NC}"
        tmp=$(mktemp)
        jq "del(.inbounds[$IDX])" "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
        echo -e "${GREEN}配置文件已更新${NC}"
    else
        echo -e "${RED}删除失败 (API) - 可能该 Tag 不存在于运行中的实例${NC}"
    fi
}

# 服务管理菜单
service_menu() {
    while true; do
        echo -e "${YELLOW}服务管理${NC}"
        echo "1. 启动服务"
        echo "2. 停止服务"
        echo "3. 重启服务"
        echo "0. 返回上级"
        read -p "请选择: " SVC_CHOICE
        case "$SVC_CHOICE" in
            1) start_service ;;
            2) stop_service ;;
            3) restart_service ;;
            0) break ;;
            *) echo "无效选择" ;;
        esac
    done
}

# 主菜单
show_menu() {
    check_api
    while true; do
        clear
        echo -e "${BLUE}Xray 管理脚本${NC}"
        echo "------------------------"
        echo "1. 添加入站"
        echo "2. 修改配置"
        echo "3. 查看配置"
        echo "4. 删除配置"
        echo "5. 服务管理"
        echo "6. 查看日志"
        echo "7. 流量统计"
        echo "8. 更新"
        echo "0. 退出"
        echo "------------------------"
        read -p "请选择: " CHOICE
        
        case "$CHOICE" in
            1)
                add_inbound
                read -n 1 -s -r -p "按任意键继续..."
                ;;
            2)
                modify_config
                read -n 1 -s -r -p "按任意键继续..."
                ;;
            3)
                view_link
                read -n 1 -s -r -p "按任意键继续..."
                ;;
            4)
                delete_inbound
                read -n 1 -s -r -p "按任意键继续..."
                ;;
            5)
                service_menu
                ;;
            6)
                view_log_menu
                ;;
            7)
                view_stats
                ;;
            8)
                install_xray
                read -n 1 -s -r -p "按任意键继续..."
                ;;
            0)
                exit 0
                ;;
            *)
                echo "无效选择"
                sleep 1
                ;;
        esac
    done
}

# 入口
if [ $# -gt 0 ]; then
    case "$1" in
        install)
            detect_system
            install_xray
            configure_xray
            setup_service
            start_service
            ;;
        start) start_service ;;
        stop) stop_service ;;
        restart) restart_service ;;
        *) echo "Usage: $0 {install|start|stop|restart}" ;;
    esac
else
    detect_system
    show_menu
fi
