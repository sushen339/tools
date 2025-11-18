#ifndef WHITELIST_H
#define WHITELIST_H

#include "common.h"
#include <stdbool.h>

/* 检查IP是否在白名单中 */
bool is_in_whitelist(const char *ip);

/* 添加IP到白名单文件 */
int whitelist_add_to_file(const char *ip);

/* 从白名单文件移除IP */
int whitelist_remove_from_file(const char *ip);

/* 显示白名单列表 */
void whitelist_show(void);

/* 恢复白名单到nftables */
int whitelist_restore(void);

#endif /* WHITELIST_H */
