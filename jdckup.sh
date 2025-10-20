#!/bin/bash
# jdckup.sh - 京东Cookie自动更新工具安装脚本
# 描述: 自动化安装和配置 AutoUpdateJdCookie 项目

set -euo pipefail  # 严格模式：遇到错误立即退出，未定义变量报错，管道命令失败即退出

# ============================================
# 配置变量
# ============================================
readonly SCRIPT_NAME="JdCkup Installer"
readonly REPO_URL="https://github.com/icepage/AutoUpdateJdCookie.git"
readonly PROJECT_DIR="AutoUpdateJdCookie"
PYTHON_CMD=""  # 动态检测的 Python 命令
LOG_FILE="jdckup_install_$(date +%Y%m%d_%H%M%S).log"
readonly LOG_FILE

# 颜色定义
readonly COLOR_RED='\033[0;31m'
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_YELLOW='\033[1;33m'
readonly COLOR_BLUE='\033[0;34m'
readonly COLOR_RESET='\033[0m'

# ============================================
# 工具函数
# ============================================

# 日志函数
log_info() {
    echo -e "${COLOR_BLUE}[INFO]${COLOR_RESET} $(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${COLOR_GREEN}[SUCCESS]${COLOR_RESET} $(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${COLOR_YELLOW}[WARNING]${COLOR_RESET} $(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${COLOR_RED}[ERROR]${COLOR_RESET} $(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$LOG_FILE" >&2
}

# 带进度条的后台执行
run_with_progress() {
    local description=$1
    local command=$2
    local log_file=$3
    
    # 在后台执行命令
    eval "$command" >> "$log_file" 2>&1 &
    local pid=$!
    
    # 显示进度动画
    local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0
    
    echo -n "$description: "
    while kill -0 $pid 2>/dev/null; do
        i=$(( (i+1) % 10 ))
        printf "\r%s: %b%s%b 处理中..." "$description" "${COLOR_BLUE}" "${spin:$i:1}" "${COLOR_RESET}"
        sleep 0.1
    done
    
    # 等待进程完成
    wait $pid
    local exit_code=$?
    
    # 清除行并显示最终状态
    if [ $exit_code -eq 0 ]; then
        printf "\r%s: %b✓%b 已完成    \n" "$description" "${COLOR_GREEN}" "${COLOR_RESET}"
    else
        printf "\r%s: %b✗%b 失败      \n" "$description" "${COLOR_RED}" "${COLOR_RESET}"
    fi
    
    return $exit_code
}

# 检查命令是否存在
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# 检查上一个命令的执行结果
check_result() {
    if [ $? -ne 0 ]; then
        log_error "$1"
        exit 1
    fi
}

# ============================================
# 安装函数
# ============================================

# 检测可用的 Python 版本
detect_python_version() {
    log_info "检测系统 Python 版本..."
    
    # 按优先级检测 Python 版本
    local python_candidates=("python3.13" "python3.12" "python3.11" "python3.10" "python3.9" "python3")
    
    for py_cmd in "${python_candidates[@]}"; do
        if command_exists "$py_cmd"; then
            local py_version
            py_version=$($py_cmd --version 2>&1 | grep -oP '\d+\.\d+')
            
            # Python 3.8+ 支持
            if [[ $(echo "$py_version >= 3.8" | bc -l 2>/dev/null || echo "1") -eq 1 ]]; then
                PYTHON_CMD="$py_cmd"
                log_success "检测到 Python: $py_cmd (版本 $py_version)"
                return 0
            fi
        fi
    done
    
    log_error "未找到可用的 Python 3.8+ 版本"
    exit 1
}

# 检查系统依赖
check_system_dependencies() {
    log_info "检查系统依赖..."
    
    # 检查必要的命令
    if ! command_exists apt; then
        log_error "此脚本仅支持基于 apt 的系统（Debian/Ubuntu）"
        exit 1
    fi
    
    # 检查是否有 root 权限
    if [ "$EUID" -ne 0 ]; then
        log_warning "建议使用 root 权限运行此脚本"
        read -p "是否继续？(y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
    
    log_success "系统依赖检查完成"
}

# 安装系统包
install_system_packages() {
    log_info "开始安装系统包..."
    
    # 更新包列表
    echo ""
    run_with_progress "📦 更新 APT 包列表" "apt update" "$LOG_FILE" || {
        log_error "更新包列表失败"
        exit 1
    }
    
    # 基础包列表（不包含 venv，按需安装）
    local base_packages=(
        "git"
        "python3-pip"
    )
    
    # 安装基础包
    echo ""
    run_with_progress "📦 安装系统包 (${base_packages[*]})" "apt install -y ${base_packages[*]}" "$LOG_FILE"
    check_result "基础系统包安装失败"
    
    echo ""
    log_success "系统包安装完成"
}

