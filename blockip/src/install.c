#include "install.h"
#include "nftables.h"
#include "ban.h"
#include "whitelist.h"
#include "log.h"

int setup_pam_hooks(void) {
    const char *pam_file = "/etc/pam.d/sshd";
    
    /* 备份原文件 */
    char backup_cmd[MAX_COMMAND_LEN];
    snprintf(backup_cmd, sizeof(backup_cmd), "cp -f %s %s.bak.bip", pam_file, pam_file);
    system(backup_cmd);
    
    /* 移除旧的钩子 */
    char remove_cmd[MAX_COMMAND_LEN];
    snprintf(remove_cmd, sizeof(remove_cmd), "sed -i '\\|%s|d' %s", INSTALL_PATH, pam_file);
    system(remove_cmd);
    
    /* 添加新的钩子 */
    FILE *fp = fopen(pam_file, "r");
    if (!fp) {
        return ERROR_FILE;
    }
    
    char temp_file[MAX_PATH_LEN];
    snprintf(temp_file, sizeof(temp_file), "%s.tmp", pam_file);
    FILE *temp_fp = fopen(temp_file, "w");
    if (!temp_fp) {
        fclose(fp);
        return ERROR_FILE;
    }
    
    /* 在第一行插入check钩子 */
    fprintf(temp_fp, "auth optional pam_exec.so quiet %s check\n", INSTALL_PATH);
    
    /* 复制原内容 */
    char line[MAX_LINE_LEN];
    while (fgets(line, sizeof(line), fp)) {
        fputs(line, temp_fp);
    }
    
    /* 在末尾添加clean钩子 */
    fprintf(temp_fp, "session optional pam_exec.so quiet %s clean\n", INSTALL_PATH);
    
    fclose(fp);
    fclose(temp_fp);
    
    rename(temp_file, pam_file);
    
    log_write("[安装] PAM钩子已配置");
    return SUCCESS;
}

int remove_pam_hooks(void) {
    const char *pam_file = "/etc/pam.d/sshd";
    
    char command[MAX_COMMAND_LEN];
    snprintf(command, sizeof(command), "sed -i '\\|%s|d' %s", INSTALL_PATH, pam_file);
    system(command);
    
    log_write("[卸载] PAM钩子已移除");
    return SUCCESS;
}

int create_systemd_service(void) {
    
    const char *service_file = "/etc/systemd/system/bip.service";    FILE *fp = fopen(service_file, "w");
    if (!fp) {
        return ERROR_FILE;
    }
    
    fprintf(fp, "[Unit]\n");
    fprintf(fp, "Description=BIP (Block-IP) Service\n");
    fprintf(fp, "After=network.target nftables.service\n\n");
    fprintf(fp, "[Service]\n");
    fprintf(fp, "Type=oneshot\n");
    fprintf(fp, "ExecStart=%s restore\n", INSTALL_PATH);
    fprintf(fp, "RemainAfterExit=yes\n\n");
    fprintf(fp, "[Install]\n");
    fprintf(fp, "WantedBy=multi-user.target\n");
    
    fclose(fp);
    
    /* 重载systemd配置 */
    system("systemctl daemon-reload");
    
    /* 启用服务 */
    system("systemctl enable bip.service");
    
    log_write("[安装] systemd服务已创建");
    return SUCCESS;
}

static int remove_systemd_service(void) {
    /* 停止并禁用服务 */
    system("systemctl stop bip.service 2>/dev/null");
    system("systemctl disable bip.service 2>/dev/null");
    
    /* 删除服务文件 */
    remove("/etc/systemd/system/bip.service");
    
    /* 重载systemd配置 */
    system("systemctl daemon-reload");
    
    log_write("[卸载] systemd服务已移除");
    return SUCCESS;
}

