#ifndef GEO_H
#define GEO_H

#include "common.h"

/* 查询IP的国家代码 */
int query_country_code(const char *ip, char *country_code, size_t size);

/* 获取国家名称 */
const char* get_country_name(const char *country_code);

/* 补充持久化文件中缺失的国家信息 */
void supplement_country_info(const char *current_ip);

#endif /* GEO_H */
