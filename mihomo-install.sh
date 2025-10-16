#!/bin/bash
# mihomo 安装脚本
# 作者: su
# 版本: v1.0.0
# 日期: 2024年11月14日

set -e -o pipefail

# 定义颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # 无颜色

# 检测系统类型和架构
detect_system() {
    if [ -f /etc/alpine-release ]; then
        SYSTEM_TYPE="Alpine"
    elif command -v systemctl > /dev/null; then
        SYSTEM_TYPE="Debian"
    elif [ -f /etc/openwrt_release ]; then
        SYSTEM_TYPE="OpenWrt"
    elif [ -d /etc/init.d ]; then
        SYSTEM_TYPE="Init.d"
    else
        echo "不支持的初始化系统"
        exit 1
    fi

    ARCH_RAW=$(uname -m)
    case "${ARCH_RAW}" in
        'x86_64')    ARCH='amd64';;
        'x86' | 'i686' | 'i386')     ARCH='386';;
        'aarch64' | 'arm64') ARCH='arm64';;
        'armv7l')   ARCH='armv7';;
        's390x')    ARCH='s390x';;
        *)          echo "Unsupported architecture: ${ARCH_RAW}"; exit 1;;
    esac

    if [ "$SYSTEM_TYPE" == "Debian" ]; then
        SYSTEM_VERSION=$(cat /etc/os-release | grep VERSION_ID | cut -d'=' -f2 | tr -d '"')
    elif [ "$SYSTEM_TYPE" == "Alpine" ]; then
        SYSTEM_VERSION=$(cat /etc/alpine-release)
    elif [ "$SYSTEM_TYPE" == "OpenWrt" ]; then
        SYSTEM_VERSION=$(cat /etc/openwrt_release | grep DISTRIB_RELEASE | cut -d'=' -f2)
    else
        SYSTEM_VERSION="Unknown"
    fi
    echo -e "${GREEN}当前系统为 ${SYSTEM_TYPE}-${SYSTEM_VERSION}_${ARCH_RAW}${NC}"
}

# 设置时区
set_timezone() {
    if [ "$SYSTEM_TYPE" == "Alpine" ]; then
        echo -e "${YELLOW}检测到 Alpine 系统，使用 cp 和 echo 设置时区${NC}"
        apk add --no-cache tzdata
        cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
        echo "Asia/Shanghai" > /etc/timezone
        apk del tzdata
    else
        CURRENT_TIMEZONE=$(timedatectl show --property=Timezone --value)
        if [ "$CURRENT_TIMEZONE" != "Asia/Shanghai" ]; then
            echo -e "${YELLOW}设置时区为Asia/Shanghai${NC}"
            timedatectl set-timezone Asia/Shanghai
        fi
    fi
}

# 安装必要软件
install_software() {
    if [ "$SYSTEM_TYPE" == "Alpine" ]; then
        echo -e "${YELLOW}正在安装必要软件${NC}"
        apk add --no-cache curl nano grep gzip
    else
        echo -e "${YELLOW}正在安装必要软件${NC}"
        if command -v apt-get > /dev/null; then
            apt-get update
            apt-get install -y curl nano gzip
        elif command -v yum > /dev/null; then
            yum install -y curl nano gzip
        else
            echo -e "${RED}不支持的包管理器${NC}"
            exit 1
        fi
    fi
}

# 检测并下载 mihomo 版本
download_mihomo() {
    VERSION=$(curl -sL "https://gh.llkk.cc/https://api.github.com/repos/MetaCubeX/mihomo/releases/latest" | grep -oP '"tag_name": "\K(.*)(?=")')
    if [ -z "$VERSION" ]; then
        echo -e "${RED}无法获取最新版本号${NC}"
        exit 1
    fi
    echo -e "${GREEN}获取到的版本: ${VERSION}${NC}"

    DOWNLOAD_URL="https://gh.llkk.cc/https://github.com/MetaCubeX/mihomo/releases/download/${VERSION}/mihomo-linux-${ARCH}-${VERSION}.gz"
    echo "从 ${DOWNLOAD_URL} 下载 mihomo"
    curl -Lo mihomo.gz "${DOWNLOAD_URL}"
    echo -e "${YELLOW}Mihomo ${VERSION} 下载完成, 开始安装${NC}"
    gzip -d mihomo.gz
    chmod +x mihomo
    mv mihomo /usr/local/bin/
}

