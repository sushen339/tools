#include "common.h"
#include "log.h"
#include "ban.h"
#include "whitelist.h"
#include "stats.h"
#include "pam.h"
#include "install.h"
#include "nftables.h"
#include "ip_utils.h"

/* 显示帮助信息 */
void show_help(void) {
    printf("BIP (Block-IP) %s    by su\n", BIP_VERSION);
    printf("--------------------------------------\n");
    printf("使用方法:\n");
    printf("  bip list                查看实时统计/活跃列表/日志\n");
    printf("  bip list -w/--watch     动态监控模式（每2秒刷新）\n");
    printf("  bip show                显示本地持久化封禁列表\n");
    printf("  bip add <IP>            手动封禁 IP (支持IPv4/IPv6/CIDR)\n");
    printf("  bip del <IP>            手动解封 IP (支持IPv4/IPv6/CIDR)\n");
    printf("  bip vip add <IP>        添加IP到白名单 (支持IPv4/IPv6/CIDR)\n");
    printf("  bip vip del <IP>        从白名单移除IP\n");
    printf("  bip vip list            显示白名单列表\n");
    printf("  bip config                显示当前配置\n");
    printf("  bip config time <time>    设置封禁时间 (如: 7d, 24h, \"\" 为永久)\n");
    printf("  bip config retries <N>    设置最大重试次数 (1-10)\n");
    printf("  bip config ratelimit <N>  设置SSH端口速率 (1-1000/分钟)\n");
    printf("  bip config rateban <time> 设置超速封禁时长 (如: 10m, 1h)\n");
    printf("  bip restore               从持久化文件恢复黑白名单\n");
    printf("  bip install             安装/重装服务\n");
    printf("  bip uninstall           卸载服务\n");
    printf("--------------------------------------------------------\n");
}

/* VIP白名单子命令处理 */
static int handle_vip_command(int argc, char *argv[]) {
    if (argc < 3) {
        msg(C_RED, "用法: bip vip {add|del|list} <IP>");
        return ERROR_INVALID_ARG;
    }
    
    const char *subcmd = argv[2];
    
    if (strcmp(subcmd, "list") == 0) {
        whitelist_show();
        return SUCCESS;
    }
    
    if (argc < 4) {
        msg(C_RED, "错误: 需要提供IP地址");
        return ERROR_INVALID_ARG;
    }
    
    const char *ip = argv[3];
    
    if (!validate_ip_format(ip)) {
        char error_msg[MAX_LINE_LEN];
        snprintf(error_msg, sizeof(error_msg), "❌ 无效的IP格式: %s", ip);
        msg(C_RED, error_msg);
        return ERROR_INVALID_ARG;
    }
    
    if (strcmp(subcmd, "add") == 0) {
        if (nft_add_to_whitelist(ip) == SUCCESS) {
            whitelist_add_to_file(ip);
            log_write("[白名单添加] IP=%s", ip);
            
            char success_msg[MAX_LINE_LEN];
            snprintf(success_msg, sizeof(success_msg), "✅ 已添加到白名单: %s", ip);
            msg(C_GREEN, success_msg);
            return SUCCESS;
        }
        return ERROR_FILE;
    }
    
    if (strcmp(subcmd, "del") == 0) {
        nft_remove_from_whitelist(ip);
        whitelist_remove_from_file(ip);
        log_write("[白名单移除] IP=%s", ip);
        
        char success_msg[MAX_LINE_LEN];
        snprintf(success_msg, sizeof(success_msg), "✅ 已从白名单移除: %s", ip);
        msg(C_GREEN, success_msg);
        return SUCCESS;
    }
    
    msg(C_RED, "用法: bip vip {add|del|list} <IP>");
    return ERROR_INVALID_ARG;
}

