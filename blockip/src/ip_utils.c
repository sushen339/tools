#include "ip_utils.h"
#include <arpa/inet.h>
#include <ctype.h>

bool is_ipv6(const char *ip) {
    if (!ip) return false;
    
    /* 移除CIDR部分 */
    char ip_copy[MAX_IP_LEN];
    strncpy(ip_copy, ip, sizeof(ip_copy) - 1);
    ip_copy[sizeof(ip_copy) - 1] = '\0';
    
    char *slash = strchr(ip_copy, '/');
    if (slash) *slash = '\0';
    
    return strchr(ip_copy, ':') != NULL;
}

bool is_cidr(const char *ip) {
    return strchr(ip, '/') != NULL;
}

int parse_ip_info(const char *input, ip_info_t *info) {
    if (!input || !info) {
        return ERROR_INVALID_ARG;
    }
    
    memset(info, 0, sizeof(ip_info_t));
    strncpy(info->ip, input, sizeof(info->ip) - 1);
    
    /* 检查是否是CIDR */
    char *slash = strchr(info->ip, '/');
    if (slash) {
        *slash = '\0';
        info->cidr_mask = atoi(slash + 1);
        
        if (is_ipv6(info->ip)) {
            info->type = IP_TYPE_V6_CIDR;
        } else {
            info->type = IP_TYPE_V4_CIDR;
        }
        *slash = '/';  /* 恢复 */
    } else {
        if (is_ipv6(info->ip)) {
            info->type = IP_TYPE_V6;
        } else {
            info->type = IP_TYPE_V4;
        }
    }
    
    return SUCCESS;
}

char* get_remote_ip(void) {
    static char ip[MAX_IP_LEN];
    char *env_ip = NULL;
    
    env_ip = getenv("PAM_RHOST");
    if (!env_ip) {
        env_ip = getenv("RHOST");
    }
    
    if (env_ip) {
        strncpy(ip, env_ip, sizeof(ip) - 1);
        ip[sizeof(ip) - 1] = '\0';
        return ip;
    }
    
    return NULL;
}

bool validate_ip_format(const char *ip) {
    if (!ip) return false;
    
    char ip_copy[MAX_IP_LEN];
    strncpy(ip_copy, ip, sizeof(ip_copy) - 1);
    ip_copy[sizeof(ip_copy) - 1] = '\0';
    
    /* 检查CIDR */
    char *slash = strchr(ip_copy, '/');
    if (slash) {
        *slash = '\0';
        int mask = atoi(slash + 1);
        
        if (is_ipv6(ip_copy)) {
            if (mask < 0 || mask > 128) return false;
        } else {
            if (mask < 0 || mask > 32) return false;
        }
    }
    
    /* 验证IP地址 */
    struct sockaddr_in sa;
    struct sockaddr_in6 sa6;
    
    if (inet_pton(AF_INET, ip_copy, &(sa.sin_addr)) == 1) {
        return true;
    }
    if (inet_pton(AF_INET6, ip_copy, &(sa6.sin6_addr)) == 1) {
        return true;
    }
    
    return false;
}

void format_nft_element(const char *ip, char *output, size_t size, const char *timeout) {
    if (!ip || !output) return;
    
    char element[MAX_LINE_LEN];
    
    if (is_cidr(ip)) {
        strncpy(element, ip, sizeof(element) - 1);
    } else if (is_ipv6(ip)) {
        snprintf(element, sizeof(element), "%s/128", ip);
    } else {
        snprintf(element, sizeof(element), "%s/32", ip);
    }
    
    if (timeout && strlen(timeout) > 0) {
        snprintf(output, size, "%s timeout %s", element, timeout);
    } else {
        snprintf(output, size, "%s", element);
    }
}

bool ip_matches_whitelist_entry(const char *ip, const char *whitelist_entry) {
    if (!ip || !whitelist_entry) return false;
    
    /* 完全匹配 */
    if (strcmp(ip, whitelist_entry) == 0) {
        return true;
    }
    
    /* CIDR匹配 */
    if (strchr(whitelist_entry, '/')) {
        char wl_copy[MAX_IP_LEN];
        strncpy(wl_copy, whitelist_entry, sizeof(wl_copy) - 1);
        wl_copy[sizeof(wl_copy) - 1] = '\0';
        
        char *slash = strchr(wl_copy, '/');
        if (slash) {
            *slash = '\0';
            int mask = atoi(slash + 1);
            
            /* 简单的IPv4段匹配 */
            if (!is_ipv6(ip)) {
                char ip_prefix[MAX_IP_LEN];
                strncpy(ip_prefix, ip, sizeof(ip_prefix) - 1);
                
                if (mask == 8) {
                    /* 匹配 A.*.*.* */
                    char *dot = strchr(ip_prefix, '.');
                    if (dot) *dot = '\0';
                    return strncmp(ip, wl_copy, strlen(ip_prefix)) == 0;
                } else if (mask == 16) {
                    /* 匹配 A.B.*.* */
                    char *dot1 = strchr(ip_prefix, '.');
                    if (dot1) {
                        char *dot2 = strchr(dot1 + 1, '.');
                        if (dot2) *dot2 = '\0';
                    }
                    return strncmp(ip, wl_copy, strlen(ip_prefix)) == 0;
                } else if (mask == 24) {
                    /* 匹配 A.B.C.* */
                    char *dot1 = strchr(ip_prefix, '.');
                    if (dot1) {
                        char *dot2 = strchr(dot1 + 1, '.');
                        if (dot2) {
                            char *dot3 = strchr(dot2 + 1, '.');
                            if (dot3) *dot3 = '\0';
                        }
                    }
                    return strncmp(ip, wl_copy, strlen(ip_prefix)) == 0;
                }
            }
        }
    }
    
    return false;
}
