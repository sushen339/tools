#ifndef LOG_H
#define LOG_H

#include "common.h"

/* 日志初始化 */
int log_init(void);

/* 写入日志 */
void log_write(const char *format, ...);

/* 日志轮转 */
void log_rotate(void);

/* 显示最新日志 */
void log_show_recent(int lines);

#endif /* LOG_H */
