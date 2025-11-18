#ifndef IP_UTILS_H
#define IP_UTILS_H

#include "common.h"
#include <stdbool.h>

/* IP类型 */
typedef enum {
    IP_TYPE_UNKNOWN = 0,
    IP_TYPE_V4,
    IP_TYPE_V6,
    IP_TYPE_V4_CIDR,
    IP_TYPE_V6_CIDR
} ip_type_t;

/* IP信息结构 */
typedef struct {
    char ip[MAX_IP_LEN];
    char country_code[MAX_COUNTRY_CODE];
    ip_type_t type;
    int cidr_mask;
} ip_info_t;

/* 判断是否为IPv6 */
bool is_ipv6(const char *ip);

/* 判断是否为CIDR格式 */
bool is_cidr(const char *ip);

/* 解析IP信息 */
int parse_ip_info(const char *input, ip_info_t *info);

/* 获取当前连接IP */
char* get_remote_ip(void);

/* 验证IP格式 */
bool validate_ip_format(const char *ip);

/* 格式化IP为nftables元素 */
void format_nft_element(const char *ip, char *output, size_t size, const char *timeout);

/* 检查IP是否匹配白名单 */
bool ip_matches_whitelist_entry(const char *ip, const char *whitelist_entry);

#endif /* IP_UTILS_H */
