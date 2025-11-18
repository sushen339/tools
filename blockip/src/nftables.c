#include "nftables.h"
#include "log.h"
#include <sys/wait.h>

int check_and_install_nftables(void) {
    /* 检查nft命令是否存在 */
    if (access("/usr/sbin/nft", X_OK) == 0 || access("/sbin/nft", X_OK) == 0) {
        return SUCCESS;
    }
    
    /* 尝试安装nftables */
    FILE *fp = fopen("/etc/os-release", "r");
    if (!fp) {
        return ERROR_FILE;
    }
    
    char line[MAX_LINE_LEN];
    char os_id[64] = {0};
    
    while (fgets(line, sizeof(line), fp)) {
        if (strncmp(line, "ID=", 3) == 0) {
            sscanf(line, "ID=%s", os_id);
            /* 移除引号 */
            char *start = strchr(os_id, '"');
            if (start) {
                start++;
                char *end = strchr(start, '"');
                if (end) *end = '\0';
                memmove(os_id, start, strlen(start) + 1);
            }
            break;
        }
    }
    fclose(fp);
    
    /* 根据发行版安装 */
    if (strcmp(os_id, "debian") == 0 || strcmp(os_id, "ubuntu") == 0 || strcmp(os_id, "kali") == 0) {
        system("apt-get update && apt-get install -y nftables");
    } else if (strcmp(os_id, "centos") == 0 || strcmp(os_id, "rhel") == 0 || strcmp(os_id, "alma") == 0) {
        system("dnf install -y nftables || yum install -y nftables");
    } else if (strcmp(os_id, "alpine") == 0) {
        system("apk add nftables");
    } else {
        return ERROR_FILE;
    }
    
    /* 加载内核模块 */
    system("modprobe nf_tables >/dev/null 2>&1");
    
    /* 启用服务 */
    system("systemctl enable --now nftables >/dev/null 2>&1");
    
    return SUCCESS;
}

