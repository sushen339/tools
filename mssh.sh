#!/bin/bash

# mssh - SSH 管理工具

# 配置文件路径
CONFIG_FILE="$HOME/.mssh.conf"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
ORANGE='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Emoji 定义
SERVER_EMOJI="🌐"
KEY_EMOJI="🔑"
PASSWORD_EMOJI="🔒"
CONNECT_EMOJI="🔌"
SUCCESS_EMOJI="✅"
ERROR_EMOJI="❌"
WARNING_EMOJI="⚠️"
INFO_EMOJI="𝒊"
FORWARD_EMOJI="📡"

# 信号处理
graceful_exit() {
    echo -e "\n${INFO_EMOJI} ${CYAN}  正在退出 mssh...${NC}"
    
    # 检查是否有活跃的端口转发
    local active_forwards
    active_forwards=$(get_section "active_forwards")
    
    if [ -n "$active_forwards" ]; then
        echo -e "${WARNING_EMOJI} ${YELLOW}检测到活跃的端口转发进程${NC}"
        echo -e "${INFO_EMOJI} ${CYAN}这些进程将继续在后台运行${NC}"
        echo -e "${CYAN}您可以随时重新启动 mssh 来管理它们${NC}"
        echo
        
        # 显示活跃的转发
        local i=1
        while IFS='|' read -r rule_name local_port pid user_host port server_alias remote_host remote_port; do
            [ -z "$rule_name" ] && continue
            printf "  ${GREEN}%2d.${NC} ${FORWARD_EMOJI} ${YELLOW}%s${NC} (PID:%s)\n" "$i" "$rule_name" "$pid"
            ((i++))
        done <<< "$active_forwards"
    fi
    
    echo -e "\n🔚 脚本已退出"
    exit 0
}

# 设置信号处理
trap graceful_exit SIGINT SIGTERM SIGQUIT

# 密码加密函数
encrypt_password() {
    local password="$1"
    [ -z "$password" ] && return
    
    # 简单的字符位移 + base64
    local encrypted
    encrypted=$(echo "$password" | tr 'A-Za-z0-9' 'N-ZA-Mn-za-m5-90-4' | base64 -w 0)
    echo "ENC:$encrypted"
}

# 密码解密函数  
decrypt_password() {
    local encrypted="$1"
    [ -z "$encrypted" ] && return
    
    # 解密格式：ENC:base64data
    if [[ "$encrypted" =~ ^ENC: ]]; then
        local encrypted_data="${encrypted#ENC:}"
        echo "$encrypted_data" | base64 -d | tr 'N-ZA-Mn-za-m5-90-4' 'A-Za-z0-9'
    fi
}

# 安全读取函数
safe_read() {
    local prompt="$1"
    local var_name="$2"
    local response
    
    if ! read -r -p "$prompt" response; then
        graceful_exit
    fi
    
    if [ -n "$var_name" ]; then
        eval "$var_name=\"$response\""
    fi
}

# 检查 sshpass
check_sshpass() {
    if ! command -v sshpass >/dev/null 2>&1; then
        echo -e "${ERROR_EMOJI} ${RED}未找到 sshpass。某些功能可能不可用。${NC}"
        echo -e "${INFO_EMOJI} ${YELLOW}可以运行以下命令安装：${NC}"
        echo -e "  ${CYAN}Ubuntu/Debian: sudo apt install sshpass${NC}"
        echo -e "  ${CYAN}CentOS/RHEL: sudo yum install sshpass${NC}"
    fi
}

# 初始化配置文件
init_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        cat > "$CONFIG_FILE" << 'EOF'
# mssh 配置文件
# 格式说明：
# [servers] 部分：alias|user@host|port|keypath|encrypted_password
# [port_forwards] 部分：server_alias|rule_name|local_port|remote_host|remote_port|user@host|port|keypath|encrypted_password
# [active_forwards] 部分：rule_name|local_port|pid|user@host|port|server_alias|remote_host|remote_port

[servers]

[port_forwards]

[active_forwards]

