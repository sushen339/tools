# BIP (Block-IP) - C语言实现

基于 nftables 的自动封禁恶意IP工具，支持IPv4/IPv6和CIDR格式。

## 特性


## 模块划分

```
blockip/
├── include/          # 头文件目录
│   ├── common.h     # 公共定义和工具函数
│   ├── log.h        # 日志模块
│   ├── ip_utils.h   # IP地址处理工具
│   ├── geo.h        # 地理位置查询
│   ├── nftables.h   # nftables操作接口
│   ├── whitelist.h  # 白名单管理
│   ├── ban.h        # 封禁/解封核心逻辑
│   ├── pam.h        # PAM集成模块
│   ├── stats.h      # 统计和展示
│   └── install.h    # 安装/卸载功能
├── src/             # 源文件目录
│   ├── main.c       # 主程序入口
│   ├── common.c     # 公共函数实现
│   ├── log.c        # 日志功能实现
│   ├── ip_utils.c   # IP处理实现
│   ├── geo.c        # 地理位置实现
│   ├── nftables.c   # nftables实现
│   ├── whitelist.c  # 白名单实现
│   ├── ban.c        # 封禁逻辑实现
│   ├── pam.c        # PAM集成实现
│   ├── stats.c      # 统计功能实现
│   └── install.c    # 安装功能实现
├── Makefile         # 构建脚本
└── README.md        # 本文档
```

## 系统要求


## 编译安装

### 1. 编译程序

```bash
cd blockip
make
```

### 2. 安装到系统（需要root权限）

```bash
sudo make install
```

### 3. 配置系统服务

```bash
sudo bip install
```

这将自动完成以下配置：

## 使用方法

### 查看状态和统计

```bash
# 查看实时统计、活跃封禁列表、日志
bip list

# 显示本地持久化封禁列表
bip show
```

### 手动封禁/解封IP

```bash
# 封禁单个IPv4地址
bip add 1.2.3.4

# 封禁IPv4网段（CIDR）
bip add 1.2.3.0/24

# 封禁IPv6地址
bip add 2001:db8::1

# 封禁IPv6网段
bip add 2001:db8::/32

# 解封IP
bip del 1.2.3.4
```

### 白名单管理

```bash
# 添加IP到白名单
bip vip add 192.168.1.100

# 添加网段到白名单
bip vip add 192.168.0.0/16

# 从白名单移除
bip vip del 192.168.1.100

# 显示白名单列表
bip vip list
```

### 系统管理

```bash
# 从持久化文件恢复黑白名单
bip restore

# 卸载服务
bip uninstall
```

## 工作原理

1. **PAM集成**：通过PAM模块监控SSH登录尝试
2. **失败计数**：记录每个IP的失败登录次数
3. **自动封禁**：达到阈值（默认3次）后自动封禁IP
4. **异步处理**：使用fork子进程异步执行封禁和地理查询，不阻塞SSH登录
5. **nftables规则**：使用nftables的集合(set)功能高效封禁
6. **持久化存储**：封禁记录保存到磁盘，重启后自动恢复
7. **白名单保护**：白名单IP永不封禁
8. **自动解封**：24小时后自动解封（可配置）

## 配置参数

### 动态配置（无需重新编译）

使用配置文件 `/etc/blockip/config` 灵活修改封禁时间：

```bash
# 查看当前配置
bip config

# 设置封禁时间为12小时
bip config time 12h

# 设置封禁时间为30分钟
bip config time 30m

# 设置为永久封禁
bip config time ""

# 设置最大重试次数为5次
bip config retries 5
```

支持的配置参数：
  - `24h` - 24小时
  - `12h` - 12小时
  - `1h` - 1小时
  - `30m` - 30分钟
  - `""` - 永久封禁（空字符串）
  
  - 范围：1-10 次
  - 默认：3 次
  - 说明：SSH登录失败达到此次数后自动封禁

配置文件位置：`/etc/blockip/config`

### 静态配置（需要重新编译）

在 `include/common.h` 中可以修改以下默认参数：

```c
#define MAX_RETRIES 3          // 默认最大失败次数
#define DEFAULT_BAN_TIME "24h" // 默认封禁时长
```

修改后需要重新编译：

```bash
make clean
make
sudo make install
```

## 文件说明

  - `config` - 配置文件（封禁时间等）
  - `blacklist` - 封禁IP列表（持久化）
  - `whitelist` - 白名单列表
  - `counts/` - 失败次数记录目录

## 卸载

```bash
# 完全卸载（会询问是否删除数据文件）
sudo make uninstall
```

或者：

```bash
sudo bip uninstall
```

## 开发和调试

### 编译调试版本

```bash
make debug
```

### 清理编译文件

```bash
make clean
```

### 深度清理（包括配置文件）

```bash
make distclean
```

## 性能优化


## 注意事项

1. **白名单优先**：请先将信任的IP加入白名单，避免误封
2. **网段封禁**：使用CIDR封禁时请谨慎，避免误伤
3. **日志监控**：定期查看日志，了解攻击情况
4. **备份配置**：重要服务器建议备份白名单配置

## 常见问题

### Q: 不小心把自己封禁了怎么办？

A: 通过控制台登录服务器，执行：
```bash
bip del YOUR_IP
bip vip add YOUR_IP
```

### Q: 如何查看当前封禁了多少IP？

A: 执行 `bip list` 查看统计信息

### Q: 封禁时间可以永久吗？

A: 修改 `include/common.h` 中的 `BAN_TIME` 为空字符串 `""`，然后重新编译

### Q: 支持自定义失败次数吗？

A: 修改 `include/common.h` 中的 `MAX_RETRIES` 值，然后重新编译

## 技术特点


## 贡献

欢迎提交Issue和Pull Request！

## 许可证

MIT License

## 作者

原Shell版本：su  
C语言重构：GitHub Copilot

## 更新日志

### v16.2-C (2025-11-18)


**享受更安全的服务器环境！ 🛡️**
