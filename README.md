

# 🚀 脚本工具集

常用 Linux/路由器/服务器 Bash 工具脚本，适合自动化、性能优化、代理配置等场景。

---

## 🛠️ 工具与一键命令

### 1. tcp.sh  —— TCP 网络优化
优化：

```bash
bash <(curl -fsSL "https://raw.githubusercontent.com/sushen339/tools/main/tcp.sh") 1
```

代理加速：

```bash
bash <(curl -fsSL "https://https://raw.githubusercontent.com/sushen339/tools/main/tcp.sh") 1
```


---

### 2. tproxy.sh  —— OpenWrt/路由透明代理自动配置
一键运行：

```bash
bash <(curl -fsSL "https://raw.githubusercontent.com/sushen339/tools/main/tproxy.sh")
```

代理加速：

```bash
bash <(curl -fsSL "https://gh-proxy.com/https://raw.githubusercontent.com/sushen339/tools/main/tproxy.sh")
```

---

### 3. mihomo-install.sh  —— Mihomo 加速核心一键安装
一键安装：

```bash
bash <(curl -fsSL "https://raw.githubusercontent.com/sushen339/tools/main/mihomo-install.sh")
```

代理加速：

```bash
bash <(curl -fsSL "https://gh-proxy.com/https://raw.githubusercontent.com/sushen339/tools/main/mihomo-install.sh")
```

---

### 4. mssh.sh  —— 多主机 SSH 管理与端口转发
一键运行：

```bash
bash <(curl -fsSL "https://raw.githubusercontent.com/sushen339/tools/main/mssh.sh")
```

代理加速：

```bash
bash <(curl -fsSL "https://gh-proxy.com/https://raw.githubusercontent.com/sushen339/tools/main/mssh.sh")
```

---

### 5. curl-cc.sh  —— 模拟浏览器 UA 自动访问签到
一键运行：

```bash
bash <(curl -fsSL "https://raw.githubusercontent.com/sushen339/tools/main/curl-cc.sh")
```

代理加速：

```bash
bash <(curl -fsSL "https://gh-proxy.com/https://raw.githubusercontent.com/sushen339/tools/main/curl-cc.sh")
```

---

### 6. AutoUpdateJdCookie.sh  —— 京东 Cookie 自动更新工具安装

一键安装：

```bash
bash <(curl -fsSL "https://raw.githubusercontent.com/sushen339/tools/main/AutoUpdateJdCookie_install.sh")
```

代理加速：

```bash
bash <(curl -fsSL "https://gh-proxy.com/https://raw.githubusercontent.com/sushen339/tools/main/AutoUpdateJdCookie_install.sh")
```

### 7. nft.sh  —— nftables 防火墙规则配置脚本
一键运行：

```bash
bash <(curl -fsSL "https://raw.githubusercontent.com/sushen339/tools/main/nft.sh")
```
代理加速：

```bash
bash <(curl -fsSL "https://gh-proxy.com/https://raw.githubusercontent.com/sushen339/tools/main/nft.sh")
```

## 8. block-ip.sh  —— 基于SSH登陆的IP 封禁
一键运行：

```bash
wget https://raw.githubusercontent.com/sushen339/tools/main/block-ip.sh -O /tmp/block-ip.sh && bash /tmp/block-ip.sh install
```

### C 语言版本（推荐静态版本）
```bash
wget https://raw.githubusercontent.com/sushen339/tools/main/blockip/bip-static -O /usr/local/bin/bip && chmod +x /usr/local/bin/bip && bip install
```

动态链接版本（需要glibc 2.33+）：
```bash
wget https://raw.githubusercontent.com/sushen339/tools/main/blockip/bip -O /usr/local/bin/bip && chmod +x /usr/local/bin/bip && bip install
```

> **兼容性说明**：  
> - **bip-static**（880K）：静态编译，适用所有Linux发行版（推荐）  
> - **bip**（52K）：动态链接，需要glibc 2.33+（Debian 12+/Ubuntu 22.04+）

> 建议所有脚本以 root 权限运行，详细参数和说明请阅读各脚本头部注释。