EOF
        echo -e "${SUCCESS_EMOJI} ${GREEN}配置文件已创建: $CONFIG_FILE${NC}"
    fi
}

# 获取配置文件中的特定部分
get_section() {
    local section="$1"
    local config_file="${2:-$CONFIG_FILE}"
    
    awk -v section="[$section]" '
    $0 == section { in_section = 1; next }
    /^\[.*\]$/ { in_section = 0; next }
    in_section && NF > 0 && !/^#/ { print }
    ' "$config_file"
}

# 格式化端口转发显示
format_forward_display() {
    local num="$1"
    local rule_name="$2"
    local local_port="$3"
    local server_alias="$4"
    local remote_host="$5"
    local remote_port="$6"
    local pid="$7"
    
    local pid_text=""
    [ -n "$pid" ] && pid_text=" PID:$pid"
    
    if [ "$remote_host" = "127.0.0.1" ]; then
        printf "  ${GREEN}%2d.${NC} ${FORWARD_EMOJI} ${YELLOW}%s${NC} (本地:%s -> %s:%s)%s\n" \
               "$num" "$rule_name" "$local_port" "$server_alias" "$remote_port" "$pid_text"
    else
        printf "  ${GREEN}%2d.${NC} ${FORWARD_EMOJI} ${YELLOW}%s${NC} (本地:%s -> %s -> %s:%s)%s\n" \
               "$num" "$rule_name" "$local_port" "$server_alias" "$remote_host" "$remote_port" "$pid_text"
    fi
}

# 显示服务器列表
show_servers() {
    echo -e "${CYAN}已保存的服务器:${NC}"
    echo -e "${CYAN}---------------${NC}"
    
    local servers
    servers=$(get_section "servers")
    if [ -z "$servers" ]; then
        echo -e "  ${YELLOW}暂无服务器${NC}"
        return 0
    fi
    
    local i=1
    while IFS='|' read -r alias_name user_host port key_path password; do
        [ -z "$alias_name" ] && continue
        
        # 显示密码和密钥状态
        local has_password=""
        local has_key=""
        [ -n "$password" ] && has_password="${PASSWORD_EMOJI}"
        [ -n "$key_path" ] && [ -f "$key_path" ] && has_key="${KEY_EMOJI}"
        
        printf "  ${GREEN}%2d.${NC} ${SERVER_EMOJI} ${YELLOW}%s${NC} (%s:%s) %s%s\n" \
               "$i" "$alias_name" "$user_host" "$port" "$has_password" "$has_key"
        ((i++))
    done <<< "$servers"
    
    return $((i-1))
}

# 显示活跃的端口转发
show_active_forwards() {
    local active_forwards
    active_forwards=$(get_section "active_forwards")
    if [ -n "$active_forwards" ]; then
        echo
        echo -e "${CYAN}已启用的端口转发:${NC}"
        echo -e "${CYAN}------------------${NC}"
        
        local i=1
        while IFS='|' read -r rule_name local_port pid user_host port server_alias remote_host remote_port; do
            [ -z "$rule_name" ] && continue
            format_forward_display "$i" "$rule_name" "$local_port" "$server_alias" "$remote_host" "$remote_port" "$pid"
            ((i++))
        done <<< "$active_forwards"
        return 0
    else
        return 1
    fi
}

