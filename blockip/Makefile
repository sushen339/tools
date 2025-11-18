# Block-IP Makefile
# C语言重构版本

CC = gcc
CFLAGS = -Wall -Wextra -O2 -std=c11
LDFLAGS = 
TARGET = bip
INSTALL_PATH = /usr/local/bin

# 源文件目录
SRC_DIR = src
INC_DIR = include
OBJ_DIR = obj

# 源文件
SRCS = $(SRC_DIR)/main.c \
       $(SRC_DIR)/common.c \
       $(SRC_DIR)/log.c \
       $(SRC_DIR)/ip_utils.c \
       $(SRC_DIR)/geo.c \
       $(SRC_DIR)/nftables.c \
       $(SRC_DIR)/whitelist.c \
       $(SRC_DIR)/ban.c \
       $(SRC_DIR)/pam.c \
       $(SRC_DIR)/stats.c \
       $(SRC_DIR)/install.c

# 目标文件
OBJS = $(SRCS:$(SRC_DIR)/%.c=$(OBJ_DIR)/%.o)

# 头文件依赖
DEPS = $(wildcard $(INC_DIR)/*.h)

# 默认目标
all: $(TARGET)

# 创建目标目录
$(OBJ_DIR):
	mkdir -p $(OBJ_DIR)

# 编译目标文件
$(OBJ_DIR)/%.o: $(SRC_DIR)/%.c $(DEPS) | $(OBJ_DIR)
	$(CC) $(CFLAGS) -I$(INC_DIR) -c $< -o $@

# 链接生成可执行文件
$(TARGET): $(OBJS)
	$(CC) $(OBJS) $(LDFLAGS) -o $(TARGET)
	@strip $(TARGET)
	@echo "编译完成: $(TARGET)"

# 安装
install: $(TARGET)
	@if [ $$(id -u) -ne 0 ]; then \
		echo "错误: 需要root权限执行安装"; \
		exit 1; \
	fi
	install -m 755 $(TARGET) $(INSTALL_PATH)/$(TARGET)
	@echo "已安装到: $(INSTALL_PATH)/$(TARGET)"
	@echo "运行 'bip install' 来完成系统配置"

# 卸载
uninstall:
	@if [ $$(id -u) -ne 0 ]; then \
		echo "错误: 需要root权限执行卸载"; \
		exit 1; \
	fi
	$(INSTALL_PATH)/$(TARGET) uninstall || true
	rm -f $(INSTALL_PATH)/$(TARGET)
	@echo "已卸载"

# 清理编译文件
clean:
	rm -rf $(OBJ_DIR) $(TARGET)
	@echo "清理完成"

# 清理所有文件（包括配置）
distclean: clean
	rm -rf /etc/blockip
	rm -f /var/log/bip.log /var/log/bip.log.1
	@echo "深度清理完成"

# 调试版本
debug: CFLAGS += -g -DDEBUG
debug: clean $(TARGET)

# 静态链接版本
static: LDFLAGS += -static
static: clean $(TARGET)

# 显示帮助
help:
	@echo "BIP 构建系统"
	@echo ""
	@echo "可用目标:"
	@echo "  make          - 编译程序"
	@echo "  make install  - 安装到系统 (需要root)"
	@echo "  make uninstall- 从系统卸载 (需要root)"
	@echo "  make clean    - 清理编译文件"
	@echo "  make distclean- 清理所有文件（包括配置）"
	@echo "  make debug    - 编译调试版本"
	@echo "  make static   - 编译静态链接版本"
	@echo "  make help     - 显示此帮助信息"

.PHONY: all install uninstall clean distclean debug static help
