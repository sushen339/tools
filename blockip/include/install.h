#ifndef INSTALL_H
#define INSTALL_H

#include "common.h"
#include <sys/stat.h>

/* 安装服务 */
int install_service(void);

/* 卸载服务 */
int uninstall_service(void);

/* 配置PAM钩子 */
int setup_pam_hooks(void);

/* 移除PAM钩子 */
int remove_pam_hooks(void);

/* 创建systemd服务 */
int create_systemd_service(void);

#endif /* INSTALL_H */