# 删除已有服务
remove_existing_service() {
    if [ -f /etc/systemd/system/mihomo.service ] || [ -f /etc/init.d/mihomo ] || [ -f /etc/rc.d/mihomo ]; then
        read -p "检测到已有的 mihomo 服务，是否删除？(y/n): " choice
        case "$choice" in
            y|Y )
                if [ -f /etc/systemd/system/mihomo.service ]; then
                    systemctl stop mihomo
                    systemctl disable mihomo
                    rm -f /etc/systemd/system/mihomo.service
                    systemctl daemon-reload
                fi

                if [ -f /etc/init.d/mihomo ]; then
                    /etc/init.d/mihomo stop
                    rm -f /etc/init.d/mihomo
                fi

                if [ -f /etc/rc.d/mihomo ]; then
                    /etc/rc.d/mihomo stop
                    rm -f /etc/rc.d/mihomo
                fi
                ;;
            n|N )
                echo -e "${YELLOW}保留已有的 mihomo 服务，退出安装。${NC}"
                exit 0
                ;;
            * )
                echo -e "${RED}无效的选择，退出安装。${NC}"
                exit 1
                ;;
        esac
    fi
}

# 配置 OpenRC 服务，Alpine 专用
configure_openrc() {
    echo "创建 OpenRC 服务文件"
    cat <<EOF > /etc/init.d/mihomo
#!/sbin/openrc-run
command="/usr/local/bin/mihomo"
command_args="-d /etc/mihomo"
command_background=true
pidfile="/var/run/mihomo.pid"
name="Mihomo Service"

depend() {
    need net
}

start_pre() {
    ebegin "等待 1 秒"
    sleep 1
    eend \$?
}
EOF
    chmod +x /etc/init.d/mihomo
    rc-update add mihomo default
    rc-service mihomo start
}

# 配置 systemd 服务，Debian系 专用
configure_systemd() {
    echo "创建 systemd 服务文件"
    cat <<EOF > /etc/systemd/system/mihomo.service
[Unit]
Description=mihomo Daemon, Another Clash Kernel.
After=network.target NetworkManager.service systemd-networkd.service iwd.service

[Service]
Type=simple
LimitNPROC=500
LimitNOFILE=1000000
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_RAW CAP_NET_BIND_SERVICE CAP_SYS_TIME CAP_SYS_PTRACE CAP_DAC_READ_SEARCH CAP_DAC_OVERRIDE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_RAW CAP_NET_BIND_SERVICE CAP_SYS_TIME CAP_SYS_PTRACE CAP_DAC_READ_SEARCH CAP_DAC_OVERRIDE
Restart=always
ExecStartPre=/usr/bin/sleep 1s
ExecStart=/usr/local/bin/mihomo -d /etc/mihomo
ExecReload=/bin/kill -HUP \$MAINPID

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl start mihomo
    systemctl enable mihomo
}

# 配置 init.d 服务，OpenWrt 和 Init.d 专用
configure_initd() {
    echo "创建 init.d 服务文件"
    cat <<EOF > /etc/init.d/mihomo
#!/bin/sh
### BEGIN INIT INFO
# Provides:          mihomo
# Required-Start:    \$network
# Required-Stop:     \$network
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Mihomo Service
### END INIT INFO

start() {
    echo "Starting mihomo"
    /usr/bin/sleep 1
    /usr/local/bin/mihomo -d /etc/mihomo &
}

stop() {
    echo "Stopping mihomo"
    pkill -f /usr/local/bin/mihomo
}

restart() {
    stop
    start
}

case "\$1" in
    start)
        start
        ;;
    stop)
        stop
        ;;
    restart)
        restart
        ;;
    *)
        echo "Usage: /etc/init.d/mihomo {start|stop|restart}"
        exit 1
        ;;
esac

exit 0
EOF
    chmod +x /etc/init.d/mihomo
    update-rc.d mihomo defaults
    /etc/init.d/mihomo start
}

