#include "whitelist.h"
#include "ip_utils.h"
#include "nftables.h"
#include "log.h"

bool is_in_whitelist(const char *ip) {
    if (!ip) return false;
    
    FILE *fp = fopen(WHITELIST_FILE, "r");
    if (!fp) return false;
    
    char line[MAX_LINE_LEN];
    bool found = false;
    
    while (fgets(line, sizeof(line), fp)) {
        line[strcspn(line, "\n")] = 0;
        
        if (strlen(line) == 0) continue;
        
        if (ip_matches_whitelist_entry(ip, line)) {
            found = true;
            break;
        }
    }
    
    fclose(fp);
    return found;
}

int whitelist_add_to_file(const char *ip) {
    if (!ip) {
        return ERROR_INVALID_ARG;
    }
    
    /* 检查是否已存在 */
    FILE *fp = fopen(WHITELIST_FILE, "r");
    if (fp) {
        char line[MAX_LINE_LEN];
        while (fgets(line, sizeof(line), fp)) {
            line[strcspn(line, "\n")] = 0;
            if (strcmp(line, ip) == 0) {
                fclose(fp);
                return SUCCESS;  /* 已存在 */
            }
        }
        fclose(fp);
    }
    
    /* 添加到文件 */
    fp = fopen(WHITELIST_FILE, "a");
    if (!fp) {
        return ERROR_FILE;
    }
    
    fprintf(fp, "%s\n", ip);
    fclose(fp);
    
    return SUCCESS;
}

int whitelist_remove_from_file(const char *ip) {
    if (!ip) {
        return ERROR_INVALID_ARG;
    }
    
    FILE *fp = fopen(WHITELIST_FILE, "r");
    if (!fp) {
        return ERROR_FILE;
    }
    
    char temp_file[MAX_PATH_LEN];
    snprintf(temp_file, sizeof(temp_file), "%s.tmp", WHITELIST_FILE);
    FILE *temp_fp = fopen(temp_file, "w");
    if (!temp_fp) {
        fclose(fp);
        return ERROR_FILE;
    }
    
    char line[MAX_LINE_LEN];
    while (fgets(line, sizeof(line), fp)) {
        line[strcspn(line, "\n")] = 0;
        
        if (strcmp(line, ip) != 0) {
            fprintf(temp_fp, "%s\n", line);
        }
    }
    
    fclose(fp);
    fclose(temp_fp);
    
    rename(temp_file, WHITELIST_FILE);
    return SUCCESS;
}

void whitelist_show(void) {
    msg(C_CYAN, "=== 📋 VIP 白名单列表 ===");
    
    FILE *fp = fopen(WHITELIST_FILE, "r");
    if (!fp || fseek(fp, 0, SEEK_END) == 0) {
        if (fp) fclose(fp);
        printf("(暂无白名单记录)\n");
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
    
    printf("%s%-45s%s\n", C_YELLOW, "IP 地址", C_RESET);
    printf("---------------------------------------------\n");
    
    rewind(fp);
    while (fgets(line, sizeof(line), fp)) {
        line[strcspn(line, "\n")] = 0;
        if (strlen(line) > 0) {
            printf("%-45s\n", line);
        }
    }
    
    fclose(fp);
    printf("\n");
    printf("%s📌 文件位置: %s%s\n", C_CYAN, WHITELIST_FILE, C_RESET);
}

int whitelist_restore(void) {
    FILE *fp = fopen(WHITELIST_FILE, "r");
    if (!fp) {
        return SUCCESS;  /* 文件不存在，无需恢复 */
    }
    
    char line[MAX_LINE_LEN];
    int count = 0;
    
    while (fgets(line, sizeof(line), fp)) {
        line[strcspn(line, "\n")] = 0;
        
        if (strlen(line) == 0) continue;
        
        if (nft_add_to_whitelist(line) == SUCCESS) {
            count++;
        }
    }
    
    fclose(fp);
    
    log_write("[系统恢复] 已从磁盘恢复 %d 个白名单 IP", count);
    
    char message[MAX_LINE_LEN];
    snprintf(message, sizeof(message), "✅ 已从磁盘恢复 %d 个白名单 IP", count);
    msg(C_GREEN, message);
    
    return SUCCESS;
}
