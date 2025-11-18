#include "geo.h"
#include "log.h"
#include <ctype.h>

/* 国家代码映射表 */
static const struct {
    const char *code;
    const char *name;
} country_map[] = {
    {"CN", "中国"},
    {"US", "美国"},
    {"RU", "俄罗斯"},
    {"MY", "马来西亚"},
    {"NL", "荷兰"},
    {"DE", "德国"},
    {"GB", "英国"},
    {"FR", "法国"},
    {"JP", "日本"},
    {"KR", "韩国"},
    {"SG", "新加坡"},
    {"HK", "香港"},
    {"TW", "台湾"},
    {"IN", "印度"},
    {"BR", "巴西"},
    {"CA", "加拿大"},
    {"AU", "澳大利亚"},
    {"IT", "意大利"},
    {"ES", "西班牙"},
    {"SE", "瑞典"},
    {"PL", "波兰"},
    {"UA", "乌克兰"},
    {"TR", "土耳其"},
    {"ID", "印度尼西亚"},
    {"TH", "泰国"},
    {"VN", "越南"},
    {"MX", "墨西哥"},
    {"AR", "阿根廷"},
    {"CL", "智利"},
    {"RO", "罗马尼亚"},
    {"CZ", "捷克"}
};

int query_country_code(const char *ip, char *country_code, size_t size) {
    if (!ip || !country_code) {
        return ERROR_INVALID_ARG;
    }
    
    char command[MAX_COMMAND_LEN];
    snprintf(command, sizeof(command),
             "curl -s --max-time 2 \"https://ipinfo.io/%s/country\" 2>/dev/null | tr -d '\\n\\r '",
             ip);
    
    FILE *fp = popen(command, "r");
    if (!fp) {
        return ERROR_NETWORK;
    }
    
    char result[16] = {0};
    if (fgets(result, sizeof(result), fp)) {
        /* 去除空白字符 */
        char *p = result;
        while (*p && isspace(*p)) p++;
        
        if (strlen(p) == 2 && isalpha(p[0]) && isalpha(p[1])) {
            strncpy(country_code, p, size - 1);
            country_code[size - 1] = '\0';
            pclose(fp);
            return SUCCESS;
        }
    }
    
    pclose(fp);
    return ERROR_NETWORK;
}

const char* get_country_name(const char *country_code) {
    if (!country_code) return country_code;
    
    for (size_t i = 0; i < ARRAY_SIZE(country_map); i++) {
        if (strcmp(country_map[i].code, country_code) == 0) {
            return country_map[i].name;
        }
    }
    
    return country_code;
}

void supplement_country_info(const char *current_ip) {
    FILE *fp = fopen(PERSIST_FILE, "r");
    if (!fp) return;
    
    char line[MAX_LINE_LEN];
    int update_count = 0;
    const int MAX_UPDATES = 3;
    
    /* 创建临时文件 */
    char temp_file[MAX_PATH_LEN];
    snprintf(temp_file, sizeof(temp_file), "%s.tmp", PERSIST_FILE);
    FILE *temp_fp = fopen(temp_file, "w");
    if (!temp_fp) {
        fclose(fp);
        return;
    }
    
    while (fgets(line, sizeof(line), fp) && update_count < MAX_UPDATES) {
        /* 去除换行符 */
        line[strcspn(line, "\n")] = 0;
        
        if (strlen(line) == 0) continue;
        
        /* 检查是否已有国家信息 */
        if (strchr(line, '|')) {
            fprintf(temp_fp, "%s\n", line);
            continue;
        }
        
        /* 检查是否是IPv6或CIDR */
        if (strchr(line, ':') || strchr(line, '/')) {
            fprintf(temp_fp, "%s\n", line);
            continue;
        }
        
        /* 跳过当前正在处理的IP */
        if (current_ip && strcmp(line, current_ip) == 0) {
            fprintf(temp_fp, "%s\n", line);
            continue;
        }
        
        /* 查询国家信息 */
        char country_code[MAX_COUNTRY_CODE];
        if (query_country_code(line, country_code, sizeof(country_code)) == SUCCESS) {
            fprintf(temp_fp, "%s|%s\n", line, country_code);
            log_write("[补充地区] IP=%s 国家=%s", line, get_country_name(country_code));
            update_count++;
        } else {
            fprintf(temp_fp, "%s\n", line);
        }
    }
    
    /* 复制剩余内容 */
    while (fgets(line, sizeof(line), fp)) {
        fputs(line, temp_fp);
    }
    
    fclose(fp);
    fclose(temp_fp);
    
    /* 替换原文件 */
    rename(temp_file, PERSIST_FILE);
}
