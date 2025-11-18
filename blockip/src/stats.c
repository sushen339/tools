#include "stats.h"
#include "nftables.h"
#include "log.h"
#include "geo.h"
#include <ctype.h>

void show_active_bans(void) {
    msg(C_CYAN, "=== 🔥 活跃封禁列表 (最新 5 条) ===");
    
    /* 获取IPv4和IPv6黑名单 */
    char buffer_v4[8192] = {0};
    char buffer_v6[8192] = {0};
    
    nft_list_set_elements(NFT_SET, buffer_v4, sizeof(buffer_v4));
    nft_list_set_elements(NFT_SET_V6, buffer_v6, sizeof(buffer_v6));
    
    /* 解析并提取IP和过期时间 */
    char command[MAX_COMMAND_LEN];
    snprintf(command, sizeof(command),
             "{ nft list set %s %s 2>/dev/null; nft list set %s %s 2>/dev/null; } | "
             "sed 's/,/\\n/g' | sed 's/elements = {//g; s/}//g' | "
             "awk '{for(i=1;i<=NF;i++) if($i==\"expires\") {time=$(i+1); gsub(\"ms\",\"\",time); print $1, time}}' | "
             "sort -t' ' -k2 | tail -n 5",
             NFT_TABLE, NFT_SET, NFT_TABLE, NFT_SET_V6);
    
    FILE *fp = popen(command, "r");
    if (!fp) {
        printf("(无法获取数据)\n\n");
        return;
    }
    
    char line[MAX_LINE_LEN];
    int count = 0;
    
    printf("%s%-20s %-15s%s\n", C_YELLOW, "IP 地址", "剩余时间", C_RESET);
    printf("-------------------------------------\n");
    
    while (fgets(line, sizeof(line), fp)) {
        line[strcspn(line, "\n")] = 0;
        if (strlen(line) > 0) {
            printf("%s\n", line);
            count++;
        }
    }
    
    pclose(fp);
    
    if (count == 0) {
        printf("(目前没有被封禁的 IP)\n");
    }
    
    printf("\n");
}

void show_subnet_aggregation(void) {
    msg(C_CYAN, "=== 📊 攻击源聚合统计 (自动识别 IP 段) ===");
    
    FILE *fp = fopen(PERSIST_FILE, "r");
    if (!fp) {
        printf("(无数据)\n\n");
        return;
    }
    
    /* 创建临时文件存储IPv4地址 */
    char temp_v4_file[MAX_PATH_LEN];
    snprintf(temp_v4_file, sizeof(temp_v4_file), "/tmp/blockip_v4_$$");
    FILE *temp_v4 = fopen(temp_v4_file, "w");
    
    int v6_count = 0;
    char line[MAX_LINE_LEN];
    
    while (fgets(line, sizeof(line), fp)) {
        line[strcspn(line, "\n")] = 0;
        if (strlen(line) == 0) continue;
        
        /* 提取IP部分 */
        char *pipe = strchr(line, '|');
        if (pipe) *pipe = '\0';
        
        if (strchr(line, ':')) {
            v6_count++;
        } else if (temp_v4) {
            fprintf(temp_v4, "%s\n", line);
        }
    }
    
    fclose(fp);
    if (temp_v4) fclose(temp_v4);
    
    /* 聚合分析 */
    char command[MAX_COMMAND_LEN * 2];
    snprintf(command, sizeof(command),
             "if [ -f %s ]; then "
             "  cat %s | cut -d. -f1-3 | sort | uniq -c | awk '$1>=2 {printf \"%%d|%%s|24\\n\", $1, $2}' > /tmp/agg24_$$; "
             "  cat %s | cut -d. -f1-2 | sort | uniq -c | awk '$1>=2 {printf \"%%d|%%s|16\\n\", $1, $2}' > /tmp/agg16_$$; "
             "  cat %s | cut -d. -f1 | sort | uniq -c | awk '$1>=2 {printf \"%%d|%%s|8\\n\", $1, $2}' > /tmp/agg8_$$; "
             "  cat /tmp/agg24_$$ /tmp/agg16_$$ /tmp/agg8_$$ | sort -t'|' -k1,1rn -k3,3n | head -n 10; "
             "  rm -f /tmp/agg24_$$ /tmp/agg16_$$ /tmp/agg8_$$; "
             "fi",
             temp_v4_file, temp_v4_file, temp_v4_file, temp_v4_file);
    
    fp = popen(command, "r");
    bool has_output = false;
    
    if (fp) {
        while (fgets(line, sizeof(line), fp)) {
            line[strcspn(line, "\n")] = 0;
            
            int count, mask;
            char subnet[MAX_IP_LEN];
            
            if (sscanf(line, "%d|%[^|]|%d", &count, subnet, &mask) == 3) {
                has_output = true;
                if (mask == 8) {
                    printf("  - %-18s %s(%d 个)%s\n", 
                           strcat(subnet, ".0.0.0/8"), C_RED, count, C_RESET);
                } else if (mask == 16) {
                    printf("  - %-18s %s(%d 个)%s\n", 
                           strcat(subnet, ".0.0/16"), C_RED, count, C_RESET);
                } else if (mask == 24) {
                    printf("  - %-18s %s(%d 个)%s\n", 
                           strcat(subnet, ".0/24"), C_RED, count, C_RESET);
                }
            }
        }
        pclose(fp);
    }
    
    if (!has_output) {
        printf("  - (散乱分布 IPv4)\n");
    }
    
    if (v6_count > 0) {
        printf("  - (IPv6 地址)          (%d 个)\n", v6_count);
    }
    
    remove(temp_v4_file);
    printf("\n");
}

