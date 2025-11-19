#ifndef COMMON_H
#define COMMON_H

#define _POSIX_C_SOURCE 200809L

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <time.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <ctype.h>

/* 配置常量 */

#define BIP_VERSION "v25.11.19"
#define CONFIG_DIR "/etc/bip"
#define CONFIG_FILE CONFIG_DIR "/config"
#define LOG_FILE "/var/log/bip.log"
#define MAX_LOG_SIZE 10485760  // 10MB
#define DEFAULT_MAX_RETRIES 3
#define DEFAULT_BAN_TIME "24h"
#define DEFAULT_RATE_LIMIT 10
#define DEFAULT_RATE_BAN_TIME "10m"
#define RECORD_DIR CONFIG_DIR "/counts"
#define PERSIST_FILE CONFIG_DIR "/blacklist"
#define WHITELIST_FILE CONFIG_DIR "/whitelist"
#define INSTALL_PATH "/usr/local/bin/bip"
#define NFT_TABLE "inet bip"
#define NFT_SET "blacklist"
#define NFT_SET_V6 "blacklist_v6"
#define NFT_WHITELIST "whitelist"
#define NFT_WHITELIST_V6 "whitelist_v6"

/* 缓冲区大小 */
#define MAX_LINE_LEN 512
#define MAX_IP_LEN 128
#define MAX_COUNTRY_CODE 8
#define MAX_COMMAND_LEN 1024
#define MAX_PATH_LEN 256

/* 颜色定义 */
#define C_RESET "\033[0m"
#define C_GREEN "\033[32m"
#define C_CYAN "\033[36m"
#define C_YELLOW "\033[33m"
#define C_RED "\033[31m"

/* 错误码 */
#define SUCCESS 0
#define ERROR_PERMISSION -1
#define ERROR_FILE -2
#define ERROR_NETWORK -3
#define ERROR_INVALID_ARG -4

/* 工具宏 */
#define ARRAY_SIZE(arr) (sizeof(arr) / sizeof((arr)[0]))

/* 打印消息 */
void msg(const char *color, const char *message);

/* 检查root权限 */
int check_root(void);

/* 获取当前时间戳字符串 */
void get_timestamp(char *buffer, size_t size);

/* 读取配置文件中的封禁时间 */
const char* get_ban_time_from_config(void);

/* 保存封禁时间到配置文件 */
int save_ban_time_to_config(const char *ban_time);

/* 读取配置文件中的最大重试次数 */
int get_max_retries_from_config(void);

/* 保存最大重试次数到配置文件 */
int save_max_retries_to_config(int max_retries);

/* 获取SSH端口 */
int get_ssh_port(void);

/* 获取SSH端口速率 */
int get_rate_limit_from_config(void);

/* 保存SSH端口速率 */
int save_rate_limit_to_config(int rate_limit);

/* 获取速率限制封禁时间 */
const char* get_rate_ban_time_from_config(void);

/* 保存速率限制封禁时间 */
int save_rate_ban_time_to_config(const char *ban_time);

#endif /* COMMON_H */