# 检查并清理无效的端口转发进程
check_and_cleanup_forwards() {
    local active_forwards
    active_forwards=$(get_section "active_forwards")
    
    if [ -z "$active_forwards" ]; then
        return 0
    fi
    
    local temp_file
    temp_file=$(mktemp)
    local cleanup_needed=false
    local cleaned_count=0
    
    # 复制配置文件到临时文件
    cp "$CONFIG_FILE" "$temp_file"
    
    while IFS='|' read -r rule_name local_port pid user_host port server_alias remote_host remote_port; do
        [ -z "$rule_name" ] && continue
        
        # 检查进程是否存在
        if ! kill -0 "$pid" 2>/dev/null; then
            # 进程不存在，从配置中移除
            local rule_line="${rule_name}|${local_port}|${pid}|${user_host}|${port}|${server_alias}|${remote_host}|${remote_port}"
            
            awk -v target_line="$rule_line" '
            $0 == target_line && in_active { next }
            /^\[active_forwards\]$/ { in_active=1 }
            /^\[.*\]$/ && !/^\[active_forwards\]$/ { in_active=0 }
            { print }
            ' "$temp_file" > "${temp_file}.new" && mv "${temp_file}.new" "$temp_file"
            
            cleanup_needed=true
            ((cleaned_count++))
        fi
    done <<< "$active_forwards"
    
    # 如果有清理，更新配置文件并显示信息
    if [ "$cleanup_needed" = true ]; then
        mv "$temp_file" "$CONFIG_FILE"
        if [ "$cleaned_count" -gt 0 ]; then
            echo -e "${INFO_EMOJI} ${YELLOW}已清理 $cleaned_count 个失效的端口转发进程${NC}"
            sleep 1
        fi
    else
        rm -f "$temp_file"
    fi
}

# 主菜单
main_menu() {
    # 在显示菜单前检查并清理无效的端口转发进程
    check_and_cleanup_forwards
    
    clear
    echo -e "${PURPLE}==========================================${NC}"
    echo -e "${PURPLE}::          mssh - SSH 管理工具         ::${NC}"
    echo -e "${PURPLE}==========================================${NC}"
    echo
    
    show_servers
    show_active_forwards
    local has_active_forwards=$?
    
    echo
    echo -e "${BLUE}选项分区:${NC}"
    echo -e "${BLUE}---------${NC}"
    echo -e "  ${GREEN}[a] 增加服务器${NC}"
    echo -e "  ${RED}[d] 删除服务器${NC}"
    echo -e "  ${BLUE}[p] 端口转发${NC}"
    echo -e "  ${CYAN}[q] 退出${NC}"
    
    # 显示端口转发持久化提示
    if [ $has_active_forwards -eq 0 ]; then
        echo
        echo -e "${INFO_EMOJI} ${YELLOW}提示：端口转发将在退出程序后继续运行${NC}"
    fi
    
    echo
    echo -ne "${GREEN}请选择操作: ${NC}"
}

# 添加服务器
add_server() {
    while true; do
        clear
        echo -e "${PURPLE}============ 添加服务器 ============${NC}"
        echo
        echo -e "${INFO_EMOJI} ${CYAN}添加新服务器 (0或回车返回)${NC}"
        echo
        safe_read "$(echo -e "${CYAN}输入别名: ${NC}")" alias_name; [ "$alias_name" = "0" ] || [ -z "$alias_name" ] && return
        safe_read "$(echo -e "${CYAN}输入用户名@主机: ${NC}")" user_host; [ "$user_host" = "0" ] || [ -z "$user_host" ] && return
        safe_read "$(echo -e "${CYAN}输入端口 (默认22): ${NC}")" port; [ "$port" = "0" ] && return; port=${port:-22}
        echo -ne "${CYAN}输入密码 (可选): ${NC}"
        read -r -s password
        echo
        safe_read "$(echo -e "${CYAN}输入私钥路径 (可选): ${NC}")" key_path; [ "$key_path" = "0" ] && return
        
        if [ -n "$key_path" ] && [ ! -f "$key_path" ]; then
            echo -e "${ERROR_EMOJI} ${RED}密钥文件不存在${NC}"
            safe_read "$(echo -e "${YELLOW}是否继续? (y/N): ${NC}")" continue_without_key
            if [[ ! "${continue_without_key:-n}" =~ [yY] ]]; then
                continue
            fi
            key_path=""
        fi
        
        # 加密密码
        [ -n "$password" ] && password=$(encrypt_password "$password")
        
        # 添加到配置文件
        local temp_file
        temp_file=$(mktemp)
        awk -v new_server="${alias_name}|${user_host}|${port}|${key_path}|${password}" '
        /^\[servers\]$/ { print; in_servers=1; next }
        /^\[.*\]$/ { in_servers=0 }
        in_servers && /^$/ { print new_server; added=1 }
        { print }
        END { if (!added && in_servers) print new_server }
        ' "$CONFIG_FILE" > "$temp_file" && mv "$temp_file" "$CONFIG_FILE"
        
        echo -e "${SUCCESS_EMOJI} ${GREEN}服务器已添加: $alias_name${NC}"
        echo
        safe_read "$(echo -e "${YELLOW}是否继续添加? (y/N): ${NC}")" continue_add
        if [[ ! "${continue_add:-n}" =~ [yY] ]]; then
            break
        fi
    done
}

