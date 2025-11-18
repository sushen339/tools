#include "log.h"
#include <stdarg.h>
#include <fcntl.h>
#include <sys/file.h>

int log_init(void) {
    FILE *fp = fopen(LOG_FILE, "a");
    if (!fp) {
        return ERROR_FILE;
    }
    chmod(LOG_FILE, 0666);
    fclose(fp);
    return SUCCESS;
}

void log_rotate(void) {
    struct stat st;
    if (stat(LOG_FILE, &st) != 0) {
        return;
    }
    
    if (st.st_size >= MAX_LOG_SIZE) {
        char backup_file[MAX_PATH_LEN];
        snprintf(backup_file, sizeof(backup_file), "%s.1", LOG_FILE);
        
        remove(backup_file);
        rename(LOG_FILE, backup_file);
        
        FILE *fp = fopen(LOG_FILE, "w");
        if (fp) {
            chmod(LOG_FILE, 0666);
            fclose(fp);
        }
    }
}

void log_write(const char *format, ...) {
    log_rotate();
    
    FILE *fp = fopen(LOG_FILE, "a");
    if (!fp) {
        return;
    }
    
    char timestamp[64];
    get_timestamp(timestamp, sizeof(timestamp));
    
    fprintf(fp, "[%s] ", timestamp);
    
    va_list args;
    va_start(args, format);
    vfprintf(fp, format, args);
    va_end(args);
    
    fprintf(fp, "\n");
    fclose(fp);
}

void log_show_recent(int lines) {
    char command[MAX_COMMAND_LEN];
    snprintf(command, sizeof(command), "tail -n %d %s 2>/dev/null", lines, LOG_FILE);
    system(command);
}