int install_service(void) {
    msg(C_YELLOW, "开始安装 BIP (Block-IP)...");
    
    /* 复制程序到安装路径 */
    char exe_path[MAX_PATH_LEN];
    ssize_t len = readlink("/proc/self/exe", exe_path, sizeof(exe_path) - 1);
    if (len != -1) {
        exe_path[len] = '\0';
        
        FILE *src = fopen(exe_path, "rb");
        FILE *dst = fopen(INSTALL_PATH, "wb");
        if (src && dst) {
            char buf[8192];
            size_t n;
            while ((n = fread(buf, 1, sizeof(buf), src)) > 0) {
                fwrite(buf, 1, n, dst);
            }
            fclose(src);
            fclose(dst);
            chmod(INSTALL_PATH, 0755);
        } else {
            if (src) fclose(src);
            if (dst) fclose(dst);
        }
    }
    
    /* 创建必要的目录和文件 */
    mkdir(CONFIG_DIR, 0700);
    chmod(CONFIG_DIR, 0700);
    
    mkdir(RECORD_DIR, 0770);
    chmod(RECORD_DIR, 0770);
    
    FILE *fp = fopen(PERSIST_FILE, "a");
    if (fp) {
        chmod(PERSIST_FILE, 0600);
        fclose(fp);
    }
    
    fp = fopen(WHITELIST_FILE, "a");
    if (fp) {
        chmod(WHITELIST_FILE, 0600);
        fclose(fp);
    }
    
    /* 创建默认配置文件 */
    if (access(CONFIG_FILE, F_OK) != 0) {
        save_ban_time_to_config(DEFAULT_BAN_TIME);
        save_max_retries_to_config(DEFAULT_MAX_RETRIES);
        save_rate_limit_to_config(DEFAULT_RATE_LIMIT);
        save_rate_ban_time_to_config(DEFAULT_RATE_BAN_TIME);
        msg(C_GREEN, "  ✓ 已创建默认配置文件");
    }
    
    log_init();
    
    /* 安装nftables */
    check_and_install_nftables();

    /* 清空bip相关nft表和集合，防止历史残留 */
    char nft_clear_cmd[MAX_COMMAND_LEN];
    snprintf(nft_clear_cmd, sizeof(nft_clear_cmd),
        "nft flush table %s 2>/dev/null; "
        "nft delete table %s 2>/dev/null;",
        NFT_TABLE, NFT_TABLE);
    system(nft_clear_cmd);

    /* 初始化规则 */
    init_nftables_rules();
    
    /* 恢复数据 */
    restore_from_persist();
    whitelist_restore();
    
    /* 配置PAM钩子 */
    setup_pam_hooks();
    
    /* 创建systemd服务 */
    create_systemd_service();
    
    msg(C_GREEN, "✅ 安装完成！输入 bip list 查看效果。");
    
    return SUCCESS;
}

int uninstall_service(void) {
    msg(C_YELLOW, "⚠️  开始卸载 BIP (Block-IP)...");
    
    /* 移除systemd服务 */
    remove_systemd_service();
    msg(C_GREEN, "  ✓ 已移除 systemd 服务");
    
    /* 清除nftables规则 */
    char command[MAX_COMMAND_LEN];
    
    snprintf(command, sizeof(command), "nft delete rule %s input ip saddr @%s drop 2>/dev/null", 
             NFT_TABLE, NFT_SET);
    system(command);
    
    snprintf(command, sizeof(command), "nft delete rule %s input ip6 saddr @%s drop 2>/dev/null", 
             NFT_TABLE, NFT_SET_V6);
    system(command);
    
    snprintf(command, sizeof(command), "nft delete rule %s input ip saddr @%s accept 2>/dev/null", 
             NFT_TABLE, NFT_WHITELIST);
    system(command);
    
    snprintf(command, sizeof(command), "nft delete rule %s input ip6 saddr @%s accept 2>/dev/null", 
             NFT_TABLE, NFT_WHITELIST_V6);
    system(command);
    
    snprintf(command, sizeof(command), "nft delete set %s %s 2>/dev/null", NFT_TABLE, NFT_SET);
    system(command);
    
    snprintf(command, sizeof(command), "nft delete set %s %s 2>/dev/null", NFT_TABLE, NFT_SET_V6);
    system(command);
    
    snprintf(command, sizeof(command), "nft delete set %s %s 2>/dev/null", NFT_TABLE, NFT_WHITELIST);
    system(command);
    
    snprintf(command, sizeof(command), "nft delete set %s %s 2>/dev/null", NFT_TABLE, NFT_WHITELIST_V6);
    system(command);
    
    msg(C_GREEN, "  ✓ 已清除防火墙规则");
    
    /* 移除PAM钩子 */
    remove_pam_hooks();
    msg(C_GREEN, "  ✓ 已移除 PAM 钩子");
    
    /* 询问是否删除数据文件 */
    printf("是否删除配置目录和日志? [y/N] ");
    char answer[10];
    if (fgets(answer, sizeof(answer), stdin)) {
        if (answer[0] == 'y' || answer[0] == 'Y') {
            char rm_cmd[MAX_COMMAND_LEN];
            snprintf(rm_cmd, sizeof(rm_cmd), "rm -rf %s", CONFIG_DIR);
            system(rm_cmd);
            
            remove(LOG_FILE);
            char log_backup[MAX_PATH_LEN];
            snprintf(log_backup, sizeof(log_backup), "%s.1", LOG_FILE);
            remove(log_backup);
            
            msg(C_GREEN, "  ✓ 已删除数据文件");
        } else {
            printf("%s  ↳ 保留: %s, %s%s\n", 
                   C_CYAN, CONFIG_DIR, LOG_FILE, C_RESET);
        }
    }
    
    /* 删除程序文件 */
    remove(INSTALL_PATH);
    msg(C_GREEN, "  ✓ 已删除程序文件");
    
    msg(C_GREEN, "\n✅ 卸载完成！");
    
    return SUCCESS;
}