int init_nftables_rules(void) {
    char command[MAX_COMMAND_LEN];
    
    /* 创建表 */
    snprintf(command, sizeof(command), "nft add table %s 2>/dev/null", NFT_TABLE);
    system(command);
    
    /* 创建黑名单集合 */
    snprintf(command, sizeof(command),
             "nft add set %s %s '{ type ipv4_addr; flags interval,timeout; }' 2>/dev/null",
             NFT_TABLE, NFT_SET);
    system(command);
    
    snprintf(command, sizeof(command),
             "nft add set %s %s '{ type ipv6_addr; flags interval,timeout; }' 2>/dev/null",
             NFT_TABLE, NFT_SET_V6);
    system(command);
    
    /* 创建白名单集合 */
    snprintf(command, sizeof(command),
             "nft add set %s %s '{ type ipv4_addr; flags interval; }' 2>/dev/null",
             NFT_TABLE, NFT_WHITELIST);
    system(command);
    
    snprintf(command, sizeof(command),
             "nft add set %s %s '{ type ipv6_addr; flags interval; }' 2>/dev/null",
             NFT_TABLE, NFT_WHITELIST_V6);
    system(command);
    
    /* 创建input链 */
    snprintf(command, sizeof(command),
             "nft add chain %s input '{ type filter hook input priority 0; }' 2>/dev/null",
             NFT_TABLE);
    system(command);
    
    /* 添加规则：白名单必须在黑名单之前，使用add按顺序添加 */
    /* 1. IPv4白名单 accept */
    snprintf(command, sizeof(command),
             "nft list chain %s input | grep -q '@%s' || nft add rule %s input ip saddr @%s accept",
             NFT_TABLE, NFT_WHITELIST, NFT_TABLE, NFT_WHITELIST);
    system(command);
    
    /* 2. IPv6白名单 accept */
    snprintf(command, sizeof(command),
             "nft list chain %s input | grep -q '@%s' || nft add rule %s input ip6 saddr @%s accept",
             NFT_TABLE, NFT_WHITELIST_V6, NFT_TABLE, NFT_WHITELIST_V6);
    system(command);
    
    /* 3. IPv4黑名单 drop */
    snprintf(command, sizeof(command),
             "nft list chain %s input | grep -q '@%s' || nft add rule %s input ip saddr @%s drop",
             NFT_TABLE, NFT_SET, NFT_TABLE, NFT_SET);
    system(command);
    
    /* 4. IPv6黑名单 drop */
    snprintf(command, sizeof(command),
             "nft list chain %s input | grep -q '@%s' || nft add rule %s input ip6 saddr @%s drop",
             NFT_TABLE, NFT_SET_V6, NFT_TABLE, NFT_SET_V6);
    system(command);

    /* 5. SSH端口速率（防止TCP洪水，超速临时封禁） */
    int ssh_port = get_ssh_port();
    int rate_limit = get_rate_limit_from_config();
    const char *rate_ban_time = get_rate_ban_time_from_config();
    
    /* 创建SSH端口速率动态集合 */
    snprintf(command, sizeof(command),
             "nft add set %s ssh-ratelimit '{ type ipv4_addr; size 65535; flags dynamic,timeout; }' 2>/dev/null",
             NFT_TABLE);
    system(command);
    snprintf(command, sizeof(command),
             "nft add set %s ssh-ratelimit_v6 '{ type ipv6_addr; size 65535; flags dynamic,timeout; }' 2>/dev/null",
             NFT_TABLE);
    system(command);
    
    /* 删除旧的限速规则（如果存在） */
    snprintf(command, sizeof(command),
             "nft -a list chain %s input 2>/dev/null | grep -E 'tcp dport.*ssh-ratelimit' | awk '{print $NF}' | "
             "xargs -r -I {} nft delete rule %s input handle {}",
             NFT_TABLE, NFT_TABLE);
    system(command);
    
    /* 重建动态集合以清空旧的限速记录 */
    snprintf(command, sizeof(command),
             "nft delete set %s ssh-ratelimit 2>/dev/null; "
             "nft add set %s ssh-ratelimit '{ type ipv4_addr; size 65535; flags dynamic,timeout; }'",
             NFT_TABLE, NFT_TABLE);
    system(command);
    snprintf(command, sizeof(command),
             "nft delete set %s ssh-ratelimit_v6 2>/dev/null; "
             "nft add set %s ssh-ratelimit_v6 '{ type ipv6_addr; size 65535; flags dynamic,timeout; }'",
             NFT_TABLE, NFT_TABLE);
    system(command);
    
    /* 添加新的限速规则：超速IP加入临时封禁集合 */
    snprintf(command, sizeof(command),
             "nft add rule %s input tcp dport %d ct state new "
             "add @ssh-ratelimit { ip saddr timeout %s limit rate over %d/minute burst 5 packets } drop",
             NFT_TABLE, ssh_port, rate_ban_time, rate_limit);
    system(command);
    snprintf(command, sizeof(command),
             "nft add rule %s input tcp dport %d ct state new "
             "add @ssh-ratelimit_v6 { ip6 saddr timeout %s limit rate over %d/minute burst 5 packets } drop",
             NFT_TABLE, ssh_port, rate_ban_time, rate_limit);
    system(command);

    return SUCCESS;
}

int nft_add_to_blacklist(const ip_info_t *ip_info) {
    if (!ip_info) {
        return ERROR_INVALID_ARG;
    }
    
    /* 从配置文件读取封禁时间 */
    const char *ban_time = get_ban_time_from_config();
    
    char element[MAX_LINE_LEN];
    format_nft_element(ip_info->ip, element, sizeof(element), ban_time);
    
    const char *set_name = (ip_info->type == IP_TYPE_V6 || ip_info->type == IP_TYPE_V6_CIDR) 
                          ? NFT_SET_V6 : NFT_SET;
    
    char command[MAX_COMMAND_LEN];
    snprintf(command, sizeof(command),
             "nft add element %s %s '{ %s }' 2>&1",
             NFT_TABLE, set_name, element);
    
    FILE *fp = popen(command, "r");
    if (!fp) {
        return ERROR_FILE;
    }
    
    char output[MAX_LINE_LEN];
    bool need_init = false;
    
    if (fgets(output, sizeof(output), fp)) {
        if (strstr(output, "No such file")) {
            need_init = true;
        }
    }
    pclose(fp);
    
    if (need_init) {
        init_nftables_rules();
        system(command);
    }
    
    return SUCCESS;
}

