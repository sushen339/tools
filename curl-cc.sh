#!/usr/bin/env bash
# curl-cc.sh
# 自动访问指定网站，模拟真实浏览器行为
# 用法: ./curl-cc.sh [-v|--verbose] [-h|--help]

set -o pipefail

# 配置选项
VERBOSE=0
SCRIPT_NAME=$(basename "$0")

# 显示帮助信息
show_help() {
  cat << EOF
用法: $SCRIPT_NAME [选项]

描述:
  自动访问指定网站，模拟真实浏览器行为进行签到或访问

选项:
  -v, --verbose    显示详细输出信息
  -h, --help       显示此帮助信息

示例:
  $SCRIPT_NAME           # 静默模式运行
  $SCRIPT_NAME -v        # 详细模式运行

EOF
  exit 0
}

# 日志函数
log_info() {
  if [ "$VERBOSE" -eq 1 ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $*"
  fi
}

log_error() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" >&2
}

# 解析命令行参数
while [ $# -gt 0 ]; do
  case "$1" in
    -v|--verbose)
      VERBOSE=1
      shift
      ;;
    -h|--help)
      show_help
      ;;
    *)
      echo "未知选项: $1"
      echo "使用 -h 或 --help 查看帮助"
      exit 1
      ;;
  esac
done

VISIT_PATH="/short_code/visit_short_code_proc_ajax.php?ref="
CLICK_PATH="/short_code/click_short_code_proc_ajax.php?c=c"

# Referer 来源列表（最常用的社交媒体和平台）
REFERERS=(
  # 主流社交媒体
  "https://www.facebook.com/"
  "https://twitter.com/"
  "https://www.instagram.com/"
  "https://www.tiktok.com/"
  "https://www.reddit.com/"
  
  # 视频平台
  "https://www.youtube.com/"
  
  # 搜索引擎
  "https://www.google.com/"
  
  # 通讯工具
  "https://t.me/"
)

# User-Agent 列表（2025年最新版本，最常用设备）
UAS=(
  # === Android 设备 ===
  # Samsung Galaxy (市场占有率最高)
  "Mozilla/5.0 (Linux; Android 14; SM-S24 Ultra) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36"
  "Mozilla/5.0 (Linux; Android 14; SM-S23) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36"
  
  # Google Pixel
  "Mozilla/5.0 (Linux; Android 14; Pixel 8 Pro) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.6723.58 Mobile Safari/537.36"
  
  # === iOS 设备 ===
  # iPhone - Safari (最常用)
  "Mozilla/5.0 (iPhone; CPU iPhone OS 18_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.1 Mobile/15E148 Safari/604.1"
  "Mozilla/5.0 (iPhone; CPU iPhone OS 17_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.7 Mobile/15E148 Safari/604.1"
  
  # iPhone - Chrome
  "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/130.0.6723.90 Mobile/15E148 Safari/604.1"
  
  # === Windows 桌面 ===
  # Chrome (最常用)
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36"
  
  # Edge
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36 Edg/130.0.2849.68"
  
  # === macOS 桌面 ===
  # Safari
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
  
  # Chrome on Mac
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36"
)

hosts=( "org.cc.cc" "sky.cc.cc" )

# 生成随机 ref 参数（30% 概率为空，70% 概率为 6-12 位随机字符串）
rand_ref() {
  if [ $((RANDOM % 10)) -lt 3 ]; then
    printf ""
  else
    local len=$((6 + RANDOM % 7))
    # 使用更便携的随机字符串生成方式
    if [ -r /dev/urandom ]; then
      head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c "$len"
    else
      # 备用方案（如果 /dev/urandom 不可用）
      < /dev/urandom tr -dc 'a-zA-Z0-9' | head -c "$len"
    fi
  fi
}

# 随机选择一个 User-Agent
choose_ua() {
  echo "${UAS[$((RANDOM % ${#UAS[@]}))]}"
}

# 随机选择一个 Referer
choose_referer() {
  echo "${REFERERS[$((RANDOM % ${#REFERERS[@]}))]}"
}

# 根据地理位置获取 Accept-Language
get_accept_language() {
  local country_code=""
  
  # 尝试从 ipinfo.io 获取国家代码（设置超时 3 秒）
  if command -v curl &> /dev/null; then
    country_code=$(curl -s --max-time 3 https://ipinfo.io/country 2>/dev/null | tr -d '[:space:]')
  fi
  
  # 根据国家代码返回对应的 Accept-Language
  case "$country_code" in
    CN|HK|TW|MO)  # 中国、香港、台湾、澳门
      echo "zh-CN,zh;q=0.9,en;q=0.8"
      ;;
    JP)  # 日本
      echo "ja,en;q=0.9"
      ;;
    KR)  # 韩国
      echo "ko,en;q=0.9"
      ;;
    ES|MX|AR|CO|CL|PE|VE)  # 西班牙语国家
      echo "es,en;q=0.9"
      ;;
    FR|BE|CH)  # 法语国家
      echo "fr,en;q=0.9"
      ;;
    DE|AT)  # 德语国家
      echo "de,en;q=0.9"
      ;;
    RU|BY|KZ|UA)  # 俄语国家
      echo "ru,en;q=0.9"
      ;;
    PT|BR)  # 葡萄牙语国家
      echo "pt,en;q=0.9"
      ;;
    IT)  # 意大利
      echo "it,en;q=0.9"
      ;;
    TR)  # 土耳其
      echo "tr,en;q=0.9"
      ;;
    SA|AE|EG|IQ|JO)  # 阿拉伯语国家
      echo "ar,en;q=0.9"
      ;;
    IN)  # 印度
      echo "en-IN,hi;q=0.9,en;q=0.8"
      ;;
    *)  # 默认英文（包括 US, GB, CA, AU, SG 等）
      echo "en-US,en;q=0.9"
      ;;
  esac
}

