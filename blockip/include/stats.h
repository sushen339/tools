#ifndef STATS_H
#define STATS_H

#include "common.h"

/* 显示完整统计信息 */
void show_statistics(void);

/* 显示活跃封禁列表 */
void show_active_bans(void);

/* 显示国家统计 */
void show_country_stats(void);

/* 显示IP段聚合统计 */
void show_subnet_aggregation(void);

#endif /* STATS_H */