# 删除服务器
delete_server() {
    while true; do
        clear
        echo -e "${PURPLE}============ 删除服务器 ============${NC}"
        echo
        echo -e "${WARNING_EMOJI} ${YELLOW}删除服务器${NC}"
        echo
        show_servers
        echo
        safe_read "$(echo -e "${CYAN}选择要删除的服务器编号 (0或回车返回): ${NC}")" choice
        [ "$choice" = "0" ] || [ -z "$choice" ] && return
        
        local servers
        servers=$(get_section "servers")
        local server_line
        server_line=$(echo "$servers" | sed -n "${choice}p")
        
        if [ -n "$server_line" ]; then
            local alias_name
            alias_name=$(echo "$server_line" | cut -d'|' -f1)
            echo -e "${WARNING_EMOJI} ${YELLOW}确认删除服务器: $alias_name${NC}"
            
            local temp_file
            temp_file=$(mktemp)
            awk -v target_line="$server_line" '
            $0 == target_line && in_servers { next }
            /^\[servers\]$/ { in_servers=1 }
            /^\[.*\]$/ && !/^\[servers\]$/ { in_servers=0 }
            { print }
            ' "$CONFIG_FILE" > "$temp_file" && mv "$temp_file" "$CONFIG_FILE"
            
            echo -e "${SUCCESS_EMOJI} ${GREEN}服务器已删除: $alias_name${NC}"
        else
            echo -e "${ERROR_EMOJI} ${RED}无效的服务器编号!${NC}"
        fi
        
        echo
        safe_read "$(echo -e "${YELLOW}是否继续删除? (y/N): ${NC}")" continue_del
        if [[ ! "${continue_del:-n}" =~ [yY] ]]; then
            break
        fi
    done
}

# 添加端口转发规则
add_port_forward_rule() {
    echo -e "${INFO_EMOJI} ${CYAN}添加新端口转发规则 (0或回车返回):${NC}"
    
    safe_read "$(echo -e "${CYAN}输入规则名称: ${NC}")" rule_name
    if [ "$rule_name" = "0" ] || [ -z "$rule_name" ]; then
        return 1
    fi
    
    safe_read "$(echo -e "${CYAN}输入本地端口: ${NC}")" local_port
    if [ "$local_port" = "0" ] || [ -z "$local_port" ]; then
        return 1
    fi
    
    safe_read "$(echo -e "${CYAN}输入远程主机 (默认127.0.0.1): ${NC}")" remote_host
    if [ "$remote_host" = "0" ]; then
        return 1
    fi
    remote_host=${remote_host:-127.0.0.1}
    
    safe_read "$(echo -e "${CYAN}输入远程端口 (默认${local_port}): ${NC}")" remote_port
    if [ "$remote_port" = "0" ]; then
        return 1
    fi
    remote_port=${remote_port:-$local_port}
    
    echo -e "\n${CYAN}请选择要使用的服务器:${NC}"
    show_servers
    echo
    safe_read "$(echo -e "${CYAN}选择服务器编号: ${NC}")" server_choice
    if [ "$server_choice" = "0" ] || [ -z "$server_choice" ]; then
        return 1
    fi
    
    local servers
    servers=$(get_section "servers")
    local selected_server
    selected_server=$(echo "$servers" | sed -n "${server_choice}p")
    if [ -n "$selected_server" ]; then
        IFS='|' read -r server_alias user_host port key_path password <<< "$selected_server"
        
        local temp_file
        temp_file=$(mktemp)
        awk -v new_rule="${server_alias}|${rule_name}|${local_port}|${remote_host}|${remote_port}|${user_host}|${port}|${key_path}|${password}" '
        /^\[port_forwards\]$/ { print; in_forwards=1; next }
        /^\[.*\]$/ { in_forwards=0 }
        in_forwards && /^$/ { print new_rule; added=1 }
        { print }
        END { if (!added && in_forwards) print new_rule }
        ' "$CONFIG_FILE" > "$temp_file" && mv "$temp_file" "$CONFIG_FILE"
        
        echo -e "${SUCCESS_EMOJI} ${GREEN}端口转发规则已添加: $rule_name${NC}"
        return 0
    else
        echo -e "${ERROR_EMOJI} ${RED}无效的服务器编号!${NC}"
        return 1
    fi
}

