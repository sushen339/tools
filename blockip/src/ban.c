#include "ban.h"
#if defined(__unix__) || defined(__linux__)
#include <fcntl.h>      // O_CREAT, O_RDWR
#include <sys/file.h>   // flock, LOCK_EX, LOCK_UN
#include <signal.h>     // SIGCHLD, SIG_IGN
#else
#define O_CREAT 0x0100
#define O_RDWR  0x0002
#define LOCK_EX 2
#define LOCK_UN 8
#define SIGCHLD 17
#define SIG_IGN ((void (*)(int))1)
#endif
#include "nftables.h"
#include "whitelist.h"
#include "geo.h"
#include "log.h"


int ban_ip(const char *ip, bool save_to_disk) {
    if (!ip || !validate_ip_format(ip)) {
        return ERROR_INVALID_ARG;
    }
    
    /* 检查白名单 */
    if (is_in_whitelist(ip)) {
        log_write("[白名单保护] IP=%s 在白名单中，拒绝封禁", ip);
        return SUCCESS;
    }
    
    /* 解析IP信息 */
    ip_info_t info;
    if (parse_ip_info(ip, &info) != SUCCESS) {
        return ERROR_INVALID_ARG;
    }
    
    /* 立即添加到nftables（关键操作，不能延迟） */
    if (nft_add_to_blacklist(&info) != SUCCESS) {
        return ERROR_FILE;
    }
    
    /* 先保存到磁盘（不查询国家） */
    if (save_to_disk) {
        persist_add_ip(ip, "");
        log_write("[执行封禁] IP=%s 已封禁", ip);
    }
    
    /* 异步查询国家信息（耗时操作，放在后台执行） */
    bool should_query = save_to_disk && !is_ipv6(ip) && !is_cidr(ip);
    if (should_query) {
        /* 设置忽略SIGCHLD信号，防止僵尸进程 */
        signal(SIGCHLD, SIG_IGN);
        
        pid_t pid = fork();
        if (pid == 0) {
            /* 子进程：执行耗时的网络查询 */
            char country_code[MAX_COUNTRY_CODE] = {0};
            if (query_country_code(ip, country_code, sizeof(country_code)) == SUCCESS) {
                /* 更新持久化文件中的国家信息 */
                update_ip_country(ip, country_code);
                log_write("[地理查询] IP=%s 国家=%s", ip, get_country_name(country_code));
            }
            
            /* 补充其他IP的国家信息 */
            supplement_country_info(ip);
            _exit(0);
        }
        /* 父进程：立即返回 */
    } else if (!save_to_disk) {
        log_write("[执行封禁] IP=%s 已封禁", ip);
    }
    
    return SUCCESS;
}

int unban_ip(const char *ip) {
    if (!ip) {
        return ERROR_INVALID_ARG;
    }
    
    /* 从nftables移除 */
    nft_remove_from_blacklist(ip);
    
    /* 从持久化文件移除 */
    persist_remove_ip(ip);
    
    log_write("[手动解封] IP=%s", ip);
    
    return SUCCESS;
}

int persist_add_ip(const char *ip, const char *country_code) {
    if (!ip) {
        return ERROR_INVALID_ARG;
    }
    
    /* 加锁 */
    char lock_file[MAX_PATH_LEN];
    snprintf(lock_file, sizeof(lock_file), "%s.lock", PERSIST_FILE);
    
    int lock_fd = open(lock_file, O_CREAT | O_RDWR, 0600);
    if (lock_fd < 0) {
        return ERROR_FILE;
    }
    
    flock(lock_fd, LOCK_EX);
    
    /* 检查是否已存在 */
    FILE *fp = fopen(PERSIST_FILE, "r");
    bool exists = false;
    
    if (fp) {
        char line[MAX_LINE_LEN];
        while (fgets(line, sizeof(line), fp)) {
            line[strcspn(line, "\n")] = 0;
            
            /* 提取IP部分 */
            char *pipe = strchr(line, '|');
            if (pipe) *pipe = '\0';
            
            if (strcmp(line, ip) == 0) {
                exists = true;
                break;
            }
        }
        fclose(fp);
    }
    
    /* 添加到文件 */
    if (!exists) {
        fp = fopen(PERSIST_FILE, "a");
        if (fp) {
            if (country_code && strlen(country_code) > 0) {
                fprintf(fp, "%s|%s\n", ip, country_code);
            } else {
                fprintf(fp, "%s\n", ip);
            }
            fclose(fp);
        }
    }
    
    flock(lock_fd, LOCK_UN);
    close(lock_fd);
    
    return SUCCESS;
}

int persist_remove_ip(const char *ip) {
    if (!ip) {
        return ERROR_INVALID_ARG;
    }
    
    FILE *fp = fopen(PERSIST_FILE, "r");
    if (!fp) {
        return ERROR_FILE;
    }
    
    char temp_file[MAX_PATH_LEN];
    snprintf(temp_file, sizeof(temp_file), "%s.tmp", PERSIST_FILE);
    FILE *temp_fp = fopen(temp_file, "w");
    if (!temp_fp) {
        fclose(fp);
        return ERROR_FILE;
    }
    
    char line[MAX_LINE_LEN];
    while (fgets(line, sizeof(line), fp)) {
        char line_copy[MAX_LINE_LEN];
        snprintf(line_copy, sizeof(line_copy), "%s", line);
        line_copy[strcspn(line_copy, "\n")] = 0;
        
        /* 提取IP部分 */
        char *pipe = strchr(line_copy, '|');
        if (pipe) *pipe = '\0';
        
        if (strcmp(line_copy, ip) != 0) {
            fputs(line, temp_fp);
        }
    }
    
    fclose(fp);
    fclose(temp_fp);
    
    rename(temp_file, PERSIST_FILE);
    return SUCCESS;
}