int nft_remove_from_blacklist(const char *ip) {
    if (!ip) {
        return ERROR_INVALID_ARG;
    }
    
    char element[MAX_LINE_LEN];
    format_nft_element(ip, element, sizeof(element), NULL);
    
    const char *set_name = is_ipv6(ip) ? NFT_SET_V6 : NFT_SET;
    
    char command[MAX_COMMAND_LEN];
    snprintf(command, sizeof(command),
             "nft delete element %s %s '{ %s }' >/dev/null 2>&1",
             NFT_TABLE, set_name, element);
    
    system(command);
    return SUCCESS;
}

int nft_add_to_whitelist(const char *ip) {
    if (!ip) {
        return ERROR_INVALID_ARG;
    }
    
    char element[MAX_LINE_LEN];
    format_nft_element(ip, element, sizeof(element), NULL);
    
    const char *set_name = is_ipv6(ip) ? NFT_WHITELIST_V6 : NFT_WHITELIST;
    
    char command[MAX_COMMAND_LEN];
    snprintf(command, sizeof(command),
             "nft add element %s %s '{ %s }' 2>&1",
             NFT_TABLE, set_name, element);
    
    FILE *fp = popen(command, "r");
    if (!fp) {
        return ERROR_FILE;
    }
    
    char output[MAX_LINE_LEN];
    bool need_init = false;
    
    if (fgets(output, sizeof(output), fp)) {
        if (strstr(output, "No such file")) {
            need_init = true;
        }
    }
    pclose(fp);
    
    if (need_init) {
        init_nftables_rules();
        system(command);
    }
    
    return SUCCESS;
}

int nft_remove_from_whitelist(const char *ip) {
    if (!ip) {
        return ERROR_INVALID_ARG;
    }
    
    char element[MAX_LINE_LEN];
    format_nft_element(ip, element, sizeof(element), NULL);
    
    const char *set_name = is_ipv6(ip) ? NFT_WHITELIST_V6 : NFT_WHITELIST;
    
    char command[MAX_COMMAND_LEN];
    snprintf(command, sizeof(command),
             "nft delete element %s %s '{ %s }' >/dev/null 2>&1",
             NFT_TABLE, set_name, element);
    
    system(command);
    return SUCCESS;
}

int nft_get_set_count(const char *set_name) {
    char command[MAX_COMMAND_LEN];
    snprintf(command, sizeof(command),
             "nft list set %s %s 2>/dev/null | sed 's/,/\\n/g' | sed 's/elements = {//g; s/}//g' | awk '{for(i=1;i<=NF;i++) if($i==\"expires\") print $1}' | wc -l",
             NFT_TABLE, set_name);
    
    FILE *fp = popen(command, "r");
    if (!fp) {
        return 0;
    }
    
    int count = 0;
    fscanf(fp, "%d", &count);
    pclose(fp);
    
    return count;
}

int nft_list_set_elements(const char *set_name, char *buffer, size_t size) {
    if (!set_name || !buffer) {
        return ERROR_INVALID_ARG;
    }
    
    char command[MAX_COMMAND_LEN];
    snprintf(command, sizeof(command),
             "nft list set %s %s 2>/dev/null",
             NFT_TABLE, set_name);
    
    FILE *fp = popen(command, "r");
    if (!fp) {
        return ERROR_FILE;
    }
    
    size_t offset = 0;
    char line[MAX_LINE_LEN];
    
    while (fgets(line, sizeof(line), fp) && offset < size - 1) {
        size_t len = strlen(line);
        if (offset + len < size - 1) {
            memcpy(buffer + offset, line, len);
            offset += len;
        } else {
            break;
        }
    }
    
    buffer[offset] = '\0';
    pclose(fp);
    
    return SUCCESS;
}
