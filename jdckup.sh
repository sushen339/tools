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
readonly VENV_NAME="jdckup_env"
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
    log_info "更新包列表..."
    apt update || {
        log_error "更新包列表失败"
        exit 1
    }
    
    # 基础包列表（不包含 venv，按需安装）
    local base_packages=(
        "git"
        "python3-pip"
    )
    
    # 可选包（安装失败不影响）
    local optional_packages=(
        "python3-opencv"
    )
    
    # 安装基础包
    log_info "安装必要的系统包: ${base_packages[*]}"
    apt install -y "${base_packages[@]}" 2>&1 | tee -a "$LOG_FILE"
    check_result "基础系统包安装失败"
    
    # 尝试安装可选包
    log_info "尝试安装可选包: ${optional_packages[*]}"
    for pkg in "${optional_packages[@]}"; do
        if apt install -y "$pkg" 2>&1 | tee -a "$LOG_FILE"; then
            log_success "已安装: $pkg"
        else
            log_warning "跳过可选包: $pkg (可能不可用)"
        fi
    done
    
    log_success "系统包安装完成"
}

# 安装 venv 包（仅在需要时）
install_venv_package() {
    log_info "检测到缺少 venv 模块，尝试安装..."
    
    # 尝试安装 python3-venv
    if apt install -y python3-venv 2>&1 | tee -a "../$LOG_FILE"; then
        log_success "python3-venv 安装成功"
        return 0
    else
        log_error "python3-venv 安装失败，请手动安装"
        return 1
    fi
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
    
    git clone --depth=1 "$REPO_URL" 2>&1 | tee -a "$LOG_FILE"
    check_result "克隆仓库失败"
    
    log_success "代码仓库克隆完成"
}

# 创建和配置虚拟环境
setup_virtual_environment() {
    log_info "设置 Python 虚拟环境..."
    
    cd "$PROJECT_DIR" || {
        log_error "无法进入目录 $PROJECT_DIR"
        exit 1
    }
    
    # 检查 Python 命令
    if [ -z "$PYTHON_CMD" ] || ! command_exists "$PYTHON_CMD"; then
        log_error "Python 命令不可用: $PYTHON_CMD"
        exit 1
    fi
    
    # 创建虚拟环境
    if [ -d "$VENV_NAME" ]; then
        log_warning "虚拟环境 $VENV_NAME 已存在，将重新创建"
        rm -rf "$VENV_NAME"
    fi
    
    log_info "使用 $PYTHON_CMD 创建虚拟环境..."
    
    # 尝试创建虚拟环境
    if "$PYTHON_CMD" -m venv "$VENV_NAME" 2>&1 | tee -a "../$LOG_FILE"; then
        log_success "虚拟环境创建完成"
    else
        log_warning "虚拟环境创建失败，可能缺少 venv 模块"
        
        # 尝试安装 venv 包
        install_venv_package || {
            log_error "无法安装 venv 模块"
            exit 1
        }
        
        # 再次尝试创建虚拟环境
        log_info "重新尝试创建虚拟环境..."
        "$PYTHON_CMD" -m venv "$VENV_NAME" 2>&1 | tee -a "../$LOG_FILE"
        check_result "创建虚拟环境失败（已安装 venv 模块）"
        
        log_success "虚拟环境创建完成"
    fi
}

# 安装 Python 依赖
install_python_dependencies() {
    log_info "安装 Python 依赖包..."
    
    # 激活虚拟环境
    source "$VENV_NAME/bin/activate" || {
        log_error "激活虚拟环境失败"
        exit 1
    }
    
    # 升级 pip
    log_info "升级 pip..."
    pip install --upgrade pip 2>&1 | tee -a "../$LOG_FILE"
    
    # 安装依赖
    if [ ! -f "requirements.txt" ]; then
        log_error "requirements.txt 文件不存在"
        exit 1
    fi
    
    log_info "安装项目依赖..."
    pip install -r requirements.txt 2>&1 | tee -a "../$LOG_FILE"
    check_result "安装 Python 依赖失败"
    
    log_success "Python 依赖安装完成"
}

# 安装 Playwright 和浏览器
install_playwright() {
    log_info "安装 Playwright 浏览器..."
    
    # 确保虚拟环境已激活
    if [ -z "${VIRTUAL_ENV:-}" ]; then
        source "$VENV_NAME/bin/activate"
    fi
    
    # 安装浏览器依赖
    log_info "安装 Playwright 系统依赖..."
    playwright install-deps 2>&1 | tee -a "../$LOG_FILE"
    check_result "安装 Playwright 系统依赖失败"
    
    # 安装 Chromium 浏览器
    log_info "安装 Chromium 浏览器..."
    playwright install chromium 2>&1 | tee -a "../$LOG_FILE"
    check_result "安装 Chromium 浏览器失败"
    
    log_success "Playwright 安装完成"
}

# 生成配置文件
generate_config() {
    log_info "生成配置文件..."
    
    # 确保虚拟环境已激活
    if [ -z "${VIRTUAL_ENV:-}" ]; then
        source "$VENV_NAME/bin/activate"
    fi
    
    if [ ! -f "make_config.py" ]; then
        log_error "make_config.py 文件不存在"
        exit 1
    fi
    
    python make_config.py 2>&1 | tee -a "../$LOG_FILE"
    check_result "生成配置文件失败"
    
    log_success "配置文件生成完成"
}

# 显示安装后信息
show_post_install_info() {
    echo ""
    echo "============================================"
    log_success "$SCRIPT_NAME 安装完成！"
    echo "============================================"
    echo ""
    echo "项目目录: $(pwd)"
    echo "虚拟环境: $VENV_NAME"
    echo "日志文件: ../$LOG_FILE"
    echo ""
    echo "使用说明："
    echo "1. 进入项目目录: cd $PROJECT_DIR"
    echo "2. 激活虚拟环境: source $VENV_NAME/bin/activate"
    echo "3. 运行程序: python main.py"
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
    setup_virtual_environment
    install_python_dependencies
    install_playwright
    generate_config
    show_post_install_info
    
    log_success "所有安装步骤完成！"
}

# 执行主函数
main "$@"