void show_country_stats(void) {
    msg(C_CYAN, "=== 🌍 攻击源国家/地区统计 ===");
    FILE *fp = fopen(PERSIST_FILE, "r");
    if (!fp) {
        printf("(暂无数据)\n\n");
        return;
    }
    struct { char code[MAX_COUNTRY_CODE]; int count; } stats[128];
    int stat_count = 0;
    char line[MAX_LINE_LEN];
    bool has_data = false;
    while (fgets(line, sizeof(line), fp)) {
        line[strcspn(line, "\n")] = 0;
        char *pipe = strchr(line, '|');
        if (pipe && strlen(pipe + 1) > 0) {
            has_data = true;
            char *code = pipe + 1;
            int found = 0;
            for (int i = 0; i < stat_count; ++i) {
                if (strcmp(stats[i].code, code) == 0) {
                    stats[i].count++;
                    found = 1;
                    break;
                }
            }
            if (!found && stat_count < 128) {
                strncpy(stats[stat_count].code, code, MAX_COUNTRY_CODE-1);
                stats[stat_count].code[MAX_COUNTRY_CODE-1] = 0;
                stats[stat_count].count = 1;
                stat_count++;
            }
        }
    }
    fclose(fp);
    if (!has_data) {
        printf("(暂无国家信息)\n\n");
        return;
    }
    // 排序
    for (int i = 0; i < stat_count-1; ++i) {
        for (int j = i+1; j < stat_count; ++j) {
            if (stats[j].count > stats[i].count) {
                char tmp_code[MAX_COUNTRY_CODE];
                int tmp_count = stats[i].count;
                strcpy(tmp_code, stats[i].code);
                stats[i].count = stats[j].count;
                strncpy(stats[i].code, stats[j].code, MAX_COUNTRY_CODE);
                stats[j].count = tmp_count;
                strncpy(stats[j].code, tmp_code, MAX_COUNTRY_CODE);
            }
        }
    }
    int show_n = stat_count < 9 ? stat_count : 9;
    for (int i = 0; i < show_n; ++i) {
        printf("  - %s %s(%d 个)%s\n", get_country_name(stats[i].code), C_RED, stats[i].count, C_RESET);
    }
    printf("\n");
}

void show_statistics(void) {
    int nft_v4_count = nft_get_set_count(NFT_SET);
    int nft_v6_count = nft_get_set_count(NFT_SET_V6);
    int nft_count = nft_v4_count + nft_v6_count;
    
    int local_count = 0;
    FILE *fp = fopen(PERSIST_FILE, "r");
    if (fp) {
        char line[MAX_LINE_LEN];
        while (fgets(line, sizeof(line), fp)) {
            if (strlen(line) > 1) local_count++;
        }
        fclose(fp);
    }
    
    msg(C_CYAN, "=== 🛡️  BIP 防护概览 ===");
    printf("当前生效: %s%d%s 条  |  本地记录: %s%d%s 条\n\n",
           C_GREEN, nft_count, C_RESET,
           C_YELLOW, local_count, C_RESET);
    
    show_active_bans();
    show_subnet_aggregation();
    show_country_stats();
    
    msg(C_CYAN, "=== 📝 最新拦截日志 (Last 10) ===");
    log_show_recent(10);
    printf("\n");
}
