#ifndef BAN_H
#define BAN_H

#include "common.h"
#include "ip_utils.h"
#include <stdbool.h>

/* 封禁IP */
int ban_ip(const char *ip, bool save_to_disk);

/* 解封IP */
int unban_ip(const char *ip);

/* 添加到持久化列表 */
int persist_add_ip(const char *ip, const char *country_code);

/* 从持久化列表移除 */
int persist_remove_ip(const char *ip);

/* 更新IP的国家信息 */
int update_ip_country(const char *ip, const char *country_code);

/* 恢复持久化列表到nftables */
int restore_from_persist(void);

/* 显示持久化列表 */
void show_persist_list(void);

#endif /* BAN_H */