# 内置配置
BUILTIN_CONFIG=$(cat <<EOF
port: 7890
socks-port: 7891
redir-port: 7892
tproxy-port: 7893
mixed-port: 1080
mode: rule
log-level: info
allow-lan: true     # 允许局域网连接
bind-address: "*"   # 绑定所有地址
ipv6: true      # IPv6 总开关
tcp-concurrent: true    # tcp 并发
unified-delay: true     # 统一延迟
find-process-mode: strict      # 进程匹配
global-client-fingerprint: random  # 随机指纹
global-ua: clash-verge/v1.8.10  # 下载资源 UA


proxies:
# clashMeta配置参考可以看看这个wiki
# https://wiki.metacubex.one

### 锚点
p: &p   # 订阅
  type: http
  interval: 1800
  health-check:
    enable: true
    url: https://www.gstatic.com/generate_204
    interval: 300
t : &t   # 节点
  type: url-test
  include-all: true
  url: https://www.gstatic.com/generate_204
  interval: 300
  skip-cert-verify: true  # 跳过 TLS 证书验证
  tolerance: 15 # 存在比当前节点延迟低15时切换
  lazy: true # 未选择此策略组时,不会进行检测
  sort:
    delay: asc
    speed: desc
r: &r    # 规则
  type: http
  format: yaml
  behavior: classical
  interval: 86400

# 代理提供(订阅)组
proxy-providers:
  1.机场1:  # 机场名
    url: ""
    path: ./proxy_providers/机场1.yaml
    #指定保存路径 非必填
    <<: *p
  
  2.机场2:  # 机场名
    url: ""
    path: ./proxy_providers/机场2.yaml
    proxy: DIRECT
    <<: *p


# 代理组
proxy-groups:
  - name: 🎯 总模式
    type: select
    proxies:
      - ♻️ 自动选择
      - 🚀 手动选择
      - 🇭🇰 香港节点
      - 🇸🇬 狮城节点
      - 🇹🇼 台湾节点
      - 🇯🇵 日本节点
      - 🇺🇸 美国节点
      - 🌎 其它地区
      - 🔃 负载均衡-轮询
      - 🔃 负载均衡-散列
      - 直连

# 策略组
  - name: ♻️ 自动选择
    <<: *t
    
  - name: 🚀 手动选择
    type: select
    <<: *t
      
  - name: 🇭🇰 香港节点
    filter: "(?i)🇭🇰|港|hk|hongkong|hong kong"
    <<: *t

  - name: 🇸🇬 狮城节点
    filter: "(?i)🇸🇬|新|sg|singapore"
    <<: *t

  - name: 🇹🇼 台湾节点
    filter: "(?i)🇹🇼|台|tw|taiwan"
    <<: *t

  - name: 🇯🇵 日本节点
    filter: "(?i)🇯🇵|日|jp|japan"
    <<: *t

  - name: 🇺🇸 美国节点
    filter: "(?i)🇺🇸|美|us|unitedstates|united states"
    <<: *t

  - name: 🌎 其它地区
    type: select
    filter: "(?i)^(?!.*(?:🇭🇰|🇯🇵|🇺🇸|🇸🇬|🇨🇳|港|hk|hongkong|台|tw|taiwan|日|jp|japan|新|sg|singapore|美|us|unitedstates)).*"
    <<: *t

  - name: 🔃 负载均衡-轮询
    type: load-balance
    strategy: round-robin
    filter: "🇭🇰|🇯🇵|🇸🇬|香港|hk|HK|hongkong|台|台湾|TW|taiwan|日本|jp|JP|新加坡|sg|韩国|中转|狮城|菲律宾"
    <<: *t

  - name: 🔃 负载均衡-散列
    type: load-balance
    strategy: consistent-hashing
    filter: "🇭🇰|🇯🇵|🇺🇸|🇸🇬|香港|hk|HK|hongkong|台|台湾|TW|taiwan|日本|jp|JP|新加坡|sg|美国|US"
    <<: *t
  
  - name: 直连
    type: select
    proxies:
      - DIRECT
      

# 分流规则提供(订阅)组
rule-providers:
  AWAvenue: # 秋风去广告
    behavior: domain
    path: ./rule_providers/AWAvenue-Ads-Rule-Clash.yaml
    url: "https://raw.githubusercontent.com/TG-Twilight/AWAvenue-Ads-Rule/main/Filters/AWAvenue-Ads-Rule-Clash.yaml"
    <<: *r
#  OpenAi:   # AI 服务
#    path: ./rule_providers/OpenAi.yaml
#    url: "https://raw.githubusercontent.com/ACL4SSR/ACL4SSR/master/Clash/Providers/Ruleset/OpenAi.yaml"
#    <<: *r
  直连:   # 自定义直连
    type: file
    behavior: domain
    format: text
    path: ./rule_providers/直连.yaml
    
  代理:   # 自定义代理
    type: file
    behavior: domain
    format: text
    path: ./rule_providers/代理.yaml

#   其他参数
sniffer:
  enable: true
  sniff:
    HTTP:
      ports: [80, 8080-8880]
    TLS:
      ports: [443, 8443]
    QUIC:
      ports: [443, 8443]
  skip-domain:
    - Mijia Cloud

profile:
  store-selected: true   # 存储 select 选择记录
  store-fake-ip: true    # 持久化 fake-ip
  
#   webui
external-controller: 0.0.0.0:9090
external-ui: webui
external-ui-name: xd
external-ui-url: "https://github.com/MetaCubeX/metacubexd/archive/refs/heads/gh-pages.zip"

#   geo
geox-url:
  geoip: "https://gcore.jsdelivr.net/gh/Loyalsoldier/geoip@release/geoip.dat"
  geosite: "https://gcore.jsdelivr.net/gh/Loyalsoldier/v2ray-rules-dat@release/geosite.dat"
  mmdb: "https://gcore.jsdelivr.net/gh/Loyalsoldier/geoip@release/Country.mmdb"
geodata-mode: true
geodata-loader: standard
geo-auto-update: true
geo-update-interval: 24

tun:
  enable: true
  device: tun
  stack: mixed
  dns-hijack:
    - any:53
    - tcp://any:53
  auto-route: true
  auto-redirect: true
  auto-detect-interface: true

dns:
  enable: true
  cache-algorithm: arc
  use-system-hosts: true
  ipv6: true
  listen: 0.0.0.0:1053
  enhanced-mode: redir-host  # fake-ip
  fake-ip-range: 198.18.0.1/16
  fake-ip-filter:
    - '+.lan'
    - '+.invalid.*'
    - '+.localhost'
    - '+.local.*'
    - '+.time.*'
    - '+.ntp.*'
    - '+.time.edu.cn'
    - '+.ntp.org.cn'
    - '+.pool.ntp.org'
    - '+.qpic.cn'
    - "+.stun.*"
    - "+.stun.*.*"
    - "+.stun.*.*.*"
    - '+.sushen.tk'
    - localhost.ptlogin2.qq.com
    - dns.msftncsi.com
    - www.msftncsi.com
    - www.msftconnecttest.com
    - time1.cloud.tencent.com
    
  nameserver:
    - https://1.0.0.1/dns-query
    - https://8.8.8.8/dns-query
    - https://208.67.222.222/dns-query
  proxy-server-nameserver:
    - https://119.29.29.29/dns-query
    - https://223.5.5.5/dns-query
  nameserver-policy:
    "geosite:category-ads-all":
      - rcode://success
  direct-nameserver:
    - system
    - 119.29.29.29
    - 223.5.5.5
  direct-nameserver-follow-policy: true


# 分流规则
rules:
  - AND,(AND,(DST-PORT,443),(NETWORK,UDP)),(NOT,((GEOSITE,CN))),REJECT-DROP # 禁用quic(不包括国内)
  - RULE-SET,AWAvenue,REJECT-DROP
#  - RULE-SET,OpenAi,🇸🇬 狮城节点
  - RULE-SET,直连,DIRECT
  - RULE-SET,代理,🎯 总模式
#  - IP-CIDR,192.168.0.0/16,DIRECT,no-resolve
  
  - GEOSITE,openai,🇸🇬 狮城节点
  
  - GEOSITE,ehentai,🎯 总模式
  - GEOSITE,github,🎯 总模式
  - GEOSITE,twitter,🎯 总模式
  - GEOSITE,youtube,🎯 总模式
  - GEOSITE,google,🎯 总模式
  - GEOSITE,telegram,🎯 总模式
  - GEOSITE,netflix,🎯 总模式
  - GEOSITE,bahamut,🎯 总模式
  - GEOSITE,spotify,🎯 总模式
  - GEOSITE,bilibili,DIRECT
  - GEOSITE,CN,DIRECT
  - GEOSITE,private,DIRECT
  - GEOSITE,category-ads-all,REJECT-DROP
  
  - GEOIP,google,🎯 总模式
  - GEOIP,netflix,🎯 总模式
  - GEOIP,telegram,🎯 总模式
  - GEOIP,twitter,🎯 总模式
  - GEOIP,CN,DIRECT,no-resolve
  - GEOIP,private,DIRECT,no-resolve
  
  - MATCH,🎯 总模式
EOF
)

