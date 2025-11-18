#ifndef NFTABLES_H
#define NFTABLES_H

#include "common.h"
#include "ip_utils.h"
#include <stdbool.h>

/* 检查并安装nftables环境 */
int check_and_install_nftables(void);

/* 初始化nftables规则 */
int init_nftables_rules(void);

/* 添加IP到nftables黑名单 */
int nft_add_to_blacklist(const ip_info_t *ip_info);

/* 从nftables黑名单移除IP */
int nft_remove_from_blacklist(const char *ip);

/* 添加IP到nftables白名单 */
int nft_add_to_whitelist(const char *ip);

/* 从nftables白名单移除IP */
int nft_remove_from_whitelist(const char *ip);

/* 获取nftables集合中的元素数量 */
int nft_get_set_count(const char *set_name);

/* 列出nftables集合中的元素 */
int nft_list_set_elements(const char *set_name, char *buffer, size_t size);

#endif /* NFTABLES_H */