# 删除端口转发规则
delete_port_forward() {
    local rule_number="$1"
    
    local forwards
    forwards=$(get_section "port_forwards")
    local rule_line
    rule_line=$(echo "$forwards" | sed -n "${rule_number}p")
    
    if [ -n "$rule_line" ]; then
        local rule_name
        rule_name=$(echo "$rule_line" | cut -d'|' -f2)
        
        local temp_file
        temp_file=$(mktemp)
        awk -v target_line="$rule_line" '
        $0 == target_line && in_forwards { next }
        /^\[port_forwards\]$/ { in_forwards=1 }
        /^\[.*\]$/ && !/^\[port_forwards\]$/ { in_forwards=0 }
        { print }
        ' "$CONFIG_FILE" > "$temp_file" && mv "$temp_file" "$CONFIG_FILE"
        
        echo -e "${SUCCESS_EMOJI} ${GREEN}规则已删除: $rule_name${NC}"
    else
        echo -e "${ERROR_EMOJI} ${RED}无效的规则编号!${NC}"
    fi
}

# 停止后台端口转发
stop_background_forward() {
    local rule_number="$1"
    
    local active_forwards
    active_forwards=$(get_section "active_forwards")
    local active_line
    active_line=$(echo "$active_forwards" | sed -n "${rule_number}p")
    
    if [ -n "$active_line" ]; then
        IFS='|' read -r rule_name local_port pid user_host port server_alias remote_host remote_port <<< "$active_line"
        
        if kill "$pid" 2>/dev/null; then
            echo -e "${SUCCESS_EMOJI} ${GREEN}端口转发已停止: $rule_name (PID: $pid)${NC}"
        else
            echo -e "${WARNING_EMOJI} ${YELLOW}进程可能已经停止: $rule_name (PID: $pid)${NC}"
        fi
        
        # 从活跃转发列表中移除
        local temp_file
        temp_file=$(mktemp)
        awk -v target_line="$active_line" '
        $0 == target_line && in_active { next }
        /^\[active_forwards\]$/ { in_active=1 }
        /^\[.*\]$/ && !/^\[active_forwards\]$/ { in_active=0 }
        { print }
        ' "$CONFIG_FILE" > "$temp_file" && mv "$temp_file" "$CONFIG_FILE"
    else
        echo -e "${ERROR_EMOJI} ${RED}无效的活跃转发编号!${NC}"
    fi
}

