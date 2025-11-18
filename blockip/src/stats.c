#include "stats.h"
#include "nftables.h"
#include "log.h"
#include "geo.h"
#include <ctype.h>

void show_active_bans(void) {
    msg(C_CYAN, "=== 🔥 活跃封禁列表 (最新 5 条) ===");
    
    /* 解析并提取IP和过期时间 */
    char command[MAX_COMMAND_LEN];
    snprintf(command, sizeof(command),
             "{ nft list set %s %s 2>/dev/null; nft list set %s %s 2>/dev/null; } | "
             "grep -E 'expires [0-9]+(s|m|h|d|ms)' | "
             "awk '{ip=\"\"; time=\"\"; for(i=1;i<=NF;i++) { if($i==\"expires\") time=$(i+1); else if(index($i,\".\")>0 || index($i,\":\")>0) ip=$i } if(ip && time) print ip\" \"time}' | "
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
            char ip[MAX_IP_LEN] = {0};
            char time_raw[64] = {0};
            if (sscanf(line, "%s %s", ip, time_raw) == 2) {
                // 解析nft时间格式：86394588ms, 23h59m54s等
                long long total_s = 0;
                char *p = time_raw;
                long long num = 0;
                
                while (*p) {
                    if (isdigit(*p)) {
                        num = num * 10 + (*p - '0');
                    } else {
                        if (*p == 'd') total_s += num * 86400;
                        else if (*p == 'h') total_s += num * 3600;
                        else if (*p == 'm' && *(p+1) == 's') { total_s += num / 1000; p++; }
                        else if (*p == 'm') total_s += num * 60;
                        else if (*p == 's') total_s += num;
                        num = 0;
                    }
                    p++;
                }
                
                long long h = total_s / 3600;
                long long m = (total_s % 3600) / 60;
                long long s = total_s % 60;
                
                char time_str[64];
                if (h > 0) {
                    snprintf(time_str, sizeof(time_str), "%lldh%lldm%llds", h, m, s);
                } else if (m > 0) {
                    snprintf(time_str, sizeof(time_str), "%lldm%llds", m, s);
                } else {
                    snprintf(time_str, sizeof(time_str), "%llds", s);
                }
                
                printf("%-20s %s\n", ip, time_str);
                count++;
            }
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
    
    /* 统计各级网段 */
    struct { char subnet[64]; int count; int mask; } agg[256];
    int agg_count = 0;
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
            continue;
        }
        
        /* 解析IPv4，统计/8, /16, /24 */
        unsigned int a, b, c, d;
        if (sscanf(line, "%u.%u.%u.%u", &a, &b, &c, &d) == 4) {
            char subnet_24[64], subnet_16[64], subnet_8[64];
            snprintf(subnet_24, sizeof(subnet_24), "%u.%u.%u", a, b, c);
            snprintf(subnet_16, sizeof(subnet_16), "%u.%u", a, b);
            snprintf(subnet_8, sizeof(subnet_8), "%u", a);
            
            /* 统计/24 */
            int found = 0;
            for (int i = 0; i < agg_count; ++i) {
                if (agg[i].mask == 24 && strcmp(agg[i].subnet, subnet_24) == 0) {
                    agg[i].count++;
                    found = 1;
                    break;
                }
            }
            if (!found && agg_count < 256) {
                snprintf(agg[agg_count].subnet, sizeof(agg[agg_count].subnet), "%s", subnet_24);
                agg[agg_count].count = 1;
                agg[agg_count].mask = 24;
                agg_count++;
            }
            
            /* 统计/16 */
            found = 0;
            for (int i = 0; i < agg_count; ++i) {
                if (agg[i].mask == 16 && strcmp(agg[i].subnet, subnet_16) == 0) {
                    agg[i].count++;
                    found = 1;
                    break;
                }
            }
            if (!found && agg_count < 256) {
                snprintf(agg[agg_count].subnet, sizeof(agg[agg_count].subnet), "%s", subnet_16);
                agg[agg_count].count = 1;
                agg[agg_count].mask = 16;
                agg_count++;
            }
            
            /* 统计/8 */
            found = 0;
            for (int i = 0; i < agg_count; ++i) {
                if (agg[i].mask == 8 && strcmp(agg[i].subnet, subnet_8) == 0) {
                    agg[i].count++;
                    found = 1;
                    break;
                }
            }
            if (!found && agg_count < 256) {
                snprintf(agg[agg_count].subnet, sizeof(agg[agg_count].subnet), "%s", subnet_8);
                agg[agg_count].count = 1;
                agg[agg_count].mask = 8;
                agg_count++;
            }
        }
    }
    fclose(fp);
    
    /* 排序：先按count降序，再按mask升序 */
    for (int i = 0; i < agg_count - 1; ++i) {
        for (int j = i + 1; j < agg_count; ++j) {
            if (agg[j].count > agg[i].count || 
                (agg[j].count == agg[i].count && agg[j].mask < agg[i].mask)) {
                char tmp_subnet[64];
                int tmp_count = agg[i].count, tmp_mask = agg[i].mask;
                strcpy(tmp_subnet, agg[i].subnet);
                agg[i].count = agg[j].count;
                agg[i].mask = agg[j].mask;
                strcpy(agg[i].subnet, agg[j].subnet);
                agg[j].count = tmp_count;
                agg[j].mask = tmp_mask;
                strcpy(agg[j].subnet, tmp_subnet);
            }
        }
    }
    
    /* 输出聚合结果，只显示count>=2的，并去重：如果大段和小段数量相同则只显示小段 */
    bool has_output = false;
    int show_count = 0;
    int aggregated_count = 0;
    
    for (int i = 0; i < agg_count && show_count < 10; ++i) {
        if (agg[i].count < 2) continue;
        
        /* 检查是否被更精确的段取代（相同count但更小mask） */
        bool replaced = false;
        for (int j = 0; j < agg_count; ++j) {
            if (agg[j].mask > agg[i].mask && agg[j].count == agg[i].count && 
                strncmp(agg[j].subnet, agg[i].subnet, strlen(agg[i].subnet)) == 0) {
                replaced = true;
                break;
            }
        }
        if (replaced) continue;
        
        has_output = true;
        
        /* 检查是否被已显示的更大段覆盖，避免重复计数 */
        bool covered = false;
        for (int k = 0; k < i; ++k) {
            if (agg[k].count >= 2 && agg[k].mask < agg[i].mask) {
                /* 检查k是否也被取代 */
                bool k_replaced = false;
                for (int m = 0; m < agg_count; ++m) {
                    if (agg[m].mask > agg[k].mask && agg[m].count == agg[k].count && 
                        strncmp(agg[m].subnet, agg[k].subnet, strlen(agg[k].subnet)) == 0) {
                        k_replaced = true;
                        break;
                    }
                }
                if (!k_replaced && strncmp(agg[i].subnet, agg[k].subnet, strlen(agg[k].subnet)) == 0) {
                    covered = true;
                    break;
                }
            }
        }
        
        if (!covered) {
            aggregated_count += agg[i].count;
        }
        
        /* 显示段信息 */
        char display_subnet[64];
        const char *suffix = (agg[i].mask == 8) ? ".0.0.0/8" : (agg[i].mask == 16) ? ".0.0/16" : ".0/24";
        snprintf(display_subnet, sizeof(display_subnet), "%s%s", agg[i].subnet, suffix);
        printf("  - %-18s %s(%d 个)%s\n", display_subnet, C_RED, agg[i].count, C_RESET);
        show_count++;
    }
    
    /* 计算散乱IP数量 */
    int total_ipv4 = 0;
    FILE *fp_count = fopen(PERSIST_FILE, "r");
    if (fp_count) {
        char line_tmp[MAX_LINE_LEN];
        while (fgets(line_tmp, sizeof(line_tmp), fp_count)) {
            line_tmp[strcspn(line_tmp, "\n")] = 0;
            if (strlen(line_tmp) > 0) {
                char *pipe = strchr(line_tmp, '|');
                if (pipe) *pipe = '\0';
                if (!strchr(line_tmp, ':')) total_ipv4++;
            }
        }
        fclose(fp_count);
    }
    int scattered_count = total_ipv4 - aggregated_count;
    
    if (!has_output) {
        if (scattered_count > 0) {
            printf("  - (散乱分布 IPv4)       (%d 个)\n", scattered_count);
        } else if (total_ipv4 > 0) {
            printf("  - (散乱分布 IPv4)\n");
        }
    } else if (scattered_count > 0) {
        printf("  - (散乱分布 IPv4)       (%d 个)\n", scattered_count);
    }
    
    if (v6_count > 0) {
        printf("  - (IPv6 地址)           (%d 个)\n", v6_count);
    }
    
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

void show_statistics_watch(bool watch_mode) {
    if (!watch_mode) {
        show_statistics();
        return;
    }
    
    /* 动态监控模式 */
    printf("\033[?25l");  /* 隐藏光标 */
    
    while (1) {
        printf("\033[2J\033[H");  /* 清屏并移到顶部 */
        
        /* 显示时间戳 */
        time_t now = time(NULL);
        struct tm *t = localtime(&now);
        printf("%s[实时监控] 刷新时间: %04d-%02d-%02d %02d:%02d:%02d (按 Ctrl+C 退出)%s\n\n",
               C_YELLOW, t->tm_year + 1900, t->tm_mon + 1, t->tm_mday,
               t->tm_hour, t->tm_min, t->tm_sec, C_RESET);
        
        show_statistics();
        
        sleep(2);  /* 每2秒刷新一次 */
    }
    
    printf("\033[?25h");  /* 恢复光标 */
}