/* 主函数 */
int main(int argc, char *argv[]) {
    /* 无参数显示帮助 */
    if (argc < 2) {
        show_help();
        return ERROR_INVALID_ARG;
    }

    const char *command = argv[1];

    if (strcmp(command, "version") == 0 || strcmp(command, "v") == 0 || strcmp(command, "-v") == 0) {
        printf("BIP (Block-IP) 版本: %s\n", BIP_VERSION);
        return 0;
    }
    
    /* PAM钩子：check命令 */
    if (strcmp(command, "check") == 0) {
        return pam_check_failed_login();
    }
    
    /* PAM钩子：clean命令 */
    if (strcmp(command, "clean") == 0) {
        return pam_clean_on_success();
    }
    
    /* list命令：显示统计信息 */
    if (strcmp(command, "list") == 0) {
        bool watch_mode = false;
        if (argc >= 3 && (strcmp(argv[2], "-w") == 0 || strcmp(argv[2], "--watch") == 0)) {
            watch_mode = true;
        }
        show_statistics_watch(watch_mode);
        return SUCCESS;
    }
    
    /* show命令：显示持久化列表 */
    if (strcmp(command, "show") == 0) {
        show_persist_list();
        return SUCCESS;
    }
    
    /* vip命令：白名单管理 */
    if (strcmp(command, "vip") == 0) {
        return handle_vip_command(argc, argv);
    }
    
    /* config命令：配置管理 */
    if (strcmp(command, "config") == 0) {
        if (argc == 2) {
            /* 显示当前配置 */
            const char *ban_time = get_ban_time_from_config();
            int max_retries = get_max_retries_from_config();
            int rate_limit = get_rate_limit_from_config();
            const char *rate_ban_time = get_rate_ban_time_from_config();
            printf("%s当前配置%s\n", C_CYAN, C_RESET);
            printf("====防爆破===\n");
            printf("封禁时间: %s%s%s", C_GREEN, ban_time, C_RESET);
            if (strlen(ban_time) == 0) {
                printf(" (永久封禁)\n");
            } else {
                printf("\n");
            }
            printf("最大重试次数: %s%d%s\n", C_GREEN, max_retries, C_RESET);
            printf("====防洪水攻击===\n");
            printf("SSH端口速率: %s%d/分钟%s\n", C_GREEN, rate_limit, C_RESET);
            printf("超速封禁时长: %s%s%s\n", C_GREEN, rate_ban_time, C_RESET);
            printf("配置文件: %s\n", CONFIG_FILE);
            return SUCCESS;
        } else if (argc == 4 && strcmp(argv[2], "time") == 0) {
            /* 设置封禁时间 */
            const char *new_time = argv[3];
            
            if (save_ban_time_to_config(new_time) == SUCCESS) {
                char msg_buf[MAX_LINE_LEN];
                if (strlen(new_time) == 0) {
                    snprintf(msg_buf, sizeof(msg_buf), "✅ 封禁时间已设置为: 永久封禁");
                } else {
                    snprintf(msg_buf, sizeof(msg_buf), "✅ 封禁时间已设置为: %s", new_time);
                }
                msg(C_GREEN, msg_buf);
                msg(C_YELLOW, "提示: 新的封禁时间将在下次封禁时生效");
                return SUCCESS;
            }
            return ERROR_FILE;
        } else if (argc == 4 && strcmp(argv[2], "retries") == 0) {
            /* 设置最大重试次数 */
            int retries = atoi(argv[3]);
            if (save_max_retries_to_config(retries) == SUCCESS) {
                char msg_buf[MAX_LINE_LEN];
                snprintf(msg_buf, sizeof(msg_buf), "✅ 最大重试次数已设置为: %d", retries);
                msg(C_GREEN, msg_buf);
                msg(C_YELLOW, "提示: 新的重试次数将在下次验证时生效");
                return SUCCESS;
            }
            msg(C_RED, "❌ 设置失败: 请使用1-10之间的整数");
            return ERROR_INVALID_ARG;
        } else if (argc == 4 && strcmp(argv[2], "ratelimit") == 0) {
            /* 设置SSH端口速率 */
            int rate = atoi(argv[3]);
            if (save_rate_limit_to_config(rate) == SUCCESS) {
                char msg_buf[MAX_LINE_LEN];
                snprintf(msg_buf, sizeof(msg_buf), "✅ SSH端口速率已设置为: %d/分钟", rate);
                msg(C_GREEN, msg_buf);
                /* 自动重新加载nftables规则 */
                if (init_nftables_rules() == SUCCESS) {
                    msg(C_GREEN, "✅ 已自动应用新的速率限制规则");
                } else {
                    msg(C_YELLOW, "⚠️  规则应用失败,请手动运行: sudo bip install");
                }
                return SUCCESS;
            }
            msg(C_RED, "❌ 设置失败: 请使用1-1000之间的整数");
            return ERROR_INVALID_ARG;
        } else if (argc == 4 && strcmp(argv[2], "rateban") == 0) {
            /* 设置超速封禁时间 */
            const char *new_time = argv[3];
            if (save_rate_ban_time_to_config(new_time) == SUCCESS) {
                char msg_buf[MAX_LINE_LEN];
                snprintf(msg_buf, sizeof(msg_buf), "✅ 超速封禁时长已设置为: %s", new_time);
                msg(C_GREEN, msg_buf);
                /* 自动重新加载nftables规则 */
                if (init_nftables_rules() == SUCCESS) {
                    msg(C_GREEN, "✅ 已自动应用新的封禁时长规则");
                } else {
                    msg(C_YELLOW, "⚠️  规则应用失败,请手动运行: sudo bip install");
                }
                return SUCCESS;
            }
            return ERROR_FILE;
        } else {
            msg(C_RED, "用法: bip config");
            msg(C_RED, "      bip config time <time>");
            msg(C_RED, "      bip config retries <count>");
            msg(C_RED, "      bip config ratelimit <rate>");
            msg(C_RED, "      bip config rateban <time>");
            return ERROR_INVALID_ARG;
        }
    }
    
    /* add命令：手动封禁IP */
    if (strcmp(command, "add") == 0) {
        if (argc < 3) {
            msg(C_RED, "错误: 需要提供IP地址");
            return ERROR_INVALID_ARG;
        }
        
        const char *ip = argv[2];
        
        if (!validate_ip_format(ip)) {
            char error_msg[MAX_LINE_LEN];
            snprintf(error_msg, sizeof(error_msg), "❌ 无效的IP格式: %s", ip);
            msg(C_RED, error_msg);
            return ERROR_INVALID_ARG;
        }
        
        if (ban_ip(ip, true) == SUCCESS) {
            char success_msg[MAX_LINE_LEN];
            snprintf(success_msg, sizeof(success_msg), "✅ 已封禁: %s", ip);
            msg(C_GREEN, success_msg);
            return SUCCESS;
        }
        
        return ERROR_FILE;
    }
    
    /* del命令：手动解封IP */
    if (strcmp(command, "del") == 0) {
        if (argc < 3) {
            msg(C_RED, "错误: 需要提供IP地址");
            return ERROR_INVALID_ARG;
        }
        
        const char *ip = argv[2];
        
        if (unban_ip(ip) == SUCCESS) {
            char success_msg[MAX_LINE_LEN];
            snprintf(success_msg, sizeof(success_msg), "✅ 已解封: %s", ip);
            msg(C_GREEN, success_msg);
            return SUCCESS;
        }
        
        return ERROR_FILE;
    }
    
    /* restore命令：恢复黑白名单 */
    if (strcmp(command, "restore") == 0) {
        if (check_root() != SUCCESS) {
            return ERROR_PERMISSION;
        }
        
        check_and_install_nftables();
        init_nftables_rules();
        restore_from_persist();
        whitelist_restore();
        
        return SUCCESS;
    }
    
    /* install命令：安装服务 */
    if (strcmp(command, "install") == 0) {
        if (check_root() != SUCCESS) {
            return ERROR_PERMISSION;
        }
        
        return install_service();
    }
    
    /* uninstall命令：卸载服务 */
    if (strcmp(command, "uninstall") == 0) {
        if (check_root() != SUCCESS) {
            return ERROR_PERMISSION;
        }
        
        return uninstall_service();
    }
    
    /* 未知命令 */
    show_help();
    return ERROR_INVALID_ARG;
}