# 询问是否使用内置配置
ask_builtin_config() {
    read -p "是否使用内置配置？(y/n): " choice
    case "$choice" in
        y|Y )
            echo -e "${YELLOW}使用内置配置，请在配置中添加订阅${NC}"
            mkdir /etc/mihomo/
            echo "$BUILTIN_CONFIG" > /etc/mihomo/config.yaml
            ;;
        n|N )
            echo -e "${YELLOW}不使用内置配置，请上传配置到/etc/mihomo/config.yaml${NC}"
            ;;
        * )
            echo -e "${RED}无效的选择，退出安装。${NC}"
            exit 1
            ;;
    esac
}

# 启用系统转发
enable_ip_forwarding() {
    echo 'net.ipv4.ip_forward = 1' | tee -a /etc/sysctl.conf
    echo 'net.ipv6.conf.all.forwarding = 1' | tee -a /etc/sysctl.conf
    sysctl -p
    if [ "$SYSTEM_TYPE" == "Alpine" ]; then
        rc-update add sysctl
    fi
}

# 主函数
main() {
    detect_system
    set_timezone
    install_software
    remove_existing_service
    download_mihomo
    ask_builtin_config
   # enable_ip_forwarding

    case "$SYSTEM_TYPE" in
        "Alpine")
            configure_openrc
            ;;
        "Debian")
            configure_systemd
            ;;
        "OpenWrt" | "Init.d")
            configure_initd
            ;;
    esac

    echo -e "${GREEN}脚本执行完毕。${NC}"
}

main