# 执行访问请求
make_visit_request() {
  local host="$1"
  local ref_url="$2"        # URL 参数中的 ref（referral site URL）
  local ua="$3"
  local referer="https://${host}/"  # HTTP Header 中的 Referer 固定为自身
  
  # 构建完整 URL，ref 参数为 referral site 的完整 URL
  local url="https://${host}${VISIT_PATH}${ref_url}"
  
  log_info "正在访问: ${host}"
  log_info "URL: ${url}"
  log_info "Referer Header: ${referer}"
  log_info "User-Agent: ${ua}"
  
  # 使用 || true 确保即使 curl 失败也不会导致脚本退出
  local curl_exit_code=0
  curl -s -S -X GET "$url" \
    -H "Host: ${host}" \
    -H "Connection: keep-alive" \
    -H "Accept: */*" \
    -H "X-Requested-With: XMLHttpRequest" \
    -H "User-Agent: ${ua}" \
    -H "Content-Type: charset=utf-8" \
    -H "Referer: ${referer}" \
    -H "Accept-Encoding: gzip, deflate" \
    -H "Accept-Language: ${ACCEPT_LANG}" \
    --compressed -o /dev/null --max-time ${MAX_TIME} || curl_exit_code=$?
  
  if [ $curl_exit_code -eq 0 ]; then
    log_info "✓ ${host} 访问成功"
    return 0
  else
    log_error "✗ ${host} 访问失败 (curl 退出码: ${curl_exit_code})"
    return 1
  fi
}

# 执行电话点击请求
make_click_request() {
  local host="$1"
  local ua="$2"
  local referer="https://${host}/"  # HTTP Header 中的 Referer 固定为自身
  
  # 构建完整 URL
  local url="https://${host}${CLICK_PATH}"
  
  log_info "  ├─ 电话点击统计"
  log_info "  ├─ URL: ${url}"
  
  # 使用 || true 确保即使 curl 失败也不会导致脚本退出
  local curl_exit_code=0
  curl -s -S -X GET "$url" \
    -H "Host: ${host}" \
    -H "Connection: keep-alive" \
    -H "Accept: */*" \
    -H "X-Requested-With: XMLHttpRequest" \
    -H "User-Agent: ${ua}" \
    -H "Content-Type: charset=utf-8" \
    -H "Referer: ${referer}" \
    -H "Accept-Encoding: gzip, deflate" \
    -H "Accept-Language: ${ACCEPT_LANG}" \
    --compressed -o /dev/null --max-time ${MAX_TIME} || curl_exit_code=$?
  
  if [ $curl_exit_code -eq 0 ]; then
    log_info "  └─ ✓ 电话点击记录成功"
    return 0
  else
    log_error "  └─ ✗ 电话点击记录失败 (curl 退出码: ${curl_exit_code})"
    return 1
  fi
}

MAX_TIME=15
SLEEP_MIN=3
SLEEP_MAX=6

# 主执行流程
main() {
  log_info "==================== 开始执行 ===================="
  log_info "目标主机数量: ${#hosts[@]}"
  
  local success_count=0
  local fail_count=0
  
  # 获取地理位置对应的语言
  ACCEPT_LANG="$(get_accept_language)"
  log_info "Accept-Language: ${ACCEPT_LANG}"
  
  # 为本次执行生成统一的 UA（所有请求使用同一个 UA）
  local ua
  ua="$(choose_ua)"
  
  for host in "${hosts[@]}"; do
    local ref_url=""
    
    # 33% 概率直接访问（unknown），67% 概率从社交媒体跳转
    if [ $((RANDOM % 3)) -eq 0 ]; then
      # 直接访问，ref 参数为空
      ref_url=""
      log_info "直接访问（referral site: unknown）"
    else
      # 从随机社交媒体跳转
      ref_url="$(choose_referer)"
      log_info "referral site: ${ref_url}"
    fi
    
    # 执行访问请求，不管成功失败都继续
    if make_visit_request "$host" "$ref_url" "$ua"; then
      ((success_count++))
      
      # 20% 概率点击电话统计
      if [ $((RANDOM % 5)) -eq 0 ]; then
        log_info "  ↳ 触发电话点击（20% 概率）"
        make_click_request "$host" "$ua" || true
      fi
    else
      ((fail_count++))
    fi
    
    # 在请求之间随机等待（最后一个请求除外）
    if [ "$host" != "${hosts[-1]}" ]; then
      local sleep_sec=$((SLEEP_MIN + RANDOM % (SLEEP_MAX - SLEEP_MIN + 1)))
      local ms=$((RANDOM % 1000))
      local sleep_time
      
      # 检查 awk 是否可用
      if command -v awk &> /dev/null; then
        sleep_time=$(awk "BEGIN{printf \"%.3f\", ${sleep_sec} + ${ms}/1000}")
      else
        sleep_time="${sleep_sec}"
      fi
      
      log_info "等待 ${sleep_time} 秒..."
      sleep "$sleep_time"
    fi
  done
  
  log_info "==================== 执行完成 ===================="
  log_info "成功: ${success_count}, 失败: ${fail_count}"
  
  # 如果有失败的请求，返回非零退出码
  if [ "$fail_count" -gt 0 ]; then
    exit 1
  fi
}

# 执行主函数
main
