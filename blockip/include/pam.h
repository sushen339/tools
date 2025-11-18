#ifndef PAM_H
#define PAM_H

#include "common.h"

/* PAM检查：处理登录失败 */
int pam_check_failed_login(void);

/* PAM清理：处理登录成功 */
int pam_clean_on_success(void);

/* 记录失败次数 */
int record_failure(const char *ip);

/* 清除失败记录 */
int clear_failure_record(const char *ip);

/* 获取失败次数 */
int get_failure_count(const char *ip);

#endif /* PAM_H */