# 启动后台端口转发
start_background_forward() {
    local rule_number="$1"
    
    local forwards
    forwards=$(get_section "port_forwards")
    local rule_line
    rule_line=$(echo "$forwards" | sed -n "${rule_number}p")
    
    if [ -n "$rule_line" ]; then
        IFS='|' read -r server_alias rule_name local_port remote_host remote_port user_host port key_path password <<< "$rule_line"
        
        # 解密密码
        [ -n "$password" ] && password=$(decrypt_password "$password")
        
        # 构建 SSH 命令
        local ssh_args=("-p" "$port" "-L" "${local_port}:${remote_host}:${remote_port}" "-N" "$user_host")
        [ -n "$key_path" ] && ssh_args+=("-i" "$key_path")
        
        # 启动后台进程 (使用密码或密钥认证)
        local ssh_pid
        if [ -n "$password" ] && command -v sshpass >/dev/null 2>&1; then
            echo -e "${INFO_EMOJI} ${YELLOW}使用保存的密码启动端口转发...${NC}"
            nohup sshpass -p "$password" ssh "${ssh_args[@]}" >/dev/null 2>&1 &
            ssh_pid=$!
            disown $ssh_pid 2>/dev/null
            
            # 等待SSH连接建立
            sleep 1
            
            # 检查进程是否仍在运行
            if ! kill -0 "$ssh_pid" 2>/dev/null; then
                echo -e "${ERROR_EMOJI} ${RED}端口转发启动失败，请检查网络连接和认证信息${NC}"
                return 1
            fi         
        else
            echo -e "${INFO_EMOJI} ${YELLOW}启动端口转发 (需要手动输入密码)...${NC}"
            nohup ssh "${ssh_args[@]}" </dev/tty >/dev/null 2>&1 &
            ssh_pid=$!
            disown $ssh_pid 2>/dev/null
            
            # 给用户一些时间输入密码
            echo -e "${INFO_EMOJI} ${CYAN}请在上方输入SSH密码...${NC}"
            sleep 3
            
            # 检查进程是否仍在运行
            if ! kill -0 "$ssh_pid" 2>/dev/null; then
                echo -e "${ERROR_EMOJI} ${RED}端口转发启动失败，请检查网络连接和认证信息${NC}"
                return 1
            fi
        fi
        
        local temp_file
        temp_file=$(mktemp)
        awk -v new_active="${rule_name}|${local_port}|${ssh_pid}|${user_host}|${port}|${server_alias}|${remote_host}|${remote_port}" '
        /^\[active_forwards\]$/ { print; in_active=1; next }
        /^\[.*\]$/ { in_active=0 }
        in_active && /^$/ { print new_active; added=1 }
        { print }
        END { if (!added && in_active) print new_active }
        ' "$CONFIG_FILE" > "$temp_file" && mv "$temp_file" "$CONFIG_FILE"
        
        echo -e "${SUCCESS_EMOJI} ${GREEN}端口转发已启动: $rule_name (PID: $ssh_pid)${NC}"
    else
        echo -e "${ERROR_EMOJI} ${RED}无效的规则编号!${NC}"
    fi
}

