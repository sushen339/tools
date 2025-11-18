#include "pam.h"
#include "ban.h"
#include "ip_utils.h"
#include "whitelist.h"
#include "log.h"
#include <sys/file.h>
#include <fcntl.h>
#include <sys/wait.h>
#include <signal.h>

/* 初始化信号处理（防止僵尸进程） */
static void init_sigchld_handler(void) {
    struct sigaction sa;
    sa.sa_handler = SIG_IGN;  /* 忽略子进程退出信号 */
    sa.sa_flags = SA_NOCLDWAIT; /* 不产生僵尸进程 */
    sigemptyset(&sa.sa_mask);
    sigaction(SIGCHLD, &sa, NULL);
}

/* 异步封禁IP（子进程中执行） */
static void async_ban_ip(const char *ip) {
    /* 设置子进程退出时自动回收，避免僵尸进程 */
    static int initialized = 0;
    if (!initialized) {
        init_sigchld_handler();
        initialized = 1;
    }
    
    pid_t pid = fork();
    
    if (pid < 0) {
        /* fork失败，同步执行 */
        ban_ip(ip, true);
        return;
    }
    
    if (pid == 0) {
        /* 子进程：执行封禁操作 */
        ban_ip(ip, true);
        _exit(0);  /* 子进程退出 */
    }
    
    /* 父进程：立即返回，不等待子进程 */
}

int pam_check_failed_login(void) {
    char *ip = get_remote_ip();
    if (!ip) {
        return SUCCESS;
    }
    
    /* 检查白名单（快速路径） */
    if (is_in_whitelist(ip)) {
        log_write("[白名单放行] IP=%s", ip);
        return SUCCESS;
    }
    
    /* 记录失败次数 */
    int count = get_failure_count(ip);
    count++;
    record_failure(ip);
    
    int max_retries = get_max_retries_from_config();
    log_write("[验证失败] IP=%s (第 %d/%d 次)", ip, count, max_retries);
    
    /* 达到阈值，异步封禁（不阻塞SSH） */
    if (count >= max_retries) {
        async_ban_ip(ip);
        clear_failure_record(ip);
    }
    
    return SUCCESS;
}

int pam_clean_on_success(void) {
    char *ip = get_remote_ip();
    if (!ip) {
        return SUCCESS;
    }
    
    int count = get_failure_count(ip);
    if (count > 0) {
        log_write("[登录成功] IP=%s (计数已重置)", ip);
        clear_failure_record(ip);
    }
    
    return SUCCESS;
}

int record_failure(const char *ip) {
    if (!ip) {
        return ERROR_INVALID_ARG;
    }
    
    /* 确保记录目录存在 */
    mkdir(RECORD_DIR, 0700);
    
    char record_file[MAX_PATH_LEN];
    snprintf(record_file, sizeof(record_file), "%s/%s", RECORD_DIR, ip);
    
    int count = get_failure_count(ip);
    count++;
    
    FILE *fp = fopen(record_file, "w");
    if (!fp) {
        return ERROR_FILE;
    }
    
    fprintf(fp, "%d\n", count);
    fclose(fp);
    
    return SUCCESS;
}

int clear_failure_record(const char *ip) {
    if (!ip) {
        return ERROR_INVALID_ARG;
    }
    
    char record_file[MAX_PATH_LEN];
    snprintf(record_file, sizeof(record_file), "%s/%s", RECORD_DIR, ip);
    
    remove(record_file);
    return SUCCESS;
}

int get_failure_count(const char *ip) {
    if (!ip) {
        return 0;
    }
    
    char record_file[MAX_PATH_LEN];
    snprintf(record_file, sizeof(record_file), "%s/%s", RECORD_DIR, ip);
    
    FILE *fp = fopen(record_file, "r");
    if (!fp) {
        return 0;
    }
    
    int count = 0;
    fscanf(fp, "%d", &count);
    fclose(fp);
    
    return count;
}