# 克隆代码仓库
clone_repository() {
    log_info "克隆代码仓库..."
    
    if [ -d "$PROJECT_DIR" ]; then
        log_warning "目录 $PROJECT_DIR 已存在"
        read -p "是否删除并重新克隆？(y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rm -rf "$PROJECT_DIR"
            log_info "已删除旧目录"
        else
            log_info "跳过克隆步骤"
            return 0
        fi
    fi
    
    echo ""
    run_with_progress "📥 克隆 GitHub 仓库" "git clone --depth=1 $REPO_URL" "$LOG_FILE"
    check_result "克隆仓库失败"
    
    echo ""
    log_success "代码仓库克隆完成"
}

# 安装 Python 依赖
install_python_dependencies() {
    log_info "安装 Python 依赖包..."
    
    # 进入项目目录
    cd "$PROJECT_DIR" || {
        log_error "无法进入目录 $PROJECT_DIR"
        exit 1
    }
    
    # 系统级安装模式：使用 --break-system-packages
    local pip_args="--break-system-packages"
    
    # 升级 pip
    echo ""
    run_with_progress "📚 升级 pip" "pip install --upgrade pip $pip_args" "../$LOG_FILE"
    
    # 安装项目依赖
    if [ ! -f "requirements.txt" ]; then
        log_error "requirements.txt 文件不存在"
        exit 1
    fi
    
    echo ""
    run_with_progress "📚 安装项目依赖" "pip install -r requirements.txt $pip_args" "../$LOG_FILE"
    check_result "安装 Python 依赖失败"
    
    # 安装 opencv-python
    echo ""
    run_with_progress "📚 安装 opencv-python" "pip install opencv-python $pip_args" "../$LOG_FILE"
    check_result "安装 opencv-python 失败"
    
    echo ""
    log_success "Python 依赖安装完成"
}

# 安装 Playwright 和浏览器
install_playwright() {
    log_info "安装 Playwright 浏览器..."
    
    # 安装浏览器依赖
    echo ""
    run_with_progress "🌐 安装 Playwright 系统依赖" "playwright install-deps" "../$LOG_FILE"
    check_result "安装 Playwright 系统依赖失败"
    
    # 安装 Chromium 浏览器
    echo ""
    run_with_progress "🌐 安装 Chromium 浏览器" "playwright install chromium" "../$LOG_FILE"
    check_result "安装 Chromium 浏览器失败"
    
    echo ""
    log_success "Playwright 安装完成"
}

# 生成配置文件
generate_config() {
    log_info "生成配置文件..."
    
    if [ ! -f "make_config.py" ]; then
        log_error "make_config.py 文件不存在"
        exit 1
    fi
    
    echo ""
    echo "============================================"
    echo "⚙️  开始配置向导（需要交互式输入）"
    echo "============================================"
    echo ""
    
    # 交互式运行配置脚本（前台执行）
    python make_config.py 2>&1 | tee -a "../$LOG_FILE"
    
    if [ ${PIPESTATUS[0]} -eq 0 ]; then
        echo ""
        log_success "配置文件生成完成"
    else
        echo ""
        log_error "生成配置文件失败"
        exit 1
    fi
}

# 显示安装后信息
show_post_install_info() {
    echo ""
    echo "============================================"
    log_success "$SCRIPT_NAME 安装完成！"
    echo "============================================"
    echo ""
    echo "项目目录: $(pwd)"
    echo "Python 版本: $PYTHON_CMD"
    echo "日志文件: ../$LOG_FILE"
    echo ""
    echo "使用说明："
    echo "1. 进入项目目录: cd $PROJECT_DIR"
    echo "2. 直接运行程序: python main.py"
    echo ""
    echo "Crontab 定时任务示例："
    echo "0 3,4 * * * cd $(pwd) && $PYTHON_CMD main.py --mode cron"
    echo ""
    echo "============================================"
}

# ============================================
# 主函数
# ============================================
main() {
    log_info "开始执行 $SCRIPT_NAME..."
    log_info "日志文件: $LOG_FILE"
    
    # 执行安装步骤
    check_system_dependencies
    detect_python_version
    install_system_packages
    clone_repository
    install_python_dependencies
    install_playwright
    generate_config
    show_post_install_info
    
    log_success "所有安装步骤完成！"
}

# 执行主函数
main "$@"