int update_ip_country(const char *ip, const char *country_code) {
    if (!ip || !country_code) {
        return ERROR_INVALID_ARG;
    }
    
    FILE *fp = fopen(PERSIST_FILE, "r");
    if (!fp) {
        return ERROR_FILE;
    }
    
    char temp_file[MAX_PATH_LEN];
    snprintf(temp_file, sizeof(temp_file), "%s.tmp", PERSIST_FILE);
    FILE *temp_fp = fopen(temp_file, "w");
    if (!temp_fp) {
        fclose(fp);
        return ERROR_FILE;
    }
    
    char line[MAX_LINE_LEN];
    bool found = false;
    
    while (fgets(line, sizeof(line), fp)) {
        char line_copy[MAX_LINE_LEN];
        snprintf(line_copy, sizeof(line_copy), "%s", line);
        line_copy[strcspn(line_copy, "\n")] = 0;
        
        /* 提取IP部分 */
        char *pipe = strchr(line_copy, '|');
        if (pipe) *pipe = '\0';
        
        if (strcmp(line_copy, ip) == 0 && !found) {
            /* 找到目标IP，更新国家信息 */
            fprintf(temp_fp, "%s|%s\n", ip, country_code);
            found = true;
        } else {
            /* 保持原样 */
            fputs(line, temp_fp);
        }
    }
    
    fclose(fp);
    fclose(temp_fp);
    
    rename(temp_file, PERSIST_FILE);
    return SUCCESS;
}

int restore_from_persist(void) {
    FILE *fp = fopen(PERSIST_FILE, "r");
    if (!fp) {
        return SUCCESS;  /* 文件不存在 */
    }
    
    char line[MAX_LINE_LEN];
    int count = 0;
    
    while (fgets(line, sizeof(line), fp)) {
        line[strcspn(line, "\n")] = 0;
        
        if (strlen(line) == 0) continue;
        
        /* 提取IP部分 */
        char ip[MAX_IP_LEN];
        char *pipe = strchr(line, '|');
        if (pipe) {
            *pipe = '\0';
            strncpy(ip, line, sizeof(ip) - 1);
        } else {
            strncpy(ip, line, sizeof(ip) - 1);
        }
        ip[sizeof(ip) - 1] = '\0';
        
        /* 恢复到nftables（不保存到磁盘） */
        ip_info_t info;
        if (parse_ip_info(ip, &info) == SUCCESS) {
            if (nft_add_to_blacklist(&info) == SUCCESS) {
                count++;
            }
        }
    }
    
    fclose(fp);
    
    log_write("[系统恢复] 已从磁盘恢复 %d 个黑名单 IP", count);
    
    char message[MAX_LINE_LEN];
    snprintf(message, sizeof(message), "✅ 已从磁盘恢复 %d 个黑名单 IP", count);
    msg(C_GREEN, message);
    
    return SUCCESS;
}

void show_persist_list(void) {
    msg(C_CYAN, "=== 📋 本地持久化封禁列表 ===");
    
    FILE *fp = fopen(PERSIST_FILE, "r");
    if (!fp) {
        printf("(暂无持久化记录)\n");
        return;
    }
    
    /* 检查文件是否为空 */
    fseek(fp, 0, SEEK_END);
    long file_size = ftell(fp);
    if (file_size <= 0) {
        fclose(fp);
        printf("(暂无持久化记录)\n");
        return;
    }
    
    rewind(fp);
    
    /* 统计 */
    int total = 0, ipv4_count = 0, ipv6_count = 0;
    char line[MAX_LINE_LEN];
    
    while (fgets(line, sizeof(line), fp)) {
        line[strcspn(line, "\n")] = 0;
        if (strlen(line) == 0) continue;
        
        total++;
        if (strchr(line, ':')) {
            ipv6_count++;
        } else {
            ipv4_count++;
        }
    }
    
    printf("总计: %s%d%s 条  |  IPv4: %s%d%s 条  |  IPv6: %s%d%s 条\n\n",
           C_GREEN, total, C_RESET,
           C_CYAN, ipv4_count, C_RESET,
           C_YELLOW, ipv6_count, C_RESET);
    
    printf("%s%-25s %-15s%s\n", C_YELLOW, "IP 地址", "国家/地区", C_RESET);
    printf("------------------------------------------\n");
    
    rewind(fp);
    while (fgets(line, sizeof(line), fp)) {
        line[strcspn(line, "\n")] = 0;
        if (strlen(line) > 0) {
            /* 解析IP和国家 */
            char *pipe = strchr(line, '|');
            
            if (pipe) {
                *pipe = '\0';
                printf("%-25s %s\n", line, get_country_name(pipe + 1));
            } else {
                printf("%-25s %s\n", line, "-");
            }
        }
    }
    
    fclose(fp);
    printf("\n");
    printf("%s📌 文件位置: %s%s\n", C_CYAN, PERSIST_FILE, C_RESET);
}