# 端口转发管理
list_port_forwards() {
    while true; do
        clear
        echo -e "${PURPLE}=========== 端口转发管理 ===========${NC}"
        echo
        
        local forwards
        forwards=$(get_section "port_forwards")
        if [ -z "$forwards" ]; then
            echo -e "${CYAN}已配置的端口转发规则:${NC}"
            echo -e "${CYAN}------------------------${NC}"
            echo -e "  ${YELLOW}暂无端口转发规则${NC}"
        else
            echo -e "${CYAN}已配置的端口转发规则:${NC}"
            echo -e "${CYAN}------------------------${NC}"
            local i=1
            while IFS='|' read -r server_alias rule_name local_port remote_host remote_port _ _ _ _ || [ -n "$rule_name" ]; do
                [ -z "$rule_name" ] && continue
                format_forward_display "$i" "$rule_name" "$local_port" "$server_alias" "$remote_host" "$remote_port"
                ((i++))
            done <<< "$forwards"
        fi
        
        show_active_forwards
        
        echo
        echo -e "${BLUE}操作选项:${NC}"
        echo -e "${BLUE}---------${NC}"
        echo -e "  ${GREEN}[1] 添加端口转发${NC}"
        echo -e "  ${YELLOW}[2] 启动端口转发${NC}"
        echo -e "  ${ORANGE}[3] 停止端口转发${NC}"
        echo -e "  ${RED}[4] 删除转发规则${NC}"
        echo
        safe_read "$(echo -e "${CYAN}请选择操作 (0或回车返回): ${NC}")" choice
        
        case $choice in
            0|"") return ;;
            1) 
                echo
                if add_port_forward_rule; then
                    safe_read "按回车键继续..." pause_key
                fi
                ;;
            2) 
                if [ -z "$forwards" ]; then
                    echo -e "${ERROR_EMOJI} ${RED}暂无端口转发规则可启动!${NC}"
                    safe_read "按回车键继续..." pause_key
                else
                    safe_read "$(echo -e "${CYAN}输入要启动的规则编号: ${NC}")" start_choice
                    if [ -n "$start_choice" ]; then
                        start_background_forward "$start_choice"
                    fi
                    safe_read "按回车键继续..." pause_key
                fi
                ;;
            3)
                local active_forwards
                active_forwards=$(get_section "active_forwards")
                if [ -z "$active_forwards" ]; then
                    echo -e "${ERROR_EMOJI} ${RED}暂无活跃的端口转发可停止!${NC}"
                    safe_read "按回车键继续..." pause_key
                else
                    echo
                    echo -e "${CYAN}当前活跃的端口转发:${NC}"
                    local i=1
                    while IFS='|' read -r rule_name local_port pid user_host port server_alias remote_host remote_port; do
                        [ -z "$rule_name" ] && continue
                        format_forward_display "$i" "$rule_name" "$local_port" "$server_alias" "$remote_host" "$remote_port" "$pid"
                        ((i++))
                    done <<< "$active_forwards"
                    echo
                    safe_read "$(echo -e "${CYAN}输入要停止的端口转发编号: ${NC}")" stop_choice
                    if [ -n "$stop_choice" ]; then
                        stop_background_forward "$stop_choice"
                    fi
                    safe_read "按回车键继续..." pause_key
                fi
                ;;
            4)
                if [ -z "$forwards" ]; then
                    echo -e "${ERROR_EMOJI} ${RED}暂无端口转发规则可删除!${NC}"
                    safe_read "按回车键继续..." pause_key
                else
                    safe_read "$(echo -e "${CYAN}输入要删除的规则编号: ${NC}")" del_choice
                    if [ -n "$del_choice" ]; then
                        delete_port_forward "$del_choice"
                    fi
                    safe_read "按回车键继续..." pause_key
                fi
                ;;
            *) echo -e "${ERROR_EMOJI} ${RED}无效选项!${NC}"; sleep 1 ;;
        esac
    done
}

# 连接服务器
connect_server() {
    local choice=$1
    
    local servers
    servers=$(get_section "servers")
    local selected_server
    selected_server=$(echo "$servers" | sed -n "${choice}p")
    
    if [ -n "$selected_server" ]; then
        IFS='|' read -r alias_name user_host port key_path password <<< "$selected_server"
        
        # 解密密码
        [ -n "$password" ] && password=$(decrypt_password "$password")
        
        echo -e "${CONNECT_EMOJI} ${GREEN}连接到: $alias_name ($user_host:$port)${NC}"
        
        local ssh_args=("-p" "$port" "$user_host")
        [ -n "$key_path" ] && ssh_args+=("-i" "$key_path")
        
        if [ -n "$password" ] && command -v sshpass >/dev/null 2>&1; then
            echo -e "${WARNING_EMOJI} ${YELLOW}使用保存的密码连接...${NC}"
            sshpass -p "$password" ssh "${ssh_args[@]}"
        else
            ssh "${ssh_args[@]}"
        fi
    else
        echo -e "${ERROR_EMOJI} ${RED}无效的服务器编号!${NC}"
        sleep 1
    fi
}

# 主程序
check_sshpass
init_config

while true; do
    main_menu
    safe_read "" choice
    
    case $choice in
        [0-9]*) 
            if [[ "$choice" =~ ^[0-9]+$ ]]; then 
                connect_server "$choice"
            else 
                echo -e "${ERROR_EMOJI} ${RED}无效的服务器编号!${NC}"
                sleep 1
            fi 
            ;;
        a|A) add_server ;;
        d|D) delete_server ;;
        p|P) list_port_forwards ;;
        q|Q) graceful_exit ;;
        *) echo -e "${ERROR_EMOJI} ${RED}无效选项!${NC}"; sleep 1 ;;
    esac
done