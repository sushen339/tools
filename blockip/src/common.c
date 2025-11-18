#include "common.h"
#include <stdbool.h>

void msg(const char *color, const char *message) {
    printf("%s%s%s\n", color, message, C_RESET);
}

int check_root(void) {
    if (getuid() != 0) {
        msg(C_RED, "❌ 需要 root 权限");
        return ERROR_PERMISSION;
    }
    return SUCCESS;
}

void get_timestamp(char *buffer, size_t size) {
    time_t now = time(NULL);
    struct tm *tm_info = localtime(&now);
    strftime(buffer, size, "%Y-%m-%d %H:%M:%S", tm_info);
}

const char* get_ban_time_from_config(void) {
    static char ban_time[32] = {0};
    
    FILE *fp = fopen(CONFIG_FILE, "r");
    if (!fp) {
        /* 配置文件不存在，返回默认值 */
        return DEFAULT_BAN_TIME;
    }
    
    char line[MAX_LINE_LEN];
    while (fgets(line, sizeof(line), fp)) {
        /* 跳过注释和空行 */
        if (line[0] == '#' || line[0] == '\n') {
            continue;
        }
        
        /* 解析 BAN_TIME=xxx */
        if (strncmp(line, "BAN_TIME=", 9) == 0) {
            char *value = line + 9;
            /* 去除换行符和空白 */
            char *p = value;
            while (*p && *p != '\n' && *p != '\r') p++;
            *p = '\0';
            
            /* 去除前导空白 */
            while (*value == ' ' || *value == '\t') value++;
            
            if (strlen(value) > 0) {
                strncpy(ban_time, value, sizeof(ban_time) - 1);
                ban_time[sizeof(ban_time) - 1] = '\0';
                fclose(fp);
                return ban_time;
            }
        }
    }
    
    fclose(fp);
    return DEFAULT_BAN_TIME;
}

int save_ban_time_to_config(const char *ban_time) {
    if (!ban_time) {
        return ERROR_INVALID_ARG;
    }
    
    /* 创建配置目录 */
    mkdir(CONFIG_DIR, 0700);
    
    /* 读取现有配置 */
    FILE *fp = fopen(CONFIG_FILE, "r");
    char temp_file[MAX_PATH_LEN];
    snprintf(temp_file, sizeof(temp_file), "%s.tmp", CONFIG_FILE);
    FILE *temp_fp = fopen(temp_file, "w");
    
    if (!temp_fp) {
        if (fp) fclose(fp);
        return ERROR_FILE;
    }
    
    bool found = false;
    bool has_header = false;
    
    if (fp) {
        char line[MAX_LINE_LEN];
        while (fgets(line, sizeof(line), fp)) {
            if (line[0] == '#') {
                has_header = true;
            }
            
            if (strncmp(line, "BAN_TIME=", 9) == 0) {
                fprintf(temp_fp, "BAN_TIME=%s\n", ban_time);
                found = true;
            } else {
                fputs(line, temp_fp);
            }
        }
        fclose(fp);
    }
    
    /* 如果没有找到 BAN_TIME，添加新配置 */
    if (!found) {
        /* 如果是新文件，添加完整头部 */
        if (!has_header && access(CONFIG_FILE, F_OK) != 0) {
            fprintf(temp_fp, "# Block-IP Configuration\n");
            fprintf(temp_fp, "# Ban time format: Xh (hours), Xm (minutes), or empty for permanent\n");
            fprintf(temp_fp, "# Examples: 24h, 12h, 1h, 30m, or empty string for permanent ban\n");
            fprintf(temp_fp, "# Max retries: 1-10, default is 3\n\n");
        }
        fprintf(temp_fp, "BAN_TIME=%s\n", ban_time);
        /* 如果是新文件，也添加默认的 MAX_RETRIES */
        if (!has_header && access(CONFIG_FILE, F_OK) != 0) {
            fprintf(temp_fp, "MAX_RETRIES=%d\n", DEFAULT_MAX_RETRIES);
        }
    }
    
    fclose(temp_fp);
    chmod(temp_file, 0600);
    rename(temp_file, CONFIG_FILE);
    
    return SUCCESS;
}

int get_max_retries_from_config(void) {
    FILE *fp = fopen(CONFIG_FILE, "r");
    if (!fp) {
        return DEFAULT_MAX_RETRIES;  /* 返回默认值 */
    }
    
    char line[MAX_LINE_LEN];
    while (fgets(line, sizeof(line), fp)) {
        if (line[0] == '#' || line[0] == '\n') {
            continue;
        }
        
        if (strncmp(line, "MAX_RETRIES=", 12) == 0) {
            int retries = atoi(line + 12);
            fclose(fp);
            return (retries > 0 && retries <= 10) ? retries : DEFAULT_MAX_RETRIES;
        }
    }
    
    fclose(fp);
    return DEFAULT_MAX_RETRIES;
}

int save_max_retries_to_config(int max_retries) {
    if (max_retries <= 0 || max_retries > 10) {
        return ERROR_INVALID_ARG;
    }
    
    mkdir(CONFIG_DIR, 0700);
    
    FILE *fp = fopen(CONFIG_FILE, "r");
    char temp_file[MAX_PATH_LEN];
    snprintf(temp_file, sizeof(temp_file), "%s.tmp", CONFIG_FILE);
    FILE *temp_fp = fopen(temp_file, "w");
    
    if (!temp_fp) {
        if (fp) fclose(fp);
        return ERROR_FILE;
    }
    
    bool found = false;
    bool has_header = false;
    
    if (fp) {
        char line[MAX_LINE_LEN];
        while (fgets(line, sizeof(line), fp)) {
            if (line[0] == '#') {
                has_header = true;
            }
            
            if (strncmp(line, "MAX_RETRIES=", 12) == 0) {
                fprintf(temp_fp, "MAX_RETRIES=%d\n", max_retries);
                found = true;
            } else {
                fputs(line, temp_fp);
            }
        }
        fclose(fp);
    }
    
    /* 如果没有找到 MAX_RETRIES，添加新配置 */
    if (!found) {
        /* 如果是新文件，添加完整头部 */
        if (!has_header && access(CONFIG_FILE, F_OK) != 0) {
            fprintf(temp_fp, "# Block-IP Configuration\n");
            fprintf(temp_fp, "# Ban time format: Xh (hours), Xm (minutes), or empty for permanent\n");
            fprintf(temp_fp, "# Max retries: 1-10, default is 3\n\n");
            fprintf(temp_fp, "BAN_TIME=%s\n", DEFAULT_BAN_TIME);
        }
        fprintf(temp_fp, "MAX_RETRIES=%d\n", max_retries);
    }
    
    fclose(temp_fp);
    chmod(temp_file, 0600);
    rename(temp_file, CONFIG_FILE);
    
    return SUCCESS;
}
